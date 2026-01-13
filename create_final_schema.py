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


def deep_merge(base: dict, override: dict) -> dict:
    """
    Deep merge override into base, returning new dict.
    
    - Dicts are recursively merged
    - Lists are replaced entirely (not appended)
    - All other values are replaced
    """
    result = deepcopy(base)
    for key, value in override.items():
        if key in result and isinstance(result[key], dict) and isinstance(value, dict):
            result[key] = deep_merge(result[key], value)
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


def represent_str(dumper, data):
    """Custom string representer to handle multiline strings nicely."""
    if '\n' in data:
        return dumper.represent_scalar('tag:yaml.org,2002:str', data, style='|')
    return dumper.represent_scalar('tag:yaml.org,2002:str', data)

def get_args():
    parser = argparse.ArgumentParser(description="Generate schema.yaml from common and category-specific schemas")
    parser.add_argument("-c", "--category", choices=["cuopt", "paas_rag", "vss"], required=True, help="Category to generate schema for (cuopt, vss, paas_rag)")
    return parser.parse_args()

def main():
    args = get_args()
    category = args.category
    print(f"Building schema for category: {category}")
    
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
    
    # Load category-specific schema
    category_path = schemas_dir / f"{category}_schema.yaml"
    if category_path.exists():
        print(f"Loading category overrides from: {category_path}")
        with open(category_path) as f:
            category_schema = yaml.safe_load(f)
        final = deep_merge(common, category_schema)
    else:
        print(f"Warning: No category schema found at {category_path}, using common only")
        final = common
    
    # Set up custom YAML dumper
    yaml.add_representer(str, represent_str)
    
    # Write final schema
    output_path = tf_dir / "schema.yaml"
    with open(output_path, 'w') as f:
        f.write("# AUTO-GENERATED - Do not edit directly!\n")
        f.write(f"# Generated from: common_schema.yaml + {category}_schema.yaml\n")
        f.write("# Regenerate with: python create_final_schema.py\n")
        f.write("#\n")
        f.write(f"# Category: {category}\n")
        f.write("\n")
        yaml.dump(final, f, default_flow_style=False, sort_keys=False, allow_unicode=True, width=120)
    
    print(f"Generated: {output_path}")
    print("Done!")


if __name__ == "__main__":
    main()

