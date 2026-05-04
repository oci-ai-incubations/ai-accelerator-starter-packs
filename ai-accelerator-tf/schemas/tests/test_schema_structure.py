"""Schema structure and validation tests."""
import re
from pathlib import Path

import pytest
import yaml
import jsonschema
from jsonschema import Draft7Validator, FormatChecker


CATEGORIES = ["cuopt", "vss", "paas_rag", "enterprise_rag", "enterprise_rag_aiq", "warehouse_pick_path", "dox_pack"]
DOX_PACK_ONLY_VARIABLES = ("dac_model_id", "dac_unit_shape", "dac_billing_acknowledgement")


def _tf_root() -> Path:
    return Path(__file__).resolve().parent.parent.parent


def _parse_terraform_variable_names() -> set[str]:
    vars_tf = (_tf_root() / "vars.tf").read_text()
    return set(re.findall(r'^variable\s+"([^"]+)"\s*\{', vars_tf, re.MULTILINE))


def _load_common_schema() -> dict:
    with open(_tf_root() / "schemas" / "common_schema.yaml") as f:
        return yaml.safe_load(f)


def _load_frontend_skin_catalog() -> dict:
    with open(_tf_root() / "schemas" / "frontend_skins.yaml") as f:
        return yaml.safe_load(f)


def _get_format_checker():
    """Return FormatChecker with OCI custom format: variablereference."""
    checker = FormatChecker()

    @checker.checks("variablereference")
    def check_variablereference(value):
        return isinstance(value, str) and bool(re.match(r"^[a-zA-Z_][a-zA-Z0-9_]*$", value))

    return checker


def _validate_against_meta_schema(schema_dict, meta_schema):
    """Validate schema against OCI meta schema. Returns list of error messages."""
    validator = Draft7Validator(meta_schema, format_checker=_get_format_checker())
    return [f"{list(e.path)}: {e.message}" for e in validator.iter_errors(schema_dict)]


class TestSchemaValidYaml:
    """All generated schemas parse as valid YAML (verified by loaded fixture)."""

    def test_all_categories_generated(self, generated_schemas):
        assert set(generated_schemas.keys()) == set(CATEGORIES)

    def test_schemas_are_dicts(self, generated_schemas):
        for category, schema in generated_schemas.items():
            assert isinstance(schema, dict), f"{category}: schema must be a dict"


class TestSchemaConformsToMetaSchema:
    """Each schema validates against OCI meta schema."""

    @pytest.mark.parametrize("category", CATEGORIES)
    def test_schema_validates_against_meta_schema(self, generated_schemas, meta_schema, category):
        schema = generated_schemas[category]
        errors = _validate_against_meta_schema(schema, meta_schema)
        if errors:
            msg = f"{category}: meta schema validation failed:\n" + "\n".join(f"  - {e}" for e in errors[:25])
            if len(errors) > 25:
                msg += f"\n  ... and {len(errors) - 25} more"
            pytest.fail(msg)


class TestSchemaHasRequiredKeys:
    """Top-level keys from expectations exist."""

    @pytest.mark.parametrize("category", CATEGORIES)
    def test_required_keys_present(self, generated_schemas, schema_expectations, category):
        schema = generated_schemas[category]
        required = schema_expectations["required_top_level_keys"]
        for key in required:
            assert key in schema, f"{category}: missing required key '{key}'"


class TestStarterPackSizeMatchesConfig:
    """starter_pack_size.enum matches vars.tf for that category."""

    @pytest.mark.parametrize("category", CATEGORIES)
    def test_starter_pack_size_enum(self, generated_schemas, schema_expectations, category):
        schema = generated_schemas[category]
        expected_sizes = schema_expectations["starter_pack_sizes"][category]
        actual = schema["variables"]["starter_pack_size"]["enum"]
        assert actual == expected_sizes, f"{category}: starter_pack_size enum {actual} != expected {expected_sizes}"


class TestOutputGroupsReferenceValidOutputs:
    """Every output in outputGroups exists in schema outputs."""

    @pytest.mark.parametrize("category", CATEGORIES)
    def test_output_references_valid(self, generated_schemas, category):
        schema = generated_schemas[category]
        outputs = schema.get("outputs", {})
        for group in schema.get("outputGroups", []):
            for output_name in group.get("outputs", []):
                assert output_name in outputs, (
                    f"{category}: outputGroups references '{output_name}' but it's not in outputs"
                )


