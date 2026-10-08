"""Source-pinned chef-cookie revision review; never edit image pixels.

The existing reviewed chef detector is reused as code only. New eye selection,
feet and every metric are measured again from this PNG; old results are not copied.
"""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import sys

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "animation/production-20261007-completion/feeding-chef-v6-qc.json"
SOURCE_SHA = "cd432cf83e782c99eed61f496cc8ab1cdd50559f95401f1b1c576ec1037cdc80"
spec = importlib.util.spec_from_file_location("reviewed_chef_measurement", ROOT / "animation/feeding-chef-v2/measure_review.py")
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)


def mask(frame, shape):
    value = np.zeros(shape, dtype=bool)
    for row in frame["rows"]:
        for start, end in zip(row[1::2], row[2::2]):
            value[row[0], start:end] = True
    return value


def make_report():
    old = base.analyze("feeding-chef-v2", "cf5115d199e0d0cbc8bac8983cec04fed215dcb4bafc0734e8e6bad9dbbfa8a0",
                       [[130,118,161,169],[161,118,196,170]], {6,8})
    # First-frame actual white components independently checked in this new source.
    new = base.analyze("feeding-chef-v6", SOURCE_SHA,
                       [[130,118,162,169],[161,118,196,170]], {6,8})
    new_path = ROOT / new["source"]["path"]
    old_rgba = np.array(Image.open(ROOT / old["source"]["path"]).convert("RGBA"))
    new_rgba = np.array(Image.open(new_path).convert("RGBA"))
    old_meta = json.loads((ROOT / old["regions"]["path"]).read_bytes())
    new_meta = json.loads((ROOT / new["regions"]["path"]).read_bytes())
    if old_rgba.shape != new_rgba.shape:
        raise ValueError("same-coordinate edit comparison requires identical source dimensions")
    changed = np.any(old_rgba != new_rgba, axis=2)
    diff = []
    for index, (before, after) in enumerate(zip(old_meta["frames"], new_meta["frames"])):
        region = mask(before, new_rgba.shape[:2]) | mask(after, new_rgba.shape[:2])
        strong = region & ((old_rgba[:,:,3] >= 128) | (new_rgba[:,:,3] >= 128))
        diff.append({"sourceFrame": index+1, "strongUnionPixels": int(strong.sum()),
                     "changedStrongRgbaPixels": int((changed & strong).sum()),
                     "changedStrongRgbaFraction": float((changed & strong).sum() / strong.sum()),
                     "meaning": "Raw RGBA changes in source coordinates, not a perceptual error score or anatomical test."})
    for row in new["frames"]:
        row["eyeLineToFootPx"] = row["eyeLineToActualFootPx"]
        eyes = row.get("eyeLowerRimPoints")
        if row["eyeLineToFootPx"] is not None and eyes:
            midpoint = [sum(point[axis] for point in eyes)/2 for axis in (0,1)]
            foot = [midpoint[0], row["visibleFootBaselineY"]]
            row.update(footSourcePoint=foot, eyeToFootPoints=[midpoint,foot])
    metrics = ["faceWidthPx", "eyeLowerRimSeparationPx", "eyeLineToActualFootPx",
               "hatWhiteFillHeightPx", "coreHeightPx"]
    edge = np.zeros(new_rgba.shape[:2], dtype=bool)
    edge[[0,-1],:] = True; edge[:,[0,-1]] = True
    alpha = new_rgba[:,:,3]
    edge_alpha = alpha[edge & (alpha>0)]
    return {"schemaVersion":1,"reviewedAt":"2026-10-07","frameIndexBasis":"one-based source reading order",
            "status":"cookie-continuity-improved-other-transitions-pending-review","artApproved":False,
            "source":new["source"],"sourceUnchanged":True,"regions":new["regions"],"canvas":new["canvas"],
            "coverage":new["coverage"],"reference":new["reference"],"frames":new["frames"],"summary":new["summary"],
            "oldSource":old["source"],"oldNewFirstFrame":{key:base.delta(old["frames"][0][key],new["frames"][0][key]) for key in metrics},
            "newFirstLastFrame":{key:base.delta(new["frames"][0][key],new["frames"][-1][key]) for key in metrics},
            "sourceCoordinateChanges":diff,
            "sourceEdgeAlpha":{"nonzeroPixels":int(edge_alpha.size),"maximumAlpha":int(edge_alpha.max()) if edge_alpha.size else 0,
                               "strongPixels":int(((alpha>=128)&edge).sum()),
                               "sourceFrames":[i+1 for i,f in enumerate(new_meta["frames"]) if f["diagnostics"]["sourceEdgeTouches"]]},
            "methods":["Reference first-frame eye boxes were checked on the new PNG, then tracked independently; closed frames6/8 remain null.",
                       "Visible feet are independently measured pink fill components; cushion/region anchor is not anatomical height.",
                       "All nonzero-alpha pixels remain assigned exactly once. Common square canvas, pixel1:1 translation only, no per-frame scaling.",
                       "Other11 frames are compared and any changed pixels reported; a targeted image edit is not claimed byte-identical outside frame12.",
                       "About2px fill-boundary uncertainty. Geometry and semantic proxies are not art approval."],
            "visualFindings":[{"sourceFrames":[12],"kind":"improved","message":"Cookie on final plate visibly retains a bitten notch; no whole-cookie reset as in chef-v2."},
                              {"sourceFrames":[5,6],"kind":"remaining","message":"Existing mouth release and hand lowering jump remains; requires real1x review."},
                              {"sourceFrames":[10,11,12],"kind":"preserved","message":"Hand lowers toward plate in stages; inspect notch orientation and apparent cookie volume through placement."},
                              {"sourceFrames":list(range(1,13)),"kind":"pending","message":"White eyes, pink closed lids, mint apron and shorter white hat retained visually. Minor shape/line drift remains unapproved."}],
            "normalSpeedReview":"pending-new-source-browser-review"}


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("--check",action="store_true");args=parser.parse_args()
    report=make_report()
    if args.check:
        if json.loads(OUTPUT.read_bytes()) != report: raise ValueError("review snapshot differs")
    else:
        OUTPUT.parent.mkdir(parents=True,exist_ok=True)
        OUTPUT.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({"report":OUTPUT.relative_to(ROOT).as_posix(),"summary":report["summary"],
                      "newFirstLastFrame":report["newFirstLastFrame"],"edge":report["sourceEdgeAlpha"],
                      "changedStrongPixelsFirst11":sum(row["changedStrongRgbaPixels"] for row in report["sourceCoordinateChanges"][:11])},ensure_ascii=False))


if __name__ == "__main__":main()
