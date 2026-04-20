"""Blueprint structure invariants for ai-accelerator-tf/blueprint_files.tf.

These tests enforce cross-cutting rules about how blueprint recipes are
declared, so that future edits don't silently regress features that thread
through every recipe.
"""
import re
from pathlib import Path

import pytest


# Pack-level list comprehensions that build FRONTEND recipes. The recipes
# inside these comprehensions are classified as "frontends (stay open)" in
# app-ingress-auth.tf — they MUST NOT carry the backend bearer-token
# annotation. Add new frontend list-comprehension locals here when the
# catalog grows to Helm-pack multi-skin or similar.
FRONTEND_LIST_COMPREHENSION_LOCALS = [
    "_cuopt_frontend_deployments",
    "_paas_rag_frontend_deployments",
]

# Regex for the attribute every backend recipe must carry. Uses `\s+` instead
# of a single space because Terraform fmt aligns `=` across adjacent attributes,
# so the actual line often has multiple spaces between name and `=`.
REQUIRED_ANNOTATION_RE = re.compile(
    r"recipe_additional_ingress_annotations\s*=\s*local\.backend_ingress_annotations_corrino\b"
)
REQUIRED_ANNOTATION_DESC = (
    "recipe_additional_ingress_annotations = local.backend_ingress_annotations_corrino"
)


def _blueprint_file_path() -> Path:
    return Path(__file__).parent.parent.parent / "blueprint_files.tf"


def _read_lines() -> list[str]:
    return _blueprint_file_path().read_text().split("\n")


def _find_frontend_ranges(lines: list[str]) -> list[tuple[int, int, str]]:
    """Return (start_line, end_line, local_name) for each frontend list comprehension.

    Start is the `<local_name> = [` line; end is the matching `]` at the same
    indent level. Lines are 0-indexed.
    """
    ranges = []
    for local_name in FRONTEND_LIST_COMPREHENSION_LOCALS:
        pattern = re.compile(rf"^(\s*){re.escape(local_name)}\s*=\s*\[")
        for i, line in enumerate(lines):
            m = pattern.match(line)
            if not m:
                continue
            start_indent = m.group(1)
            close_pattern = re.compile(rf"^{re.escape(start_indent)}\]\s*$")
            for j in range(i + 1, len(lines)):
                if close_pattern.match(lines[j]):
                    ranges.append((i, j, local_name))
                    break
            else:
                pytest.fail(
                    f"Could not find matching closing ']' for "
                    f"{local_name} starting at line {i + 1}"
                )
            break  # only one definition per local
    return ranges


def _find_recipe_blocks(lines: list[str]) -> list[tuple[int, int, str]]:
    """Return (start_line, end_line, opener) for every `recipe = {` or
    `recipe = merge(` block. End is the line of the matching close token.
    Lines are 0-indexed.
    """
    blocks: list[tuple[int, int, str]] = []
    for i, line in enumerate(lines):
        # `recipe = {`
        m = re.match(r"^(\s*)recipe\s*=\s*\{", line)
        if m:
            blocks.append((i, _find_matching_brace(lines, i), "{"))
            continue
        # `recipe = merge(`
        m = re.match(r"^(\s*)recipe\s*=\s*merge\(", line)
        if m:
            blocks.append((i, _find_matching_paren(lines, i), "merge("))
            continue
    return blocks


def _find_matching_brace(lines: list[str], open_line: int) -> int:
    """Return the line index of the `}` that closes the `{` on open_line.
    Counts ALL `{`/`}` on subsequent lines. For our purposes this is reliable
    enough because HCL syntax doesn't embed braces in strings in this file.
    """
    # Count the `{` on the open line
    depth = lines[open_line].count("{") - lines[open_line].count("}")
    if depth <= 0:
        return open_line
    for j in range(open_line + 1, len(lines)):
        depth += lines[j].count("{") - lines[j].count("}")
        if depth <= 0:
            return j
    return len(lines) - 1


def _find_matching_paren(lines: list[str], open_line: int) -> int:
    """Same idea for `(`/`)` — tracks parens starting on open_line."""
    depth = lines[open_line].count("(") - lines[open_line].count(")")
    if depth <= 0:
        return open_line
    for j in range(open_line + 1, len(lines)):
        depth += lines[j].count("(") - lines[j].count(")")
        if depth <= 0:
            return j
    return len(lines) - 1


