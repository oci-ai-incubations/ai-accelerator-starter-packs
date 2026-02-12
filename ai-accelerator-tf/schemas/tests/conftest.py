"""Pytest fixtures for schema tests."""
import subprocess
import sys
import yaml
from pathlib import Path

import pytest


def _repo_root() -> Path:
    """Return repository root (parent of ai-accelerator-tf)."""
    return Path(__file__).resolve().parent.parent.parent.parent


def _schemas_dir() -> Path:
    """Return schemas directory."""
    return Path(__file__).resolve().parent.parent


@pytest.fixture(scope="session")
def generated_schemas():
    """Run create_final_schema.py --all and load all generated schemas."""
    repo_root = _repo_root()
    script = repo_root / "create_final_schema.py"
    result = subprocess.run(
        [sys.executable, str(script), "--all"],
        cwd=repo_root,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"create_final_schema.py --all failed: {result.stderr}"

    generated_dir = _schemas_dir() / "generated"
    schemas = {}
    for path in generated_dir.glob("*_schema.yaml"):
        category = path.stem.replace("_schema", "")
        with open(path) as f:
            schemas[category] = yaml.safe_load(f)
    return schemas


@pytest.fixture(scope="session")
def schema_expectations():
    """Load schema_expectations.yaml."""
    path = Path(__file__).parent / "schema_expectations.yaml"
    with open(path) as f:
        return yaml.safe_load(f)


@pytest.fixture(scope="session")
def meta_schema():
    """Load OCI meta schema for validation."""
    path = _schemas_dir() / "meta_schema.yaml"
    with open(path) as f:
        return yaml.safe_load(f)
