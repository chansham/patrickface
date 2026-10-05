#!/usr/bin/env python3
"""Read-only verification of the six local, muted-by-default audio cues."""
from __future__ import annotations

from array import array
import hashlib
import json
import math
from pathlib import Path
import sys
import wave

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_IDS = {"bubble", "pet", "feed", "complete", "wake", "softclick"}


def validate(project_root: Path = ROOT) -> dict:
    project_root = project_root.resolve()
    pack = project_root / "experience" / "audio"
    manifest = json.loads((pack / "manifest.json").read_text(encoding="utf-8-sig"))
    errors = []
    results = []
    if manifest.get("schemaVersion") != 1 or manifest.get("defaultEnabled") is not False:
        errors.append("Schema or default mute policy is incorrect.")
    cues = manifest.get("cues", [])
    if len(cues) != 6 or {cue.get("id") for cue in cues} != EXPECTED_IDS:
        errors.append("Exactly six named cues are required.")
    settings_path = project_root / "experience" / "contract.json"
    if settings_path.exists():
        contract = json.loads(settings_path.read_text(encoding="utf-8-sig"))
        if contract.get("settings", {}).get("soundEnabled") is not False:
            errors.append("The shared contract must default to soundEnabled=false.")
    for cue in cues:
        cue_id = cue.get("id", "unknown")
        path = project_root / cue.get("path", "")
        expected = pack / f"{cue_id}.wav"
        if path != expected or path.resolve() != expected.absolute():
            errors.append(f"{cue_id}: Invalid or redirected path.")
            continue
        try:
            raw = path.read_bytes()
            with wave.open(str(path), "rb") as audio:
                channels, width, rate, count, compression, _ = audio.getparams()
                samples = array("h", audio.readframes(count))
            if sys.byteorder != "little":
                samples.byteswap()
            if (channels, width, rate, compression) != (1, 2, 44100, "NONE"):
                errors.append(f"{cue_id}: Unexpected WAV encoding.")
                continue
            duration_ms = count * 1000 / rate
            peak = max(abs(value) for value in samples) / 32768
            rms = math.sqrt(sum(value * value for value in samples) / len(samples)) / 32768
            dc = abs(sum(samples) / len(samples)) / 32768
            clipped = sum(abs(value) >= 32767 for value in samples)
            maximum_step = max(abs(right - left) for left, right in zip(samples, samples[1:])) / 32768
            if hashlib.sha256(raw).hexdigest() != cue.get("sha256"):
                errors.append(f"{cue_id}: SHA mismatch.")
            if abs(duration_ms - cue.get("durationMs", 0)) > .01 or not 50 <= duration_ms <= 1000:
                errors.append(f"{cue_id}: Incorrect or excessive duration.")
            if not 0 < peak <= .16 or clipped or dc > .001 or maximum_step > .03:
                errors.append(f"{cue_id}: Peak, clipping, DC offset, or sample discontinuity exceeds limit.")
            edge = round(.008 * rate)
            if any(samples[:edge]) or any(samples[-edge:]):
                errors.append(f"{cue_id}: The start/end silence guard is missing.")
            if abs(peak - cue.get("peakLinear", 0)) > .00000002:
                errors.append(f"{cue_id}: Manifest peak is inaccurate.")
            if abs(rms - cue.get("rmsLinear", 0)) > .00000002:
                errors.append(f"{cue_id}: Manifest RMS is inaccurate.")
            if cue.get("enabledByDefault") is not False or not 0 < cue.get("gain", 0) <= .5:
                errors.append(f"{cue_id}: Unsafe default/gain policy.")
            if cue.get("haptic") not in {"gentleTap", "success"}:
                errors.append(f"{cue_id}: Unknown semantic haptic ID.")
            results.append({"id": cue_id, "durationMs": duration_ms,
                            "peakLinear": round(peak, 8), "rmsLinear": round(rms, 8),
                            "absoluteDC": round(dc, 8), "clippedSamples": clipped,
                            "maximumSampleStep": round(maximum_step, 8)})
        except (OSError, wave.Error, ValueError, ZeroDivisionError) as error:
            errors.append(f"{cue_id}: {error}")
    return {"status": "PASS" if not errors else "FAIL", "errors": errors, "cues": results,
            "scope": "WAV/header/hash/amplitude/envelope/default checks; not a device listening test.",
            "deviceLoudnessVerified": False}


if __name__ == "__main__":
    result = validate()
    print(json.dumps(result, ensure_ascii=False, indent=2))
    raise SystemExit(1 if result["errors"] else 0)