def _block_contains_annotation(lines: list[str], start: int, end: int) -> bool:
    return any(REQUIRED_ANNOTATION_RE.search(lines[i]) for i in range(start, end + 1))


class TestBlueprintAnnotations:
    """Every backend recipe must declare the backend-ingress-auth annotation.

    Rationale: main's PR #102 introduced `add_api_key_to_ingress` as a feature
    flag that requires the `recipe_additional_ingress_annotations =
    local.backend_ingress_annotations_corrino` line on every backend recipe.
    Without the line, that recipe's ingress stays open even when the flag is
    on. Easy to miss when adding a new recipe — this test makes the invariant
    a hard check.

    Frontend recipes (in the allowlisted list comprehensions) are exempt:
    they are explicitly "public" and must NOT have the annotation.
    """

    def test_every_backend_recipe_has_annotation(self):
        lines = _read_lines()
        frontend_ranges = _find_frontend_ranges(lines)

        def in_frontend_range(line_idx: int) -> str | None:
            for start, end, name in frontend_ranges:
                if start <= line_idx <= end:
                    return name
            return None

        blocks = _find_recipe_blocks(lines)
        assert len(blocks) > 0, "No `recipe = {` or `recipe = merge(` blocks found — parser issue?"

        missing = []
        for start, end, opener in blocks:
            if in_frontend_range(start) is not None:
                continue  # frontend recipe, allowlisted
            if not _block_contains_annotation(lines, start, end):
                # Extract a short snippet to help locate the offending recipe
                snippet_start = start
                snippet = " ".join(lines[snippet_start : snippet_start + 4]).strip()
                missing.append((start + 1, snippet[:120]))

        if missing:
            details = "\n".join(
                f"  - line {n}: {preview}" for n, preview in missing
            )
            pytest.fail(
                f"{len(missing)} backend recipe(s) missing required annotation "
                f"`{REQUIRED_ANNOTATION_DESC}`.\n"
                f"Every `recipe = {{` or `recipe = merge(` block in "
                f"blueprint_files.tf must include this line UNLESS it's inside "
                f"one of the frontend list comprehensions "
                f"({FRONTEND_LIST_COMPREHENSION_LOCALS}). "
                f"Add the line, or if this recipe is a new frontend, add the "
                f"enclosing local to FRONTEND_LIST_COMPREHENSION_LOCALS in "
                f"test_blueprint_structure.py.\n"
                f"Missing:\n{details}"
            )

    def test_frontend_recipes_do_not_have_annotation(self):
        """Frontend recipes must stay OPEN — annotation on a frontend would
        break public access to the UI.
        """
        lines = _read_lines()
        frontend_ranges = _find_frontend_ranges(lines)
        blocks = _find_recipe_blocks(lines)

        def in_frontend_range(line_idx: int) -> str | None:
            for start, end, name in frontend_ranges:
                if start <= line_idx <= end:
                    return name
            return None

        offenders = []
        for start, end, _ in blocks:
            frontend_name = in_frontend_range(start)
            if frontend_name is None:
                continue
            if _block_contains_annotation(lines, start, end):
                offenders.append((start + 1, frontend_name))

        if offenders:
            details = "\n".join(
                f"  - line {n}: in {name}" for n, name in offenders
            )
            pytest.fail(
                f"{len(offenders)} frontend recipe(s) unexpectedly carry the "
                f"backend bearer-token annotation. Frontend recipes must stay "
                f"open (no annotation).\n{details}"
            )

    def test_frontend_allowlist_resolves(self):
        """Catch typos in FRONTEND_LIST_COMPREHENSION_LOCALS — every entry
        must actually exist in blueprint_files.tf with the expected shape.
        """
        lines = _read_lines()
        found = _find_frontend_ranges(lines)
        found_names = {name for _, _, name in found}
        expected = set(FRONTEND_LIST_COMPREHENSION_LOCALS)
        missing = expected - found_names
        assert missing == set(), (
            f"FRONTEND_LIST_COMPREHENSION_LOCALS entries not found in "
            f"blueprint_files.tf: {sorted(missing)}. Either the local was "
            f"renamed or deleted (update the allowlist) or the local's "
            f"definition doesn't match `<name> = [` followed by a closing "
            f"`]` at the same indent."
        )
