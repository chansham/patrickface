#!/usr/bin/env python3
"""Describe the three original clock-art layers; never edits or exports PNG pixels."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
import numpy as np
from PIL import Image
from build_frame_regions import ALGORITHM, build_regions, validate_regions

ROOT = Path(__file__).resolve().parents[1]
SOURCE = "experience/clock/layers-v1.png"


def build(check: bool) -> dict:
    path = ROOT / SOURCE
    destination = path.with_name("regions-v1.json")
    for candidate in (path, destination):
        if candidate.resolve() != candidate.absolute() or not candidate.is_relative_to(ROOT / "experience/clock"):
            raise ValueError("Clock art and sidecar must stay in the non-redirected clock directory.")
    before = path.read_bytes()
    with Image.open(path) as image:
        if image.format != "PNG" or "A" not in image.getbands():
            raise ValueError("Clock source must be PNG with explicit alpha.")
        alpha = np.asarray(image.getchannel("A"))
        source = {"path": SOURCE, "sha256": hashlib.sha256(before).hexdigest(),
                  "width": image.width, "height": image.height}
    if check:
        data = json.loads(destination.read_text(encoding="utf-8-sig"))
        if data.get("source") != source or data.get("algorithm") != ALGORITHM:
            raise ValueError("Clock sidecar source or algorithm does not match.")
    else:
        if destination.exists():
            previous = json.loads(destination.read_text(encoding="utf-8-sig"))
            if previous.get("algorithm") != ALGORITHM or previous.get("source", {}).get("path") != SOURCE:
                raise ValueError("Refusing to overwrite an unknown sidecar.")
        data = build_regions(alpha, columns=3, rows=1)
        data["source"] = source
    if len(data["frames"]) != 3:
        raise ValueError("Expected body, short arm and long arm as three distinct strong components.")
    result = validate_regions(data, alpha)
    if path.read_bytes() != before:
        raise ValueError("Source changed during analysis; nothing written.")
    if not check:
        destination.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    return {**result, "source": source, "sourceUnchanged": True,
            "metadata": destination.relative_to(ROOT).as_posix(), "canvas": data["canvas"],
            "layers": [{"regionIndex": index, "coreBounds": frame["diagnostics"]["coreBounds"],
                        "sourceBounds": frame["sourceBounds"], "translation": frame["translation"]}
                       for index, frame in enumerate(data["frames"])],
            "note": "These are extraction placements, not rotation pivots; root/length/layout belong to the clock manifest."}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Read-only alpha coverage and source-hash check")
    args = parser.parse_args()
    try:
        print(json.dumps(build(args.check), ensure_ascii=False))
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.exit(1, f"error: {error}\n")
