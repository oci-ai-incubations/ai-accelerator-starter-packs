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
    """frontend_skin enum values match the catalog YAML."""

    @pytest.mark.parametrize("category", CATEGORIES)
    def test_frontend_skin_enum_matches_catalog(self, generated_schemas, category):
        """frontend_skin enum values must match keys in frontend_skins.yaml."""
        schema = generated_schemas[category]
        skin_var = schema["variables"]["frontend_skin"]

        # Load the skin catalog
        catalog_path = Path(__file__).parent.parent / "frontend_skins.yaml"
        with open(catalog_path) as f:
            catalog = yaml.safe_load(f)

        expected_keys = [s["key"] for s in catalog[category]["skins"]]
        assert skin_var["enum"] == expected_keys, (
            f"{category}: frontend_skin enum {skin_var['enum']} "
            f"does not match catalog keys {expected_keys}"
        )
        assert skin_var["default"] == catalog[category]["default"], (
            f"{category}: frontend_skin default '{skin_var['default']}' "
            f"does not match catalog default '{catalog[category]['default']}'"
        )
