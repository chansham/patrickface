"""Contour integrity regressions; original PNGs are only read."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from PIL import Image
from frame_region_contract import read_regions

ROOT = Path(__file__).resolve().parents[1]


class RegionContractTests(unittest.TestCase):
    def setUp(self):
        self.clip = json.loads((ROOT / "animation/catalog.json").read_text(encoding="utf-8"))["clips"][0]
        self.meta = json.loads((ROOT / self.clip["frameRegions"]["path"]).read_text(encoding="utf-8"))
        with Image.open(ROOT / self.clip["atlas"]) as image:
            self.alpha = image.getchannel("A").copy()

    def check(self, meta):
        # Only this known temporary directory is cleaned by TemporaryDirectory.
        with tempfile.TemporaryDirectory(prefix="patrick-contour-contract-") as directory:
            root = Path(directory).resolve()
            self.assertEqual(root.parent, Path(tempfile.gettempdir()).resolve())
            payload = json.dumps(meta).encode("utf-8")
            (root / "regions.json").write_bytes(payload)
            clip = copy.deepcopy(self.clip)
            clip["frameRegions"] = {"path": "regions.json", "version": 1,
                                    "sha256": hashlib.sha256(payload).hexdigest()}
            return read_regions(clip, root, self.alpha)

    def test_real_source_pixels_preserved_once(self):
        result = self.check(self.meta)
        self.assertEqual(result["sourcePixelsDuplicated"], 0)
        self.assertEqual(result["sourcePixelsPreserved"], sum(value != 0 for value in self.alpha.tobytes()))
        self.assertEqual(len(result["frames"]), 8)
        self.assertEqual(len({tuple(frame["footAnchor"]) for frame in result["frames"]}), 1)

    def test_duplicated_neighbor_character_is_rejected(self):
        data = copy.deepcopy(self.meta)
        data["frames"][1] = copy.deepcopy(data["frames"][0])
        with self.assertRaisesRegex(ValueError, "more than one pose"):
            self.check(data)

    def test_missing_source_row_is_rejected(self):
        data = copy.deepcopy(self.meta)
        del data["frames"][0]["rows"][len(data["frames"][0]["rows"]) // 2]
        with self.assertRaisesRegex(ValueError, "preserve every"):
            self.check(data)

    def test_anchor_and_placement_mismatch_is_rejected(self):
        data = copy.deepcopy(self.meta)
        data["frames"][0]["translation"][1] += 1
        with self.assertRaisesRegex(ValueError, "register"):
            self.check(data)

    def test_source_revision_is_checked(self):
        data = copy.deepcopy(self.meta)
        data["source"]["sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "source sha256"):
            self.check(data)

    def test_per_frame_resizing_cannot_hide_art_changes(self):
        data = copy.deepcopy(self.meta)
        data["frames"][0]["scale"] = 1.2
        with self.assertRaisesRegex(ValueError, "resize"):
            self.check(data)


if __name__ == "__main__":
    unittest.main()
