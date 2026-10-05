"""Contract regressions using existing art read-only; no image or fixture writes."""
import copy
import hashlib
from pathlib import Path
import unittest

from validate_animation_catalog import ROOT, validate_catalog


class CatalogContractTests(unittest.TestCase):
    def setUp(self):
        atlas = Path("animation/yawn-v1/atlas-eyes-v2.png")
        self.catalog = {
            "master": {"id": "test-master", "anchorNormalized": [0.5, 0.88], "scale": 1,
                       "cellAspect": 1, "displayRectNormalized": [0.1, 0.25, 0.8, 0.671]},
            "clips": [{"id": "yawn", "title": "Test existing atlas", "category": "once",
                       "status": "direction-accepted", "triggerKinds": ["manual"],
                       "atlas": atlas.as_posix(), "columns": 4, "rows": 2, "frameCount": 8,
                       "width": 1774, "height": 887, "durationsMs": [100] * 8,
                       "sha256": hashlib.sha256((ROOT / atlas).read_bytes()).hexdigest()}],
        }

    def codes(self, report):
        return {issue["code"] for issue in report["errors"]}

    def test_fractional_grid_is_fixed_and_not_fatal(self):
        before = (ROOT / self.catalog["clips"][0]["atlas"]).read_bytes()
        report = validate_catalog(self.catalog)
        self.assertEqual(report["errors"], [])
        self.assertEqual(report["clips"][0]["sourceCellSize"], [443.5, 443.5])
        self.assertEqual(report["clips"][0]["sourceCells"][1]["sourceRect"], [443.5, 0, 443.5, 443.5])
        self.assertEqual(report["artApproval"], "not-assessed")
        self.assertEqual(before, (ROOT / self.catalog["clips"][0]["atlas"]).read_bytes())

    def test_double_blink_can_reuse_source_cells(self):
        clip = self.catalog["clips"][0]
        clip.update(frameCount=16, frameIndices=list(range(8)) * 2, durationsMs=[80] * 16)
        report = validate_catalog(self.catalog)
        self.assertEqual(report["errors"], [])
        self.assertEqual(len(report["clips"][0]["sourceCells"]), 8)
        self.assertEqual(report["clips"][0]["playbackFrameCount"], 16)

    def test_invalid_indices_and_duration_are_rejected(self):
        self.catalog["clips"][0]["frameIndices"] = [0, 1, 2, 3, 4, 5, 6, 8]
        self.assertIn("frame-indices", self.codes(validate_catalog(self.catalog)))
        del self.catalog["clips"][0]["frameIndices"]
        self.catalog["clips"][0]["durationsMs"][-1] = 0
        self.assertIn("frame-durations", self.codes(validate_catalog(self.catalog)))

    def test_exact_bytes_and_dimensions_are_required(self):
        self.catalog["clips"][0]["sha256"] = "0" * 64
        self.assertIn("sha256-mismatch", self.codes(validate_catalog(self.catalog)))
        self.catalog["clips"][0]["width"] = 1776
        self.assertIn("atlas-size", self.codes(validate_catalog(self.catalog)))

    def test_alpha_fitting_and_frame_transforms_are_rejected(self):
        self.catalog["clips"][0]["fitToAlpha"] = True
        self.catalog["clips"][0]["frames"] = [{"scale": 1.1}]
        codes = self.codes(validate_catalog(self.catalog))
        self.assertIn("per-frame-fit", codes)
        self.assertIn("per-frame-transform", codes)

    def test_common_clip_scale_allowed_but_other_master_rejected(self):
        self.catalog["clips"][0].update(scale=0.95, anchorNormalized=[0.5, 0.9])
        self.assertEqual(validate_catalog(self.catalog)["errors"], [])
        self.catalog["clips"][0]["masterId"] = "different-camera"
        self.assertIn("master-mismatch", self.codes(validate_catalog(self.catalog)))

    def test_missing_and_unsafe_atlas_not_silently_passed(self):
        self.catalog["clips"][0]["atlas"] = "animation/no-such-atlas.png"
        self.assertIn("atlas-missing", self.codes(validate_catalog(self.catalog)))
        self.catalog["clips"][0]["atlas"] = "../outside.png"
        self.assertIn("atlas-path", self.codes(validate_catalog(self.catalog)))

    def test_blocked_entry_is_explicitly_undelivered(self):
        planned = {"id": "pending", "title": "Not generated", "category": "once",
                   "status": "generation-blocked", "triggerKinds": []}
        self.catalog["clips"].append(planned)
        report = validate_catalog(self.catalog)
        self.assertEqual(report["errors"], [])
        self.assertFalse(report["clips"][-1]["available"])
        self.assertIn("not-produced", {item["code"] for item in report["warnings"]})

    def test_bad_types_and_duplicate_ids_report_errors(self):
        duplicate = copy.deepcopy(self.catalog["clips"][0])
        duplicate["status"] = []
        duplicate["columns"] = True
        self.catalog["clips"].append(duplicate)
        codes = self.codes(validate_catalog(self.catalog))
        self.assertTrue({"duplicate-id", "clip-metadata", "grid-metadata"}.issubset(codes))

    def test_planned_ids_are_not_counted_as_delivered(self):
        self.catalog["plannedClips"] = ["future-blink"]
        report = validate_catalog(self.catalog)
        self.assertEqual(report["errors"], [])
        self.assertEqual(report["plannedClipCount"], 1)
        self.assertEqual(len(report["clips"]), 1)
        self.assertTrue(any(item["code"] == "not-produced" and item.get("clipId") == "future-blink"
                            for item in report["warnings"]))


if __name__ == "__main__":
    unittest.main()
