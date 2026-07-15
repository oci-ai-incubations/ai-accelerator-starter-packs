#!/usr/bin/env python3
"""
Merge common schema with category-specific overrides to create final schema.yaml

Usage:
    python create_final_schema.py [category]

If category is not provided, it reads from starter_pack_category.auto.tfvars
"""
import yaml
import argparse
import sys
import re
from pathlib import Path
from copy import deepcopy


def merge_list_by_key(base_list: list, override_list: list, key: str) -> list:
    """
    Merge two lists of dicts by a key field.
    
    - Items in override with matching key replace base items
    - Items only in base are preserved
    - Items only in override are added
    - Order: base items first (in original order), then new override items
    """
    if not base_list:
        return deepcopy(override_list) if override_list else []
    if not override_list:
        return deepcopy(base_list)
    
    # Build lookup of override items by key
    override_by_key = {item.get(key): item for item in override_list if isinstance(item, dict)}
    
    result = []
    seen_keys = set()
    
    # Process base items - keep or replace with override
    for item in base_list:
        if isinstance(item, dict):
            item_key = item.get(key)
            if item_key in override_by_key:
                result.append(deepcopy(override_by_key[item_key]))
            else:
                result.append(deepcopy(item))
            if item_key:
                seen_keys.add(item_key)
        else:
            result.append(deepcopy(item))
    
    # Add new items from override that weren't in base
    for item in override_list:
        if isinstance(item, dict):
            item_key = item.get(key)
            if item_key and item_key not in seen_keys:
                result.append(deepcopy(item))
    
    return result


def deep_merge(base: dict, override: dict) -> dict:
    """
    Deep merge override into base, returning new dict.
    
    - Dicts are recursively merged
    - outputGroups and variableGroups are merged by 'title' field
    - Other lists are replaced entirely
    - All other values are replaced
    """
    # Keys that should merge lists by 'title' instead of replacing
    LIST_MERGE_BY_TITLE = {'outputGroups', 'variableGroups'}
    
    result = deepcopy(base)
    for key, value in override.items():
        if key in result and isinstance(result[key], dict) and isinstance(value, dict):
            result[key] = deep_merge(result[key], value)
        elif key in LIST_MERGE_BY_TITLE and isinstance(result.get(key), list) and isinstance(value, list):
            result[key] = merge_list_by_key(result[key], value, 'title')
        else:
            result[key] = deepcopy(value)
    return result


def get_category_from_tfvars(tfvars_path: Path) -> str:
    """Read starter_pack_category from .auto.tfvars file."""
    content = tfvars_path.read_text()
    match = re.search(r'starter_pack_category\s*=\s*"(\w+)"', content)
    if not match:
        raise ValueError(f"Could not find starter_pack_category in {tfvars_path}")
    return match.group(1)


def update_tfvars_category(tfvars_path: Path, category: str) -> None:
    """Update starter_pack_category in .auto.tfvars file."""
    content = tfvars_path.read_text()
    # Replace the category value, preserving the rest of the file
    updated_content = re.sub(
        r'(starter_pack_category\s*=\s*)"[^"]*"',
        f'\\1"{category}"',
        content
    )
    tfvars_path.write_text(updated_content)


def represent_str(dumper, data):
    """Custom string representer to handle multiline strings nicely."""
    if '\n' in data:
        return dumper.represent_scalar('tag:yaml.org,2002:str', data, style='|')
    return dumper.represent_scalar('tag:yaml.org,2002:str', data)