class TestVariableGroupsReferenceValidVariables:
    """Every variable in variableGroups exists in schema variables."""

    @pytest.mark.parametrize("category", CATEGORIES)
    def test_variable_references_valid(self, generated_schemas, category):
        schema = generated_schemas[category]
        variables = schema.get("variables", {})
        for group in schema.get("variableGroups", []):
            for var_name in group.get("variables", []):
                assert var_name in variables, (
                    f"{category}: variableGroups references '{var_name}' but it's not in variables"
                )


class TestTerraformVariablesControlledBySchema:
    """Every Terraform variable must have an ORM schema entry.

    OCI Resource Manager renders Terraform variables that are absent from the
    schema as raw fields, so pack-specific variables need hidden fallbacks in
    common_schema.yaml and visible overrides only in their owner schemas.
    """

    def test_common_schema_declares_every_terraform_variable(self):
        tf_variables = _parse_terraform_variable_names()
        common_variables = set(_load_common_schema().get("variables", {}))
        missing = sorted(tf_variables - common_variables)
        assert missing == [], (
            "common_schema.yaml must declare every Terraform variable so ORM does not "
            f"render raw fields. Add hidden visible:false fallbacks for: {missing}"
        )

    @pytest.mark.parametrize("category", CATEGORIES)
    def test_generated_schema_controls_every_terraform_variable(self, generated_schemas, category):
        tf_variables = _parse_terraform_variable_names()
        schema_variables = set(generated_schemas[category].get("variables", {}))
        missing = sorted(tf_variables - schema_variables)
        assert missing == [], (
            f"{category}: generated schema is missing Terraform variables {missing}. "
            "Missing schema entries leak as raw ORM fields; add hidden fallbacks in common_schema.yaml."
        )


class TestRequiredOutputsAndVariables:
    """Required outputs and variables exist in every schema."""

    @pytest.mark.parametrize("category", CATEGORIES)
    def test_required_outputs_exist(self, generated_schemas, schema_expectations, category):
        schema = generated_schemas[category]
        outputs = schema.get("outputs", {})
        for name in schema_expectations["required_outputs"]:
            assert name in outputs, f"{category}: required output '{name}' missing"

    @pytest.mark.parametrize("category", CATEGORIES)
    def test_required_variables_exist(self, generated_schemas, schema_expectations, category):
        schema = generated_schemas[category]
        variables = schema.get("variables", {})
        for name in schema_expectations["required_variables"]:
            assert name in variables, f"{category}: required variable '{name}' missing"


def _property_matches(actual, expected, prop_name):
    """Check if actual matches expected for a property.

    Skip when the schema has a nested value (dict) but expectations list a simple value
    (e.g. true, false, string). We cannot compare a dict to true/false, so we skip.
    """
    if expected is None:
        return True
    # Schema has nested value (e.g. visible: {eq: [...]}), expectations have simple value
    if isinstance(actual, dict) and not isinstance(expected, dict):
        return None  # Skip - can't compare
    # When visible is absent (None), treat as True for "shown" (default when in variableGroups)
    if prop_name == "visible" and actual is None and expected is True:
        return True
    return actual == expected


