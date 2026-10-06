"""Regressions for measurement semantics, not art approval or image editing."""
import json
from pathlib import Path
import tempfile
import unittest

import numpy as np

from audit_body_scale import (checked_json, digest, measure_face, source_to_stage_factor,
                             unique_source_clips, variation, verify_source_digest)


def face():
    image=np.zeros((110,110,4),dtype=np.uint8)
    image[12:66,25:71]=[245,130,135,255]
    boxes=[[35,30,43,42],[52,30,60,42]]
    for left,top,right,bottom in boxes:image[top:bottom,left:right]=[250,250,250,255]
    return image,boxes


class BodyScaleAuditTests(unittest.TestCase):
    def test_transparent_padding_preserves_anatomical_measurement_and_mapping(self):
        original,boxes=face()
        first=measure_face(original,boxes,85)
        padded=np.zeros((180,230,4),dtype=np.uint8)
        padded[20:130,50:160]=original
        moved=[[x0+50,y0+20,x1+50,y1+20] for x0,y0,x1,y1 in boxes]
        second=measure_face(padded,moved,105)
        for key in ("faceWidth","eyeSeparation","eyeToFoot"):
            self.assertAlmostEqual(first[key],second[key])
        # Same source-pixel stage mapping, with a larger contour canvas.
        a=source_to_stage_factor(200,1.3)
        b=source_to_stage_factor(300,1.95)
        self.assertAlmostEqual(a,b)
        self.assertAlmostEqual(first["faceWidth"]*a,second["faceWidth"]*b)

    def test_larger_hat_and_detached_prop_do_not_become_head_width(self):
        original,boxes=face()
        baseline=measure_face(original,boxes,85)
        changed=original.copy()
        changed[0:11,10:100]=[250,250,250,255]  # oversized white hat
        changed[32:60,78:107]=[245,130,135,255]  # separate pink prop at eye height
        after=measure_face(changed,boxes,85)
        for key in ("faceWidth","eyeSeparation","eyeToFoot"):
            self.assertEqual(baseline[key],after[key])

    def test_twenty_percent_shrunk_frame_is_flagged_without_normalization(self):
        measured=[100.0,99.0,80.0,101.0]
        before=measured.copy()
        all_frames=variation(measured,100)
        self.assertTrue(all_frames["flagged"])
        self.assertEqual(all_frames["minimumReferenceRatio"],.8)
        self.assertEqual(measured,before)
        # Skipping a bad drawing only changes the used subset, not source-all.
        self.assertFalse(variation([measured[i] for i in (0,1,3)],100)["flagged"])
        self.assertTrue(all_frames["flagged"])

    def test_smaller_source_anatomy_is_observed_at_fixed_render_scale(self):
        original,boxes=face()
        baseline=measure_face(original,boxes,85)
        small=np.zeros_like(original)
        small[10:53,20:57]=[245,130,135,255]
        small_boxes=[[round(x*.8) for x in box] for box in boxes]
        for left,top,right,bottom in small_boxes:small[top:bottom,left:right]=[250,250,250,255]
        measured=measure_face(small,small_boxes,68)
        self.assertLess(measured["faceWidth"]/baseline["faceWidth"],.85)
        self.assertTrue(variation([baseline["faceWidth"],measured["faceWidth"]],baseline["faceWidth"])["flagged"])
        factor=source_to_stage_factor(200,1)
        self.assertLess(measured["faceWidth"]*factor,baseline["faceWidth"]*factor*.85)

    def test_three_blink_timings_are_one_source(self):
        catalogs={"main":{"clips":[{"id":x,"atlas":"blink.png"} for x in ("normal","slow","double")]},
                  "candidates":{"clips":[{"id":"review","atlas":"blink.png"}]}}
        self.assertEqual(len(unique_source_clips(catalogs)),1)

    def test_source_and_landmark_digest_drift_are_rejected(self):
        payload=b"original source bytes";expected=digest(payload)
        verify_source_digest(payload,expected,expected)
        for current,landmark,catalog in ((b"changed",expected,expected),
                                         (payload,"0"*64,expected),(payload,expected,"0"*64)):
            with self.assertRaisesRegex(ValueError,"SHA drift"):
                verify_source_digest(current,landmark,catalog)
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/"landmarks.json";path.write_text(json.dumps({"frame":0}))
            pin=digest(path.read_bytes());checked_json(path,pin)
            path.write_text(json.dumps({"frame":1}))
            with self.assertRaisesRegex(ValueError,"SHA drift"):checked_json(path,pin)

    def test_occluded_face_is_not_filled_from_total_bounds(self):
        image,boxes=face()
        image[:,45:]=[0,0,0,0]
        measured=measure_face(image,boxes,85)
        self.assertIn("unavailable",measured)

    def test_unverified_anatomical_feet_are_not_replaced_by_cushion_bottom(self):
        image,boxes=face()
        measured=measure_face(image,boxes,None)
        self.assertIsNone(measured["eyeToFoot"])
        self.assertGreater(measured["faceWidth"],0)


if __name__=="__main__":unittest.main()
