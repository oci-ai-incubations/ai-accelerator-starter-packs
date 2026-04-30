"""Structural invariant for Helm-pack skin override (BUG-020).

enterprise_rag_aiq has a separate `aiq` Helm release (chart `aiq2-web`
v2.0.0) that serves the user-facing frontend; the `rag` release's
frontend override does NOT reach the user. Both releases must carry the
chart-appropriate `frontend.image.{repository,tag}` set entries with the
skin image URI, or the `skin_enterprise_rag_aiq` enum dropdown has no
visible effect.

The two releases use different chart shapes, so the override key paths
differ:
  - `rag` (nvidia-blueprint-rag, flat values): `frontend.image.*`
  - `aiq` (aiq2-web v2.0.0, nested values):   `aiq.apps.frontend.image.*`

The keys were the same flat path in v1.2.1 (chart `aiq-aira`); commit
cfc63e6 upgraded the AIQ chart to v2.0.0 and rewired the override to the
nested path.

See BUGS.md#BUG-020.
"""
import re
from pathlib import Path

import pytest


HELM_TF_PATH = Path(__file__).parent.parent.parent / "helm.tf"

# Every Helm release that serves a user-facing frontend subject to the
# skin dropdown, mapped to the (repository_key, tag_key) pair its chart
# expects in helm_release `set` entries. The keys differ per chart:
#   - `rag` uses the `nvidia-blueprint-rag` chart's flat values
#     (`frontend.image.*`).
#   - `aiq` uses the `aiq2-web` v2.0.0 chart's nested values, where the
#     workload is a sub-chart and its values namespace under `aiq.apps`
#     (`aiq.apps.frontend.image.*`).
# When adding a new Helm pack, append its release name and the exact
# value-key pair the chart expects.
RELEASES_REQUIRING_SKIN_OVERRIDE = {
    "rag": ("frontend.image.repository", "frontend.image.tag"),
    "aiq": ("aiq.apps.frontend.image.repository", "aiq.apps.frontend.image.tag"),
}


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

    @pytest.mark.parametrize(
        "release_name,required_keys",
        RELEASES_REQUIRING_SKIN_OVERRIDE.items(),
    )
    def test_release_has_frontend_image_override(self, release_name, required_keys):
        set_block = _load_release_set_block(release_name)
        assert set_block, (
            f"helm_release {release_name!r} has no `set = [...]` block; cannot verify "
            f"skin override."
        )
        for key in required_keys:
            assert f'"{key}"' in set_block, (
                f"helm_release {release_name!r} is missing required `set` entry for "
                f"{key!r}. Without it, the skin_<category> enum dropdown won't "
                f"replace the frontend image for this pack. See BUGS.md#BUG-020."
            )

    @pytest.mark.parametrize(
        "release_name,required_keys",
        RELEASES_REQUIRING_SKIN_OVERRIDE.items(),
    )
    def test_frontend_image_value_is_split_skin_uri(self, release_name, required_keys):
        """The override value must be `split(":", local.frontend_skin_image_uri)[N]`.

        Catches cases where someone accidentally hardcodes an image in the
        set block (which would work in isolation but breaks the skin dropdown
        feature).
        """
        set_block = _load_release_set_block(release_name)
        repository_key, tag_key = required_keys
        for key, idx in ((repository_key, "0"), (tag_key, "1")):
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