class TestCategorySpecificExpectations:
    """Category-specific required/absent and property checks."""

    @pytest.mark.parametrize("category", CATEGORIES)
    def test_category_required_exist(self, generated_schemas, schema_expectations, category):
        cat = schema_expectations.get("category_specific", {}).get(category, {})
        required_outputs = cat.get("required_outputs", [])
        required_variables = cat.get("required_variables", [])
        schema = generated_schemas[category]
        for name in required_outputs:
            assert name in schema.get("outputs", {}), f"{category}: category required output '{name}' missing"
        for name in required_variables:
            assert name in schema.get("variables", {}), f"{category}: category required variable '{name}' missing"

    @pytest.mark.parametrize("category", CATEGORIES)
    def test_category_absent_not_exist(self, generated_schemas, schema_expectations, category):
        """Assert variables/outputs in absent_* do not exist in this category.

        Use absent for: (1) regression guard after removing something,
        (2) guarding against category-inappropriate vars/outputs leaking in.
        This is different from visible: false - absent means not in schema at all;
        visible: false means the variable/output exists but is hidden in the UI.
        """
        cat = schema_expectations.get("category_specific", {}).get(category, {})
        absent_outputs = cat.get("absent_outputs", [])
        absent_variables = cat.get("absent_variables", [])
        schema = generated_schemas[category]
        for name in absent_outputs:
            assert name not in schema.get("outputs", {}), f"{category}: output '{name}' must NOT exist"
        for name in absent_variables:
            assert name not in schema.get("variables", {}), f"{category}: variable '{name}' must NOT exist"

    @pytest.mark.parametrize("category", CATEGORIES)
    def test_category_variable_properties(self, generated_schemas, schema_expectations, category):
        cat = schema_expectations.get("category_specific", {}).get(category, {})
        props = cat.get("variable_properties", {})
        schema = generated_schemas[category]
        variables = schema.get("variables", {})
        for key, expected_props in props.items():
            assert key in variables, f"{category}: variable '{key}' missing (needed for property check)"
            var = variables[key]
            for prop_name, expected_val in expected_props.items():
                actual = var.get(prop_name)
                result = _property_matches(actual, expected_val, prop_name)
                if result is None:
                    continue  # Skip complex type
                assert result, (
                    f"{category}: variable '{key}' property '{prop_name}' = {actual!r} != expected {expected_val!r}"
                )

    @pytest.mark.parametrize("category", CATEGORIES)
    def test_category_output_properties(self, generated_schemas, schema_expectations, category):
        cat = schema_expectations.get("category_specific", {}).get(category, {})
        props = cat.get("output_properties", {})
        schema = generated_schemas[category]
        outputs = schema.get("outputs", {})
        for key, expected_props in props.items():
            assert key in outputs, f"{category}: output '{key}' missing (needed for property check)"
            out = outputs[key]
            for prop_name, expected_val in expected_props.items():
                actual = out.get(prop_name)
                result = _property_matches(actual, expected_val, prop_name)
                if result is None:
                    continue  # Skip complex type
                assert result, (
                    f"{category}: output '{key}' property '{prop_name}' = {actual!r} != expected {expected_val!r}"
                )


class TestPackExclusiveVariables:
    """Variables owned by one pack stay hidden in every other generated schema."""

    @pytest.mark.parametrize("category", CATEGORIES)
    def test_dac_variables_visible_only_for_dox_pack(self, generated_schemas, category):
        variables = generated_schemas[category].get("variables", {})
        for name in DOX_PACK_ONLY_VARIABLES:
            assert name in variables, f"{category}: missing schema control for dox_pack-only variable {name}"
            expected_visible = category == "dox_pack"
            assert variables[name].get("visible") is expected_visible, (
                f"{category}: {name} visible={variables[name].get('visible')!r}; "
                f"expected {expected_visible!r} because DAC fields are dox_pack-only"
            )


class TestVariableTypesComplete:
    """Verify that all variables have required type properties."""

    @pytest.mark.parametrize("category", ["cuopt", "vss", "paas_rag", "enterprise_rag"])
    def test_all_variables_have_type(self, generated_schemas, category):
        """Every variable must have a 'type' property defined."""
        schema = generated_schemas[category]
        variables = schema.get("variables", {})

        missing_type = []
        for var_name, var_def in variables.items():
            if "type" not in var_def:
                missing_type.append(var_name)

        assert not missing_type, (
            f"{category}: variables without 'type' property: {', '.join(missing_type)}"
        )

    @pytest.mark.parametrize("category", ["cuopt", "vss", "paas_rag", "enterprise_rag"])
    def test_complex_variables_have_required_properties(self, generated_schemas, category):
        """Map/List variables must have 'valueType'; Object variables must have 'attributes'."""
        schema = generated_schemas[category]
        variables = schema.get("variables", {})

        for var_name, var_def in variables.items():
            var_type = var_def.get("type")

            if var_type == "map" or var_type == "list":
                assert "valueType" in var_def, (
                    f"{category}: variable '{var_name}' has type '{var_type}' "
                    f"but missing required 'valueType' property"
                )
            elif var_type == "object":
                assert "attributes" in var_def, (
                    f"{category}: variable '{var_name}' has type 'object' "
                    f"but missing required 'attributes' property"
                )


