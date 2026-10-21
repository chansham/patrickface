"""Read source/regions only; emit unaltered-alpha diagnostic composites and QC."""
from pathlib import Path
import hashlib
import json
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from build_frame_regions import validate_regions

HERE = Path(__file__).resolve().parent
OUT = ROOT / "output" / "martial-inbetweens-20261012"
OUT.mkdir(parents=True, exist_ok=True)
source = ROOT / "animation/fitness-martial-v2/atlas-generated.png"
regions = source.with_name("regions-v1.json")
original = source.read_bytes()
if hashlib.sha256(original).hexdigest() != "8ba068acc7c9548ef002f29593afffbdc08d4666610e40d46c5f8b11cdfa3bdf":
    raise ValueError("The visual review belongs to the exact original v2 PNG; review a changed source separately.")
image = Image.open(source).convert("RGBA")
pixels = np.asarray(image)
alpha = pixels[:, :, 3]
metadata = json.loads(regions.read_bytes())
coverage = validate_regions(metadata, alpha)
n = metadata["canvas"]["width"]

for color in ("black", "white"):
    background = Image.new("RGBA", image.size, color)
    background.alpha_composite(image)
    background.convert("RGB").save(OUT / f"source-{color}.png")

frame_arrays = []
for frame in metadata["frames"]:
    result = np.zeros((n, n, 4), dtype=np.uint8)
    tx, ty = frame["translation"]
    for row in frame["rows"]:
        y, *runs = row
        for start, end in zip(runs[::2], runs[1::2]):
            result[y + ty, start + tx:end + tx] = pixels[y, start:end]
    frame_arrays.append(result)

# Every frame shares N, integer translation and 1:1 source pixel scale.
# The source is never repainted or per-frame fitted for these diagnostics.
for color in ("black", "white"):
    sheet = Image.new("RGBA", (5*n, 2*(n+30)), color)
    draw = ImageDraw.Draw(sheet)
    for index, rgba in enumerate(frame_arrays):
        x, y = index % 5*n, index // 5*(n+30)
        sheet.alpha_composite(Image.fromarray(rgba), (x, y))
        baseline = y + metadata["canvas"]["anchorPixels"][1]
        draw.line((x, baseline, x+n-1, baseline), fill="#557766", width=1)
        draw.text((x+10, y+n+8), f"source {index+1}; fixed 1px scale", fill="white" if color == "black" else "black")
    sheet.convert("RGB").save(OUT / f"contours-{color}.png")

fragments = metadata["diagnostics"]["detachedComponents"]
strong_fragments = [f for f in fragments if f["maxAlpha"] >= 128]
edge = np.zeros(alpha.shape, dtype=bool)
edge[0] = edge[-1] = True
edge[:, 0] = edge[:, -1] = True

old_meta = json.loads((ROOT / "animation/fitness-martial-v1/regions-v1.json").read_bytes())
def heights(meta):
    return [f["diagnostics"]["coreBounds"][3] - f["diagnostics"]["coreBounds"][1] for f in meta["frames"]]
