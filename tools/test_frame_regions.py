"""Small in-memory tests of pixel ownership, translation and validation."""
from copy import deepcopy
import unittest
from pathlib import Path
from unittest.mock import patch

import numpy as np

from build_frame_regions import (SOURCES, build_regions, confined_source,
                                 normalized_source, selected_sources, validate_regions,
                                 apply_reviewed_support_policy)


def fixture():
    alpha = np.zeros((50, 70), dtype=np.uint8)
    alpha[10:31, 8:24] = 255
    alpha[14:31, 43:57] = 255
    alpha[20, 24:43] = 1  # weak bridge must not merge the two characters
    alpha[8:10, 29:31] = 180  # detached prop, too small to be a body seed
    alpha[0, 0] = 1  # preserve even a remote faint speck
    return alpha


class FrameRegionTests(unittest.TestCase):
    def test_known_cli_source_remains_compatible(self):
        self.assertEqual(selected_sources(None, None, None), SOURCES)
        self.assertEqual(selected_sources(SOURCES[0][0], None, None), (SOURCES[0],))
        self.assertEqual(selected_sources(SOURCES[0][0], 4, 2), (SOURCES[0],))
        with self.assertRaisesRegex(ValueError, "disagrees"):
            selected_sources(SOURCES[0][0], 2, 4)

    def test_new_cli_source_requires_explicit_positive_grid(self):
        source = "animation/new-clip-v1/atlas.png"
        self.assertEqual(selected_sources(source, 4, 2), ((source, 4, 2),))
        for columns, rows in ((None, None), (4, None), (None, 2), (0, 2), (4, -1)):
            with self.subTest(columns=columns, rows=rows):
                with self.assertRaises(ValueError):
                    selected_sources(source, columns, rows)
        with self.assertRaisesRegex(ValueError, "explicit --source"):
            selected_sources(None, 4, 2)

    def test_source_path_rejects_traversal_absolute_and_other_roots(self):
        self.assertEqual(normalized_source(r"animation\new-clip\atlas.png"),
                         "animation/new-clip/atlas.png")
        for source in ("../atlas.png", "animation/../atlas.png", "animation//atlas.png",
                       "animation/./atlas.png", "animation/a/../../atlas.png",
                       "D:/outside.png", "/animation/atlas.png", "//server/share/a.png",
                       "preview/assets/atlas.png", "animation/atlas.png:stream", "animation/x.json"):
            with self.subTest(source=source):
                with self.assertRaises(ValueError):
                    normalized_source(source)

    def test_resolved_redirect_escape_is_rejected_before_open(self):
        # Exercise resolution rejection without requiring Windows symlink rights.
        root = Path.cwd().resolve()
        redirected = root.parent / "outside-atlas.png"
        def fake_resolve(path, strict=False):
            return redirected if path.name == "atlas.png" else path.absolute()
        with patch("build_frame_regions.ROOT", root), patch.object(Path, "resolve", fake_resolve):
            with self.assertRaisesRegex(ValueError, "ordinary file"):
                confined_source("animation/new/atlas.png")

    def test_default_core_size_gate_is_not_relaxed_for_new_sources(self):
        with self.assertRaisesRegex(ValueError, "expected 2 strong character cores; found 0"):
            build_regions(fixture(), 2, 1)

    def test_bridge_and_detached_prop_preserved_once(self):
        alpha = fixture()
        before = alpha.copy()
        data = build_regions(alpha, 2, 1, min_core_pixels=50)
        result = validate_regions(data, alpha)
        self.assertEqual(len(data["frames"]), 2)
        self.assertEqual(result["assignedPixels"], int((alpha > 0).sum()))
        self.assertEqual(data["diagnostics"]["discardedPixels"], 0)
        self.assertGreater(data["diagnostics"]["detachedComponentCount"], 0)
        np.testing.assert_array_equal(alpha, before)

    def test_shared_canvas_translation_never_normalizes_core_size(self):
        data = build_regions(fixture(), 2, 1, min_core_pixels=50)
        self.assertEqual(data["diagnostics"]["scalePerFrame"], 1)
        self.assertEqual(data["canvas"]["width"] % 4, 0)
        heights = [f["diagnostics"]["coreBounds"][3] - f["diagnostics"]["coreBounds"][1]
                   for f in data["frames"]]
        self.assertEqual(heights, [21, 17])
        for frame in data["frames"]:
            x, y, _, _ = frame["sourceBounds"]
            tx, ty = frame["translation"]
            self.assertEqual(frame["placement"], [x + tx, y + ty])

    def test_missing_mask_pixel_fails(self):
        alpha = fixture()
        data = build_regions(alpha, 2, 1, min_core_pixels=50)
        broken = deepcopy(data)
        broken["frames"][0]["rows"].pop(0)
        with self.assertRaisesRegex(ValueError, "exactly cover"):
            validate_regions(broken, alpha)

    def test_translation_drift_fails(self):
        alpha = fixture()
        data = build_regions(alpha, 2, 1, min_core_pixels=50)
        data["frames"][0]["translation"][0] += 1
        with self.assertRaisesRegex(ValueError, "translation"):
            validate_regions(data, alpha)

    def test_reviewed_foot_band_excludes_low_prop_without_changing_pixels(self):
        alpha = np.zeros((80, 120), dtype=np.uint8)
        alpha[10:60, 40:80] = 255  # stationary body
        alpha[60:66, 45:75] = 255  # feet
        alpha[52:62, 15:42] = 255  # held prop pollutes the broad support band
        data = build_regions(alpha, 1, 1, min_core_pixels=50)
        before = deepcopy(data)
        policy = {"id": "fixture-feet", "kind": "fixed-bottom-core-band", "depthPixels": 4}
        apply_reviewed_support_policy(data, alpha, policy)
        self.assertNotEqual(before["frames"][0]["anchorSource"][0], 60)
        self.assertEqual(data["frames"][0]["anchorSource"], [60, 66])
        self.assertEqual(data["canvas"], before["canvas"])
        for key in ("rows", "sourceBounds"):
            self.assertEqual(data["frames"][0][key], before["frames"][0][key])
        self.assertEqual(validate_regions(data, alpha)["assignedPixels"], int((alpha > 0).sum()))
        corrected = deepcopy(data)
        apply_reviewed_support_policy(data, alpha, policy)
        self.assertEqual(data, corrected)

    def test_invalid_reviewed_band_fails_without_partial_translation(self):
        data = build_regions(fixture(), 2, 1, min_core_pixels=50)
        before = deepcopy(data)
        for depth in (True, 0, -1, 18):
            with self.subTest(depth=depth), self.assertRaises(ValueError):
                apply_reviewed_support_policy(data, fixture(), {
                    "kind": "fixed-bottom-core-band", "depthPixels": depth})
            self.assertEqual(data, before)

    def test_reviewed_anchor_cannot_expand_or_overflow_the_canvas(self):
        data = build_regions(fixture(), 2, 1, min_core_pixels=50)
        data["canvas"]["anchorPixels"][0] = 0
        before = deepcopy(data)
        with self.assertRaisesRegex(ValueError, "unchanged common canvas"):
            apply_reviewed_support_policy(data, fixture(), {
                "kind": "fixed-bottom-core-band", "depthPixels": 3})
        self.assertEqual(data, before)


if __name__ == "__main__":
    unittest.main()