class TestFrontendSkinCatalogSync:
    """Multi-skin catalog synchronization tests."""

    BLUEPRINT_PACKS = ["cuopt", "vss", "paas_rag", "warehouse_pick_path", "dox_pack"]
    HELM_PACKS = ["enterprise_rag", "enterprise_rag_aiq"]

    @pytest.mark.parametrize("category", BLUEPRINT_PACKS)
    def test_frontend_skin_booleans_match_catalog(self, generated_schemas, category):
        """Every blueprint-pack catalog entry must have a boolean variable in the schema
        whose default matches the catalog's default_enabled."""
        schema = generated_schemas[category]
        catalog_path = Path(__file__).parent.parent / "frontend_skins.yaml"
        with open(catalog_path) as f:
            catalog = yaml.safe_load(f)
        for skin in catalog[category]["skins"]:
            var_name = skin["variable_name"]
            assert var_name in schema["variables"], (
                f"{category}: schema missing boolean variable {var_name}"
            )
            var_def = schema["variables"][var_name]
            assert var_def["type"] == "boolean", f"{category}: {var_name} not boolean"
            assert var_def["default"] == skin["default_enabled"], (
                f"{category}: {var_name} default {var_def['default']!r} != "
                f"catalog default_enabled {skin['default_enabled']!r}"
            )

    @pytest.mark.parametrize("category", CATEGORIES)
    def test_foreign_frontend_skin_booleans_are_hidden_and_default_false(self, generated_schemas, category):
        """A skin toggle is visible only in the pack that owns that skin."""
        catalog = _load_frontend_skin_catalog()
        owner_by_var = {
            skin["variable_name"]: owner
            for owner, pack in catalog.items()
            if isinstance(pack, dict)
            for skin in pack.get("skins", [])
            if "variable_name" in skin
        }
        variables = generated_schemas[category].get("variables", {})

        for var_name, owner in owner_by_var.items():
            if owner == category:
                continue
            assert var_name in variables, (
                f"{category}: missing hidden fallback for foreign frontend skin {var_name}"
            )
            var_def = variables[var_name]
            assert var_def.get("visible") is False, (
                f"{category}: foreign frontend skin {var_name} from {owner} must be visible:false"
            )
            assert var_def.get("default") is False, (
                f"{category}: foreign frontend skin {var_name} from {owner} must default false"
            )

    @pytest.mark.parametrize("category", HELM_PACKS)
    def test_helm_packs_expose_single_skin_enum(self, generated_schemas, category):
        """Helm packs surface ONE pack-level enum (skin_<category>) for single-select.

        The enum's values come from the catalog's skin keys; its default comes
        from the catalog's top-level `default:` key. Blueprint-pack per-skin
        booleans (skin_cuopt_core, skin_vss_core, etc.) stay visible=false in
        Helm-pack schemas via the common_schema fallbacks — they must NOT
        render as user-visible vars in a Helm-pack wizard.
        """
        schema = generated_schemas[category]
        variables = schema.get("variables", {})
        expected_enum_var = f"skin_{category}"

        # The category's own enum must exist, be visible, type enum, with enum list from catalog.
        assert expected_enum_var in variables, (
            f"{category}: missing {expected_enum_var} enum variable"
        )
        spec = variables[expected_enum_var]
        assert spec.get("visible") is True, f"{category}: {expected_enum_var} must be visible"
        assert spec.get("type") == "enum", (
            f"{category}: {expected_enum_var} must be type=enum, got {spec.get('type')!r}"
        )
        assert "enum" in spec and isinstance(spec["enum"], list) and len(spec["enum"]) >= 1, (
            f"{category}: {expected_enum_var} must declare a non-empty enum list"
        )

        # Enum contents and default must match the catalog — otherwise a stale generator
        # or drifting catalog could silently expose the wrong choices to the user.
        catalog_path = Path(__file__).parent.parent / "frontend_skins.yaml"
        with open(catalog_path) as f:
            catalog = yaml.safe_load(f)
        expected_keys = [s["key"] for s in catalog[category]["skins"]]
        expected_default = catalog[category]["default"]
        assert set(spec["enum"]) == set(expected_keys), (
            f"{category}: enum values {sorted(spec['enum'])!r} do not match catalog keys "
            f"{sorted(expected_keys)!r}"
        )
        assert spec.get("default") == expected_default, (
            f"{category}: enum default {spec.get('default')!r} does not match catalog default "
            f"{expected_default!r}"
        )

        # No OTHER skin_* variable should be user-visible in a Helm-pack wizard.
        stray_visible = [
            v for v, vs in variables.items()
            if v.startswith("skin_") and v != expected_enum_var and vs.get("visible") is True
        ]
        assert stray_visible == [], (
            f"{category}: unexpected VISIBLE foreign skin_* variables {stray_visible}"
        )

        # The Frontend Skins group must exist and contain exactly the enum variable.
        groups = schema.get("variableGroups", [])
        fs_group = next((g for g in groups if g.get("title") == "Frontend Skins"), None)
        assert fs_group is not None, f"{category}: missing 'Frontend Skins' variableGroup"
        assert fs_group.get("variables") == [expected_enum_var], (
            f"{category}: 'Frontend Skins' group must contain exactly [{expected_enum_var!r}], "
            f"got {fs_group.get('variables')!r}"
        )

    def test_skin_catalog_matches_terraform(self):
        """Bidirectional drift check across the two skin-variable shapes:

        Blueprint packs (cuopt/vss/paas_rag):
          - Every catalog entry's variable_name has a `variable "<name>"` in vars.tf.
          - Every catalog entry's variable_name has an entry in skin_enabled_map.
          - Every bool `skin_*` variable in vars.tf corresponds to a catalog entry.
          - Every skin_enabled_map entry corresponds to a catalog entry.

        Helm packs (enterprise_rag/enterprise_rag_aiq):
          - Every Helm-pack category has a `variable "skin_<category>"` in vars.tf.
          - Every Helm-pack category has an entry in helm_skin_enum_map.
          - No spurious skin_<helm_category> entry in skin_enabled_map.
        """
        import re
        repo_root = Path(__file__).parent.parent.parent
        vars_tf = (repo_root / "vars.tf").read_text()
        frontend_skins_tf = (repo_root / "frontend-skins.tf").read_text()
        catalog_path = repo_root / "schemas" / "frontend_skins.yaml"
        with open(catalog_path) as f:
            catalog = yaml.safe_load(f)

        # Blueprint-pack variable_names from the catalog.
        blueprint_cat_vars = set()
        for cat in ("cuopt", "vss", "paas_rag", "warehouse_pick_path", "dox_pack"):
            for skin in catalog[cat]["skins"]:
                if "variable_name" in skin:
                    blueprint_cat_vars.add(skin["variable_name"])

        # Expected Helm-pack enum variable names.
        helm_cat_vars = {f"skin_{cat}" for cat in ("enterprise_rag", "enterprise_rag_aiq")}

        # Parse vars.tf — collect ALL skin_* variables and their types.
        # NOTE: the body capture uses [^}]* which fails if any skin variable later adds
        # a nested block (e.g. validation {}). Guarded by the count assertion below.
        var_decls = re.findall(
            r'^variable\s+"(skin_\w+)"\s*\{([^}]*)\}',
            vars_tf,
            re.MULTILINE | re.DOTALL,
        )
        bool_vars = {name for name, body in var_decls if re.search(r'type\s*=\s*bool\b', body)}
        string_vars = {name for name, body in var_decls if re.search(r'type\s*=\s*string\b', body)}

        # Independent count of skin_* variable declarations — a regression in the
        # body-capture regex above will drop variables from bool_vars/string_vars
        # silently, which would let drift through. Trip it loudly instead.
        declared_count = len(re.findall(r'^variable\s+"skin_\w+"\s*\{', vars_tf, re.MULTILINE))
        assert declared_count == len(var_decls), (
            f"vars.tf has {declared_count} skin_* variable declarations but the body-capture "
            f"regex matched {len(var_decls)} — likely a nested {{}} block broke the pattern. "
            f"Update the regex (brace-counting or python-hcl2) before this test can pass."
        )
        assert declared_count == len(bool_vars) + len(string_vars), (
            f"vars.tf has {declared_count} skin_* variables but only "
            f"{len(bool_vars) + len(string_vars)} have a recognized type (bool/string). "
            f"All skin_* variables must declare type = bool or type = string."
        )

        assert blueprint_cat_vars == bool_vars, (
            f"Blueprint catalog vars {sorted(blueprint_cat_vars)} != "
            f"vars.tf bool skin_* {sorted(bool_vars)}"
        )
        assert helm_cat_vars == string_vars, (
            f"Helm-pack expected enums {sorted(helm_cat_vars)} != "
            f"vars.tf string skin_* {sorted(string_vars)}"
        )

        # skin_enabled_map should ONLY contain blueprint-pack boolean entries.
        map_block_match = re.search(
            r'skin_enabled_map\s*=\s*\{([^}]*)\}',
            frontend_skins_tf,
            re.DOTALL,
        )
        assert map_block_match is not None, "skin_enabled_map block not found in frontend-skins.tf"
        map_body = map_block_match.group(1)
        map_entries = set(
            re.findall(r'"(skin_\w+)"\s*=\s*var\.\1\b', map_body)
        )
        assert blueprint_cat_vars == map_entries, (
            f"Blueprint catalog vars {sorted(blueprint_cat_vars)} != "
            f"skin_enabled_map entries {sorted(map_entries)}"
        )

        # helm_skin_enum_map must cover exactly the Helm pack categories.
        helm_map_match = re.search(
            r'helm_skin_enum_map\s*=\s*\{([^}]*)\}',
            frontend_skins_tf,
            re.DOTALL,
        )
        assert helm_map_match is not None, "helm_skin_enum_map block not found in frontend-skins.tf"
        helm_map_body = helm_map_match.group(1)
        helm_map_entries = set(
            re.findall(r'"(\w+)"\s*=\s*var\.skin_\1\b', helm_map_body)
        )
        assert helm_map_entries == {"enterprise_rag", "enterprise_rag_aiq"}, (
            f"helm_skin_enum_map must cover exactly {{'enterprise_rag','enterprise_rag_aiq'}}, "
            f"got {sorted(helm_map_entries)}"
        )

    @pytest.mark.parametrize("category", BLUEPRINT_PACKS)
    def test_default_enabled_matches_top_level_default(self, category):
        catalog_path = Path(__file__).parent.parent / "frontend_skins.yaml"
        with open(catalog_path) as f:
            catalog = yaml.safe_load(f)
        defaults = [s for s in catalog[category]["skins"] if s.get("default_enabled")]
        assert len(defaults) == 1, (
            f"{category}: expected exactly 1 default_enabled=true, got {len(defaults)}"
        )
        assert defaults[0]["key"] == catalog[category]["default"], (
            f"{category}: default_enabled skin {defaults[0]['key']!r} != "
            f"top-level default {catalog[category]['default']!r}"
        )

    def test_k8s_resource_name_length_limit(self):
        """VSS K8s resource names stay within RFC 1123's 63-character limit.

        Today VSS has one skin (the default) which uses the unsuffixed base name
        'vss-oracle-ux' (14 chars). Non-default skins would append their
        hyphenated variable_name as a suffix. This test guards future skin
        additions.
        """
        catalog_path = Path(__file__).parent.parent / "frontend_skins.yaml"
        with open(catalog_path) as f:
            catalog = yaml.safe_load(f)
        for skin in catalog["vss"]["skins"]:
            safe_name = skin["variable_name"].replace("_", "-")
            candidate = f"vss-oracle-ux-{safe_name}"
            assert len(candidate) <= 63, (
                f"vss skin {skin['variable_name']}: computed K8s name "
                f"{candidate!r} exceeds 63 chars ({len(candidate)})"
            )


