"""Schema structure and validation tests."""
import re
from pathlib import Path

import pytest
import yaml
import jsonschema
from jsonschema import Draft7Validator, FormatChecker


CATEGORIES = ["cuopt", "vss", "paas_rag", "enterprise_rag", "enterprise_rag_aiq", "warehouse_pick_path"]


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

    BLUEPRINT_PACKS = ["cuopt", "vss", "paas_rag"]
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

    @pytest.mark.parametrize("category", HELM_PACKS)
    def test_helm_packs_have_no_per_skin_variables(self, generated_schemas, category):
        """Helm packs must not have any skin_* variables injected."""
        schema = generated_schemas[category]
        skin_vars = [v for v in schema.get("variables", {}) if v.startswith("skin_")]
        assert skin_vars == [], (
            f"{category}: unexpected skin_* variables {skin_vars} injected"
        )

    def test_skin_catalog_matches_terraform(self):
        """Bidirectional drift check:
           - Every catalog variable_name has a `variable "<name>"` in vars.tf.
           - Every catalog variable_name has an entry in skin_enabled_map.
           - Every skin_* variable in vars.tf corresponds to a catalog entry.
           - Every skin_enabled_map entry corresponds to a catalog entry.
        """
        import re
        repo_root = Path(__file__).parent.parent.parent
        vars_tf = (repo_root / "vars.tf").read_text()
        frontend_skins_tf = (repo_root / "frontend-skins.tf").read_text()
        catalog_path = repo_root / "schemas" / "frontend_skins.yaml"
        with open(catalog_path) as f:
            catalog = yaml.safe_load(f)

        # All catalog variable_names across blueprint packs.
        catalog_vars = set()
        for cat in ("cuopt", "vss", "paas_rag"):
            for skin in catalog[cat]["skins"]:
                if "variable_name" in skin:
                    catalog_vars.add(skin["variable_name"])

        # Variables in vars.tf matching skin_*. Anchor to start-of-line + variable keyword.
        tf_vars = set(re.findall(r'^variable\s+"(skin_\w+)"\s*\{', vars_tf, re.MULTILINE))

        # skin_enabled_map entries — extract the block first, then match inside it.
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

        assert catalog_vars == tf_vars, (
            f"Catalog vars {sorted(catalog_vars)} != vars.tf skin_* {sorted(tf_vars)}"
        )
        assert catalog_vars == map_entries, (
            f"Catalog vars {sorted(catalog_vars)} != skin_enabled_map entries {sorted(map_entries)}"
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