def inject_frontend_skin_toggles(merged_schema, skins_data, category, learn_more_url):
    """Inject per-skin selection variables into the merged schema.

    Two shapes, chosen by the catalog:
      - Blueprint packs (cuopt/vss/paas_rag): catalog entries declare a
        `variable_name` and `default_enabled`. We inject one boolean variable
        per skin; users can enable any combination (multi-select).
      - Helm packs (enterprise_rag/enterprise_rag_aiq): catalog entries have
        no `variable_name`. We inject a single enum variable named
        `skin_<category>` whose enum list is every skin key in the catalog and
        whose default is the catalog's top-level `default:`. Users pick one
        (single-select).

    Both shapes land in a dedicated 'Frontend Skins' variableGroup inserted
    after 'Deployment Configuration' so the skin selection is a discoverable
    section in the ORM UI.
    """
    if skins_data is None or category not in skins_data:
        return
    skins = skins_data[category].get("skins", [])
    if not skins:
        return

    per_skin_variable_names = [s.get("variable_name") for s in skins if s.get("variable_name")]
    # Helm pack indicator: no per-skin variable_names in the catalog.
    is_helm_pack = len(per_skin_variable_names) == 0

    # Variable names to place in the group (in catalog order).
    group_var_names = []

    if is_helm_pack:
        # Single enum var for Helm packs.
        enum_var_name = f"skin_{category}"
        default_key = skins_data[category].get("default", skins[0]["key"])
        # Catch catalog typos where `default:` doesn't match any `key:`. Without this
        # the ORM wizard renders an out-of-range default that users can't select.
        available_keys = [s["key"] for s in skins]
        if default_key not in available_keys:
            raise ValueError(
                f"Catalog default {default_key!r} for {category} is not in the skin keys "
                f"{available_keys!r}. Fix schemas/frontend_skins.yaml."
            )
        merged_schema.setdefault("variables", {})[enum_var_name] = {
            "type": "enum",
            "title": "Frontend Skin",
            "description": (
                "Choose which frontend UI to deploy for this Helm-based pack. "
                f"Only one skin can be active at a time. <a href='{learn_more_url}'>Learn more</a>"
            ),
            "enum": [skin["key"] for skin in skins],
            "default": default_key,
            "required": True,
            "visible": True,
        }
        group_var_names.append(enum_var_name)
    else:
        # Blueprint packs: one boolean per skin.
        for skin in skins:
            var_name = skin.get("variable_name")
            if not var_name:
                continue
            merged_schema.setdefault("variables", {})[var_name] = {
                "type": "boolean",
                "title": skin["key"],
                "description": f"Enable this frontend skin. <a href='{learn_more_url}'>Learn more</a>",
                "default": skin.get("default_enabled", False),
                "required": True,
                "visible": True,
            }
            group_var_names.append(var_name)

    if not group_var_names:
        return  # Nothing to inject (shouldn't happen given the guards above).

    variable_groups = merged_schema.setdefault("variableGroups", [])

    # Find or create the "Frontend Skins" group.
    #
    # NOTE: OCI Resource Manager variableGroups support only `title`, `variables`, and `visible`.
    # A `description` key is rejected by the ORM schema validator ("Errors exist in your schema
    # file") — the Redwood UI never rendered group descriptions anyway — so we must NOT set one.
    skin_group = None
    for group in variable_groups:
        if group.get("title") == "Frontend Skins":
            skin_group = group
            break
    if skin_group is None:
        skin_group = {
            "title": "Frontend Skins",
            "variables": [],
        }
        # Insert right after "Deployment Configuration" if present, else append.
        insert_at = len(variable_groups)
        for idx, group in enumerate(variable_groups):
            if group.get("title") == "Deployment Configuration":
                insert_at = idx + 1
                break
        variable_groups.insert(insert_at, skin_group)
    # Defensively strip any description a base schema or older run may have added.
    skin_group.pop("description", None)

    # Populate in catalog order.
    for var_name in group_var_names:
        if var_name not in skin_group["variables"]:
            skin_group["variables"].append(var_name)
        # Also make sure the variable is NOT in Deployment Configuration (older
        # generations may have placed it there).
        for group in variable_groups:
            if group.get("title") == "Deployment Configuration" and var_name in group.get("variables", []):
                group["variables"].remove(var_name)