class TestDocsCoverage:
    """Every starter pack category must have a backend API contract doc."""

    @staticmethod
    def _parse_categories_from_vars_tf():
        """Extract the category list from the validation block in vars.tf.

        Parses the ``contains([...], var.starter_pack_category)`` expression
        so the test breaks when a new category is added to vars.tf without a
        matching contract doc — no test-file update required.
        """
        vars_tf = (Path(__file__).parent.parent.parent / "vars.tf").read_text()
        m = re.search(
            r'variable\s+"starter_pack_category".*?'
            r'contains\(\[([^\]]+)\]',
            vars_tf,
            re.DOTALL,
        )
        assert m, "Could not find starter_pack_category validation in vars.tf"
        return [s.strip().strip('"') for s in m.group(1).split(",")]

    def test_every_category_has_contract_doc(self):
        """Each category in vars.tf must have a UPPER_CASE.md in docs/skins/contracts/."""
        categories = self._parse_categories_from_vars_tf()
        contracts_dir = Path(__file__).parent.parent.parent.parent / "docs" / "skins" / "contracts"
        missing = []
        for cat in categories:
            expected = contracts_dir / f"{cat.upper()}.md"
            if not expected.exists():
                missing.append(f"{cat} -> {expected.name}")
        assert missing == [], (
            f"Missing backend API contract docs for: {missing}. "
            f"Add a contract doc in docs/skins/contracts/<CATEGORY>.md "
            f"(see existing files for the format)."
        )

    def test_every_category_in_naming_md(self):
        """Each category in vars.tf must have a row in NAMING.md's name mapping table."""
        categories = self._parse_categories_from_vars_tf()
        naming_md = (Path(__file__).parent.parent.parent.parent / "NAMING.md").read_text()
        missing = [cat for cat in categories if f"`{cat}`" not in naming_md]
        assert missing == [], (
            f"Categories missing from NAMING.md: {missing}. "
            f"Add a row to the Name Mapping table in NAMING.md for each new category."
        )
