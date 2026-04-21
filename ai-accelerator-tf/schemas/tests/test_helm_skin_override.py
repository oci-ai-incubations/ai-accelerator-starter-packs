"""Structural invariant for Helm-pack skin override (BUG-020).

enterprise_rag_aiq has a separate `aiq-aira` Helm release that serves the
user-facing frontend; the `rag` release's frontend override does NOT reach
the user. Both releases must carry `frontend.image.repository` and
`frontend.image.tag` set blocks with the skin image URI, or the
`skin_enterprise_rag_aiq` enum dropdown has no visible effect.

See BUGS.md#BUG-020.
"""
import re
from pathlib import Path

import pytest


HELM_TF_PATH = Path(__file__).parent.parent.parent / "helm.tf"

# Each release's set block must contain both of these
REQUIRED_KEYS = ("frontend.image.repository", "frontend.image.tag")

# Every Helm release that serves a user-facing frontend subject to the
# skin dropdown. The `rag` release serves enterprise_rag's user-facing
# frontend directly; the `aiq` release serves enterprise_rag_aiq's
# user-facing frontend (BUG-020 — both releases need the override).
RELEASES_REQUIRING_SKIN_OVERRIDE = ["rag", "aiq"]


def _load_release_set_block(release_name: str) -> str:
    """Return the entire `set = [ ... ]` block for a given helm_release.

    Uses a simple brace-counting parser — HCL in this file doesn't embed
    `[`/`]` in strings inside these set blocks.
    """
    content = HELM_TF_PATH.read_text()
    # Find the resource declaration
    m = re.search(
        rf'resource\s+"helm_release"\s+"{re.escape(release_name)}"\s*\{{',
        content,
    )
    if not m:
        pytest.fail(f"helm_release {release_name!r} not found in helm.tf")
    # Find the resource's closing brace by bracket-counting from the opening
    start = m.end() - 1
    depth = 0
    end = start
    for i in range(start, len(content)):
        if content[i] == "{":
            depth += 1
        elif content[i] == "}":
            depth -= 1
            if depth == 0:
                end = i
                break
    resource_body = content[start : end + 1]

    # Locate the `set = [` OR `set = concat(` assignment. The rag release uses
    # concat() to conditionally combine set entries; the aiq release uses a
    # flat list. We need to support both. `(?!\w)` prevents matching
    # `set_sensitive`.
    set_match = re.search(r"\bset(?!\w)\s*=\s*(\[|concat\()", resource_body)
    if not set_match:
        return ""
    opener = set_match.group(1)
    closer = "]" if opener == "[" else ")"
    depth = 1
    start = set_match.end()
    for i in range(start, len(resource_body)):
        if resource_body[i] == opener[0]:
            depth += 1
        elif resource_body[i] == closer:
            depth -= 1
            if depth == 0:
                return resource_body[set_match.start() : i + 1]
    return resource_body[set_match.start() :]


class TestHelmSkinOverride:
    """BUG-020: Helm-pack skin override must reach every user-facing frontend."""

    @pytest.mark.parametrize("release_name", RELEASES_REQUIRING_SKIN_OVERRIDE)
    def test_release_has_frontend_image_override(self, release_name):
        set_block = _load_release_set_block(release_name)
        assert set_block, (
            f"helm_release {release_name!r} has no `set = [...]` block; cannot verify "
            f"skin override."
        )
        for key in REQUIRED_KEYS:
            assert f'"{key}"' in set_block, (
                f"helm_release {release_name!r} is missing required `set` entry for "
                f"{key!r}. Without it, the skin_<category> enum dropdown won't "
                f"replace the frontend image for this pack. See BUGS.md#BUG-020."
            )

    @pytest.mark.parametrize("release_name", RELEASES_REQUIRING_SKIN_OVERRIDE)
    def test_frontend_image_value_is_split_skin_uri(self, release_name):
        """The override value must be `split(":", local.frontend_skin_image_uri)[N]`.

        Catches cases where someone accidentally hardcodes an image in the
        set block (which would work in isolation but breaks the skin dropdown
        feature).
        """
        set_block = _load_release_set_block(release_name)
        # Find the two lines and verify each references frontend_skin_image_uri
        for key, idx in (("frontend.image.repository", "0"), ("frontend.image.tag", "1")):
            # Find the `name = "<key>"` line, then look at the following `value = ...`
            pattern = rf'name\s*=\s*"{re.escape(key)}"\s*\n?\s*value\s*=\s*(.+)'
            m = re.search(pattern, set_block)
            assert m, (
                f"helm_release {release_name!r}: cannot find value line for {key!r} "
                f"inside the set block."
            )
            value = m.group(1).strip().rstrip(",").rstrip("}").strip()
            expected_substr = f'split(":", local.frontend_skin_image_uri)[{idx}]'
            assert expected_substr in value, (
                f"helm_release {release_name!r}: `{key}` value {value!r} does not use "
                f"`{expected_substr}`. The skin dropdown feeds via "
                f"local.frontend_skin_image_uri; overriding with anything else breaks "
                f"the feature for this pack."
            )