def inject_frontend_skin_url_map_output(merged_schema, skins_data):
    """Declare frontend_skin_urls as a map output and add to the Frontend group."""
    if skins_data is None:
        return
    merged_schema.setdefault("outputs", {})["frontend_skin_urls"] = {
        "type": "map",
        "title": "Frontend URLs",
        "visible": True,
    }
    target_group = None
    for group in merged_schema.get("outputGroups", []):
        if group.get("title") in ("Frontend", "Frontend Skin"):
            target_group = group
            break
    if target_group is not None:
        target_group["title"] = "Frontend"
        if "frontend_skin_urls" not in target_group["outputs"]:
            target_group["outputs"].insert(0, "frontend_skin_urls")
        target_group["outputs"] = [o for o in target_group["outputs"] if o != "frontend_skin_image_uri"]


CATEGORIES = ["cuopt", "vss", "paas_rag", "enterprise_rag", "enterprise_rag_aiq", "warehouse_pick_path", "dox_pack", "agent_observability"]


def get_args():
    parser = argparse.ArgumentParser(description="Generate schema.yaml from common and category-specific schemas")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("-c", "--category", choices=CATEGORIES, help="Category to generate schema for")
    group.add_argument("--all", action="store_true", help="Generate schemas for all categories to schemas/generated/")
    return parser.parse_args()


def generate_schema_for_category(common: dict, category: str, schemas_dir: Path, output_path: Path, skins_data: dict = None) -> None:
    """Generate merged schema for a single category and write to output_path."""
    category_path = schemas_dir / f"{category}_schema.yaml"
    if category_path.exists():
        with open(category_path) as f:
            category_schema = yaml.safe_load(f)
        final = deep_merge(common, category_schema)
    else:
        final = deepcopy(common)

    # Inject per-skin boolean toggles and frontend_skin_urls map output after merge
    if skins_data:
        learn_more_url = skins_data.get("learn_more_url", "")
        inject_frontend_skin_toggles(final, skins_data, category, learn_more_url)
        inject_frontend_skin_url_map_output(final, skins_data)

    with open(output_path, 'w') as f:
        f.write("# AUTO-GENERATED - Do not edit directly!\n")
        f.write(f"# Generated from: common_schema.yaml + {category}_schema.yaml\n")
        f.write("# Regenerate with: python create_final_schema.py --all\n")
        f.write("#\n")
        f.write(f"# Category: {category}\n")
        f.write("\n")
        yaml.dump(final, f, default_flow_style=False, sort_keys=False, allow_unicode=True, width=120)


def main():
    args = get_args()
    script_dir = Path(__file__).parent
    tf_dir = script_dir / "ai-accelerator-tf"
    schemas_dir = tf_dir / "schemas"

    # Load common schema
    common_path = schemas_dir / "common_schema.yaml"
    if not common_path.exists():
        print(f"Error: Common schema not found at {common_path}")
        sys.exit(1)

    with open(common_path) as f:
        common = yaml.safe_load(f)

    # Load frontend skins catalog
    skins_path = schemas_dir / "frontend_skins.yaml"
    skins_data = None
    if skins_path.exists():
        with open(skins_path) as f:
            skins_data = yaml.safe_load(f)

    yaml.add_representer(str, represent_str)

    if args.all:
        generated_dir = schemas_dir / "generated"
        generated_dir.mkdir(exist_ok=True)
        for category in CATEGORIES:
            print(f"Building schema for category: {category}")
            output_path = generated_dir / f"{category}_schema.yaml"
            generate_schema_for_category(common, category, schemas_dir, output_path, skins_data)
            print(f"  Generated: {output_path}")
        print("Done!")
    else:
        category = args.category
        print(f"Building schema for category: {category}")

        # Update starter_pack_category in .auto.tfvars file
        tfvars_path = tf_dir / "starter_pack_category.auto.tfvars"
        if tfvars_path.exists():
            print(f"Updating {tfvars_path} with category: {category}")
            update_tfvars_category(tfvars_path, category)
        else:
            print(f"Warning: {tfvars_path} not found, skipping update")

        output_path = tf_dir / "schema.yaml"
        generate_schema_for_category(common, category, schemas_dir, output_path, skins_data)
        print(f"Generated: {output_path}")
        print("Done!")


if __name__ == "__main__":
    main()

