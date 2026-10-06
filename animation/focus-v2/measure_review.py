"""Read source pixels; save only a source-pinned QC record, never an image."""
from pathlib import Path
import hashlib
import json
import sys

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from build_frame_regions import validate_regions
from audit_body_scale import measure_face, rim_point, track_eyes

SOURCE = "animation/focus-v2/atlas-generated.png"
EXPECTED_SHA = "7ee112183d2c9e5d911bf89cedc8b4afba705f6a72659838410daa934939322f"
OLD_SOURCE = "animation/focus-v1/atlas-generated.png"
OLD_SHA = "d1405d87f66a16baa98689b1b2a5b704f2b68b8b7c9c64595af74db9aa90d755"
DESTINATION = ROOT / "animation/production-20261006-repair/focus-v2-qc.json"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def delta(first, last):
    return {"first": first, "last": last,
            "changePercent": (last / first - 1) * 100}


def main():
    payload = (ROOT / SOURCE).read_bytes()
    if sha(payload) != EXPECTED_SHA or sha((ROOT / OLD_SOURCE).read_bytes()) != OLD_SHA:
        raise ValueError("reviewed source SHA changed; select fresh landmarks")
    regions_path = (ROOT / SOURCE).with_name("regions-v1.json")
    regions_payload = regions_path.read_bytes()
    data = json.loads(regions_payload)
    if data["source"]["sha256"] != EXPECTED_SHA:
        raise ValueError("metadata is for a different source")
    rgba = np.array(Image.open(ROOT / SOURCE).convert("RGBA"))
    alpha = rgba[:, :, 3]
    coverage = validate_regions(data, alpha)
    old = json.loads((ROOT / OLD_SOURCE).with_name("regions-v1.json").read_bytes())
    reference = {"referenceEyeWhiteBounds": [[179, 105, 210, 136], [214, 105, 245, 137]]}
    frames = []
    for index, frame in enumerate(data["frames"]):
        left, top, right, bottom = frame["diagnostics"]["coreBounds"]
        owned = np.zeros(alpha.shape, dtype=bool)
        for row in frame["rows"]:
            for x0, x1 in zip(row[1::2], row[2::2]):
                owned[row[0], x0:x1] = True
        strong = owned & (alpha >= 128)
        row = {"sourceFrame": index + 1, "sourceBounds": frame["sourceBounds"],
               "coreBounds": [left, top, right, bottom],
               "coreWidthPx": right-left, "coreHeightPx": bottom-top,
               "strongPixelArea": int(strong.sum()), "nonzeroAlphaPixels": int(owned.sum()),
               "anchorSource": frame["anchorSource"], "translation": frame["translation"],
               "sourceEdgeStrongPixels": int(strong[0].sum()+strong[-1].sum()+strong[1:-1,0].sum()+strong[1:-1,-1].sum()),
               "faceWidthPx": None, "eyeLowerRimSeparationPx": None, "eyeLineToFootPx": None}
        if index + 1 in (8, 9, 10, 11):
            row["unavailableReason"] = "hand overlaps face; do not infer hidden face from its bounding box"
        elif index + 1 == 15:
            row["unavailableReason"] = "closed eyes; no white-eye lower-rim proxy"
        else:
            eyes, reason = track_eyes(rgba, frame, reference, data["frames"][0])
            if eyes is None:
                row["unavailableReason"] = reason
            else:
                l, r = [rim_point(bounds) for bounds in eyes]
                row["eyeWhiteBounds"] = eyes
                row["eyeLowerRimPoints"] = [l.tolist(), r.tolist()]
                row["eyeLowerRimSeparationPx"] = float(np.linalg.norm(r-l))
                row["eyeLineToFootPx"] = float(bottom - (l[1]+r[1])/2)
                measured = measure_face(rgba, eyes, bottom)
                if "faceWidth" in measured:
                    row["faceWidthPx"] = measured["faceWidth"]
                    row["faceCaliperPoints"] = measured["faceCaliperPoints"]
                else:
                    row["faceWidthUnavailableReason"] = measured.get("unavailable", "unreliable face edge")
        frames.append(row)
    heights = [f["coreHeightPx"] for f in frames]
    old_heights = [f["diagnostics"]["coreBounds"][3]-f["diagnostics"]["coreBounds"][1] for f in old["frames"]]
    report = {"schemaVersion": 1, "reviewedAt": "2026-10-06", "status": "candidate-needs-revision",
              "artApproved": False, "bodyScaleResolved": False,
              "catalogIntegrated": False, "normalSpeedReview": "not-yet-performed-for-v2",
              "source": data["source"], "sourceUnchanged": True,
              "previousSource": {"path": OLD_SOURCE, "sha256": OLD_SHA},
              "regions": {"path": regions_path.relative_to(ROOT).as_posix(), "sha256": sha(regions_payload)},
              "canvas": data["canvas"], "coverage": coverage,
              "frameIndexBasis": "one-based source reading order",
              "methods": [
                  "Original source coordinates; no crop, repaint, resample or per-frame scale.",
                  "Core bounds are alpha>=128 silhouette bounds and include clothing/notebook; they are not bare torso measurements.",
                  "Eye-white reference boxes are selected on this new source, not copied from a different SHA. Other eye boxes are tracking proposals and expression-sensitive.",
                  "Visible bare feet establish the source core bottom for this seated set; no cushion or dumbbell occupies its lowest band.",
                  "Face width is the visible pink face cross-section at the two lower eye rims, not head width or pupil distance.",
                  "Hand-occluded frames 8-11 and closed-eye frame15 remain unmeasured. No whole-bounds fill-in.",
                  "First/last are comparable unobstructed forward stern poses. Their body proxy is more meaningful than comparing a blink to a wide-open eye pose."
              ],
              "reference": {"sourceFrame": 1, **reference, "sourceSha256": EXPECTED_SHA,
                            "visualReview": "original correctly alpha-composited on light and dark backgrounds; first/last white-eye positions and visible feet inspected"},
              "frames": frames,
              "summary": {"sourceFrames": 16, "measuredFaceFrames": sum(f["faceWidthPx"] is not None for f in frames),
                          "measuredEyeFootFrames": sum(f["eyeLineToFootPx"] is not None for f in frames),
                          "coreHeightFirstLast": delta(heights[0], heights[-1]),
                          "coreWidthFirstLast": delta(frames[0]["coreWidthPx"],frames[-1]["coreWidthPx"]),
                          "coreHeightFirstLastRowMeans": delta(float(np.mean(heights[:4])),float(np.mean(heights[-4:]))),
                          "oldCoreHeightFirstLast": delta(old_heights[0],old_heights[-1]),
                          "oldCoreHeightFirstLastRowMeans": delta(float(np.mean(old_heights[:4])),float(np.mean(old_heights[-4:]))),
                          "faceWidthFirstLast": delta(frames[0]["faceWidthPx"],frames[-1]["faceWidthPx"]),
                          "eyeSeparationFirstLast": delta(frames[0]["eyeLowerRimSeparationPx"],frames[-1]["eyeLowerRimSeparationPx"]),
                          "eyeLineToFootFirstLast": delta(frames[0]["eyeLineToFootPx"],frames[-1]["eyeLineToFootPx"]),
                          "sourceEdgeStrongPixels": sum(f["sourceEdgeStrongPixels"] for f in frames)},
              "visualFindings": [
                  {"sourceFrames": [11,12], "kind": "improved", "message": "New intermediate hand-lowering poses exist, compared with old frame11-to12 jump."},
                  {"sourceFrames": [13,14,15,16], "kind": "needs-revision", "message": "Torso/vertical body proportions still shorten; constant face width does not justify calling this solved or uniformly rescaling these frames."},
                  {"sourceFrames": [1,16], "kind": "needs-revision", "message": "Same stern forward pose but shorter eye-line-to-feet distance at end. First/last do not match geometrically."},
                  {"sourceFrames": [13,14,15,16], "kind": "pending-normal-speed-review", "message": "Final sleepy/blink/awake beats and shrinking posture must be reviewed at real speed; no seamless-loop approval."},
                  {"sourceFrames": list(range(1,17)), "kind": "preserve", "message": "Navy suit, notebook, round glasses, white sclera and pink eyelids retained. Raw transparent RGB fringes mostly disappear under correct alpha composition."}
              ]}
    if (ROOT / SOURCE).read_bytes() != payload:
        raise ValueError("source changed during QC")
    DESTINATION.write_text(json.dumps(report, ensure_ascii=False, indent=2)+"\n",encoding="utf-8")
    print(json.dumps({"report":DESTINATION.relative_to(ROOT).as_posix(),"summary":report["summary"],"coverage":coverage},ensure_ascii=False))


if __name__ == "__main__":
    main()
