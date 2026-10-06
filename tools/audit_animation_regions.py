#!/usr/bin/env python3
"""Read-only source/contour audit; optional JSON report, never changes PNGs."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

from build_frame_regions import validate_regions
from validate_animation_catalog import validate_catalog

ROOT = Path(__file__).resolve().parents[1]


def sha(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def frame_metrics(frame: dict, alpha: np.ndarray) -> dict:
    xs, ys = [], []
    for row in frame["rows"]:
        y = row[0]
        for left, right in zip(row[1::2], row[2::2]):
            x = np.flatnonzero(alpha[y, left:right] >= 128) + left
            xs.extend(x.tolist())
            ys.extend([y] * len(x))
    x, y = np.asarray(xs), np.asarray(ys)
    tx, ty = frame["translation"]
    left, top, right, bottom = frame["diagnostics"]["coreBounds"]
    # Independent upper-head silhouette measurement, not the foot-band anchor.
    # Pose/hat changes can legitimately affect it; this is not art approval.
    head = (y >= top) & (y < top + max(1, int((bottom - top) * .2)))
    return {
        "strongPixelArea": int(x.size),
        "strongBounds": [int(x.min()), int(y.min()), int(x.max()+1), int(y.max()+1)],
        "coreBounds": [left, top, right, bottom],
        "sourceEdgeStrongPixels": int(((x == 0) | (x == alpha.shape[1]-1)
                                       | (y == 0) | (y == alpha.shape[0]-1)).sum()),
        "headSilhouetteCenterAfterTranslation": round(float(x[head].mean()+tx), 4),
        "allStrongCentroidAfterTranslation": [round(float(x.mean()+tx), 4),
                                               round(float(y.mean()+ty), 4)],
        "anchorSource": frame["anchorSource"],
        "translation": frame["translation"],
    }


def audit() -> dict:
    report = {"schemaVersion": 1, "date": "2026-10-06", "artApproved": False,
              "sourcePixelsEdited": False, "catalogs": [], "atlases": []}
    union = {}
    for name in ("animation/catalog.json", "animation/candidates.json"):
        payload = (ROOT/name).read_bytes()
        data = json.loads(payload)
        checked = validate_catalog(data, ROOT)
        if checked["errors"]:
            raise ValueError(f"{name}: {checked['errors']}")
        report["catalogs"].append({
            "path": name, "sha256": sha(payload), "clipCount": len(data["clips"]),
            "uniqueSourceCount": len({clip["atlas"] for clip in data["clips"]}),
            "playbackFrameOccurrences": sum(clip["frameCount"] for clip in data["clips"]),
            "errors": checked["errors"], "warnings": checked["warnings"],
        })
        for clip in data["clips"]:
            union.setdefault(clip["atlas"], clip)
    for source, clip in union.items():
        payload = (ROOT/source).read_bytes()
        metadata_bytes = (ROOT/clip["frameRegions"]["path"]).read_bytes()
        data = json.loads(metadata_bytes)
        with Image.open(ROOT/source) as image:
            alpha = np.asarray(image.getchannel("A"))
        if sha(payload) != data["source"]["sha256"]:
            raise ValueError(f"Source SHA drift: {source}")
        coverage = validate_regions(data, alpha)
        metrics = [frame_metrics(frame, alpha) for frame in data["frames"]]
        heights = [m["coreBounds"][3]-m["coreBounds"][1] for m in metrics]
        areas = [m["strongPixelArea"] for m in metrics]
        report["atlases"].append({
            "source": source, "sha256": sha(payload),
            "regions": clip["frameRegions"]["path"], "regionsSha256": sha(metadata_bytes),
            "sourceHashMatches": True, "frameCount": len(metrics), "canvas": data["canvas"],
            "coverage": coverage, "coreHeightRange": [min(heights), max(heights)],
            "strongPixelAreaRange": [min(areas), max(areas)],
            "areaMaxMinRatio": round(max(areas)/min(areas), 6),
            "sourceEdgeFramesOneBased": [i+1 for i, m in enumerate(metrics)
                                         if m["sourceEdgeStrongPixels"]],
            "frames": metrics,
        })
    previous = ROOT/"animation/production-20261006/exercise-regions-before-anchor-fix.json"
    exercise = next(a for a in report["atlases"] if "/exercise-v2/" in a["source"])
    before_bytes = previous.read_bytes()
    before = json.loads(before_bytes)
    after = json.loads((ROOT/exercise["regions"]).read_bytes())
    with Image.open(ROOT/exercise["source"]) as image:
        alpha = np.asarray(image.getchannel("A"))
    validate_regions(before, alpha)
    assert before["canvas"] == after["canvas"]
    for b, a in zip(before["frames"], after["frames"]):
        assert b["sourceBounds"] == a["sourceBounds"] and b["rows"] == a["rows"]
        assert b["anchorSource"][1] == a["anchorSource"][1]
    before_metrics = [frame_metrics(frame, alpha) for frame in before["frames"]]
    after_metrics = exercise["frames"]
    def head_range(frames):
        xs = [frame["headSilhouetteCenterAfterTranslation"] for frame in frames]
        return round(max(xs)-min(xs), 4)
    report["exerciseAnchorCorrection"] = {
        "beforeRegions": previous.relative_to(ROOT).as_posix(), "beforeSha256": sha(before_bytes),
        "afterRegions": exercise["regions"], "afterSha256": exercise["regionsSha256"],
        "canvasUnchanged": True, "sourceBoundsUnchanged": True, "sourceRowMasksUnchanged": True,
        "verticalAnchorsUnchanged": True, "perFrameResize": False,
        "policy": after["diagnostics"]["supportAnchorPolicy"],
        "independentUpperHeadCenterRangeSourcePixels": {
            "before": head_range(before_metrics), "after": head_range(after_metrics)},
        "frames": [{"frameOneBased": i+1, "before": b, "after": a}
                   for i, (b, a) in enumerate(zip(before_metrics, after_metrics))],
        "remainingArtIssues": ["Frame 5 wrist/forearm silhouette changes abruptly.",
                               "Head/body shapes still vary; no original drawing was corrected.",
                               "First and last artwork are not identical; seamless loop is unapproved."],
    }
    report["totals"] = {"uniqueAtlases": len(union),
                        "originalFrames": sum(a["frameCount"] for a in report["atlases"]),
                        "nonzeroAlphaPixelsPreservedExactlyOnce": sum(a["coverage"]["assignedPixels"] for a in report["atlases"]),
                        "missingPixels": 0, "overlapPixels": 0}
    feedback_name = "feedback/2026-09-27-wardrobe-review.json"
    feedback_bytes = (ROOT/feedback_name).read_bytes()
    feedback = json.loads(feedback_bytes)
    reviews = []
    for concept, review in feedback["reviews"].items():
        current_sha = sha((ROOT/review["image"]).read_bytes())
        parts = review["fingerprint"].split("|")
        reviews.append({"concept": concept, "verdict": review["verdict"],
                        "note": review["note"], "image": review["image"],
                        "sha256": current_sha,
                        "fingerprintStillMatches": parts[:2] == [review["image"], current_sha]})
    report["persistedUserFeedback"] = {
        "path": feedback_name, "sha256": sha(feedback_bytes),
        "approvalGranted": feedback["approvalGranted"], "reviews": reviews,
        "interpretation": "Only these explicit exported verdicts are counted. Unmarked concepts are not accepted; browser-only state was not read by this filesystem audit.",
    }
    ledger_name = "animation/production-20261006/generation-ledger.json"
    ledger_bytes = (ROOT/ledger_name).read_bytes()
    ledger = json.loads(ledger_bytes)
    report["generationSnapshot"] = {
        "path": ledger_name, "sha256": sha(ledger_bytes),
        "allArtworkComplete": ledger["allArtworkComplete"],
        "requests": [{key: job.get(key) for key in ("id", "status", "outputExists", "error")}
                     for job in ledger["requests"]],
    }
    playback_name = "output/playwright/20261006-exercise-anchor/report.json"
    playback_path = ROOT/playback_name
    if playback_path.exists():
        playback_bytes = playback_path.read_bytes()
        playback = json.loads(playback_bytes)
        case = next(item for item in playback["cases"] if item["id"] == "exercise")
        report["exerciseNormalSpeedReview"] = {
            "status": "playback-technical-pass-position-improved-art-revision-pending",
            "report": playback_name, "reportSha256": sha(playback_bytes),
            "clock": playback["clock"], "speed": playback["speed"],
            "passed": playback["passed"], "observedFrames": len(case["liveFrames"]),
            "durationMs": case["durationMs"], "stoppedAtLastFrame": case["stoppedAtLastFrame"],
            "autoReplayObserved": case["autoReplayObserved"], "artApproved": False,
            "sequence": "output/playwright/20261006-exercise-anchor/exercise-sequence.png",
            "video": "output/playwright/20261006-exercise-anchor/exercise-fixed-anchor-live-1x.webm",
            "visualObservations": [
                "Frames 1 to 2 no longer show the old approximately 44-stage-pixel whole-body jump; frames 10 to 11 also keep the feet registered.",
                "Frame 5 raised forearm remains disproportionately thin/long.",
                "Frames 10 to 12 wrist/grip morph as the dumbbell lowers.",
                "Frames 13 to 14 change abruptly from exhaling to the forward expression.",
            ],
        }
    report["limitations"] = [
        "Strong-alpha area includes props and changes with acting; variation is not an automatic defect verdict.",
        "Correct contour conservation does not establish correct ownership of every artistic detail or usable animation.",
        "Foot/upper-head measurements are source-pixel diagnostics, not a claim that original artwork is motion-consistent.",
        "Normal-speed playback is separately reviewed; no browser playback is performed by this tool.",
    ]
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="optional JSON report under animation/production-20261006")
    args = parser.parse_args()
    report = audit()
    if args.output:
        destination = args.output.resolve()
        allowed = (ROOT/"animation/production-20261006").resolve()
        if not destination.is_relative_to(allowed) or destination.suffix != ".json":
            raise ValueError("report output must be JSON inside this audit's production directory")
        destination.write_text(json.dumps(report, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
        print(json.dumps({"report": str(destination), **report["totals"]}, ensure_ascii=False))
    else:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