old_heights = heights(old_meta)
new_heights = heights(metadata)
report = {
    "schemaVersion": 1,
    "candidateID": "martial-inbetweens-20261012",
    "artApproval": False,
    "source": metadata["source"],
    "regions": {"path": regions.relative_to(ROOT).as_posix(), "sha256": hashlib.sha256(regions.read_bytes()).hexdigest()},
    "sourceUnchanged": source.read_bytes() == original,
    "sourceFrames": 10,
    "canvas": metadata["canvas"],
    "coverage": coverage,
    "sourceAlpha": {
        "transparentPixels": int((alpha == 0).sum()),
        "alphaOnePixels": int((alpha == 1).sum()),
        "edgeNonzeroPixels": int(((alpha > 0) & edge).sum()),
        "edgeStrongPixels": int(((alpha >= 128) & edge).sum()),
        "maximumEdgeAlpha": int(alpha[edge].max()),
        "detachedComponents": len(fragments),
        "detachedFragmentsWithStrongAlpha": len(strong_fragments),
        "strongDetachedFragments": strong_fragments,
        "detachedMaximumAlpha": max((f["maxAlpha"] for f in fragments), default=0),
        "detachedPixels": sum(f["pixelCount"] for f in fragments),
        "detachedPixelsOnlyAlpha1": sum(f["pixelCount"] for f in fragments if f["maxAlpha"] == 1),
    },
    "frames": [{"sourceFrame": i+1, "sourceBounds": f["sourceBounds"], "coreBounds": f["diagnostics"]["coreBounds"], "anchorSource": f["anchorSource"], "translation": f["translation"], "placement": f["placement"], "alignmentIsAnatomy": False} for i, f in enumerate(metadata["frames"])],
    "transitionDiagnostics": {
        "meaning": "Strong-alpha full-body silhouette heights, in source pixels. Bow foreshortening is intentional; this is not an anatomical scale approval.",
        "oldHeights": old_heights,
        "newHeights": new_heights,
        "oldAdjacentDelta": [b-a for a,b in zip(old_heights, old_heights[1:])],
        "newAdjacentDelta": [b-a for a,b in zip(new_heights, new_heights[1:])],
    },
    "sourceReview": {
        "sourceViewed": True,
        "blackWhiteViewed": True,
        "alignmentReviewed": True,
        "reviewedAt": "2026-10-12",
        "reviewMethod": "Actual view_image review of the exact source SHA plus opaque black/white source and common-canvas composites. No browser playback in this source review.",
        "findings": [
            {"sourceFrames": list(range(1, 11)), "issueType": "alpha", "message": "Transparent-tool presentation exaggerated red/white fringes. Every detached fragment has alpha=1/255; no strong-alpha detached fragment exists. Actual black/white composites show no conspicuous detached debris. Faint pixels remain preserved, not erased."},
            {"sourceFrames": list(range(1, 11)), "issueType": "outfit", "message": "White gi, black belt, red star and two complete bare feet remain visible. The common-canvas baseline aligns the support feet by integer translation; no frame is resized."},
            {"sourceFrames": [5], "issueType": "eyes", "message": "Deepest bow closes eyes on warm coral-pink skin. Open sclera in the other inspected frames are white; no purple eyelid defect was seen."},
            {"sourceFrames": [5, 6, 7], "issueType": "motion", "message": "New frame 6 visibly begins rising from the deepest bow. The old large 75-source-pixel silhouette-height jump is split into new rises of 38 and 33 source pixels. These silhouette values describe posture, not anatomical size acceptance."},
            {"sourceFrames": [7, 8, 9], "issueType": "motion", "severity": "medium", "status": "pending-art-review", "message": "Frames 7 and 8 remain very close in head/shoulder pose (silhouette heights 310 and 309 px), followed by a 28 px rise to frame 9. The requested second inbetween is not convincingly distinct; normal-speed review must retain this pause/jump concern."},
            {"sourceFrames": [1, 10], "issueType": "scale", "status": "anatomical-measurement-pending", "message": "Neutral silhouettes have heights 343 and 337 source px; this is not a face/torso measurement. Independent body-landmark review is required before a cross-version scale or body-volume conclusion."},
        ],
        "alignmentMethod": "Default lower-15-percent support center, visually checked against the two bare feet in all ten frames; integer translation only. Bowing head/shoulder descent is retained.",
        "evidencePaths": [f"output/martial-inbetweens-20261012/{name}.png" for name in ("source-black", "source-white", "contours-black", "contours-white")],
    },
    "status": "source-qc-complete-art-pending",
}
(HERE / "martial-v2-source-qc.json").write_text(json.dumps(report, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
print(json.dumps({"regions": report["regions"], "canvas": metadata["canvas"], "coverage": coverage, "alpha": report["sourceAlpha"], "transitionDiagnostics": report["transitionDiagnostics"]}, ensure_ascii=False))
