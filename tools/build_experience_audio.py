#!/usr/bin/env python3
"""Build deterministic, original, non-vocal short cues using sine synthesis.

No recordings, downloaded samples, image processing, or network are involved.
Run with --check for a read-only comparison against the reproducible output.
"""
from __future__ import annotations

import argparse
from array import array
import hashlib
import io
import json
import math
from pathlib import Path
import sys
import wave

ROOT = Path(__file__).resolve().parents[1]
DESTINATION = ROOT / "experience" / "audio"
SAMPLE_RATE = 44100
MASTER_PEAK = 0.15
GAIN = 0.45


def tone(track: list[float], start: float, duration: float, frequency: float,
         level: float = 1.0, end_frequency: float | None = None) -> None:
    """Add a phase-continuous sine with a smooth, zero-ended envelope."""
    first = round(start * SAMPLE_RATE)
    count = round(duration * SAMPLE_RATE)
    phase = 0.0
    for offset in range(count):
        index = first + offset
        if index >= len(track):
            break
        position = offset / (count - 1)
        pitch = frequency + ((end_frequency or frequency) - frequency) * position
        phase += 2 * math.pi * pitch / SAMPLE_RATE
        envelope = math.sin(math.pi * position) ** 2
        track[index] += level * envelope * math.sin(phase)


def make_cue(cue_id: str) -> tuple[bytes, dict]:
    durations = {"bubble": .34, "pet": .46, "feed": .42,
                 "complete": .78, "wake": .82, "softclick": .11}
    track = [0.0] * round(durations[cue_id] * SAMPLE_RATE)
    if cue_id == "bubble":
        tone(track, .018, .13, 440, .85, 930)
        tone(track, .16, .13, 710, .55, 1080)
    elif cue_id == "pet":
        tone(track, .018, .31, 392, .75, 440)
        tone(track, .09, .31, 587.33, .40, 659.25)
    elif cue_id == "feed":
        tone(track, .018, .11, 261.63, .70, 329.63)
        tone(track, .15, .19, 392, .85, 523.25)
    elif cue_id == "complete":
        for start, frequency in ((.018, 523.25), (.18, 659.25), (.35, 783.99)):
            tone(track, start, .34, frequency, .65)
        tone(track, .35, .34, 1046.5, .15)
    elif cue_id == "wake":
        tone(track, .018, .64, 392, .45)
        tone(track, .13, .60, 523.25, .60)
        tone(track, .29, .45, 659.25, .30)
    else:
        tone(track, .014, .058, 740, 1.0, 620)

    peak = max(abs(value) for value in track)
    pcm = array("h", (round(value / peak * MASTER_PEAK * 32767) for value in track))
    integer_peak = max(abs(value) for value in pcm)
    rms = math.sqrt(sum(value * value for value in pcm) / len(pcm)) / 32768
    if sys.byteorder != "little":
        pcm.byteswap()
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(SAMPLE_RATE)
        output.writeframes(pcm.tobytes())
    data = buffer.getvalue()
    peak_linear = integer_peak / 32768
    record = {
        "id": cue_id,
        "path": f"experience/audio/{cue_id}.wav",
        "durationMs": len(pcm) * 1000 / SAMPLE_RATE,
        "sha256": hashlib.sha256(data).hexdigest(),
        "gain": GAIN,
        "haptic": "success" if cue_id == "complete" else "gentleTap",
        "enabledByDefault": False,
        "sampleRateHz": SAMPLE_RATE,
        "channels": 1,
        "bitsPerSample": 16,
        "peakLinear": round(peak_linear, 8),
        "peakDbfs": round(20 * math.log10(peak_linear), 3),
        "rmsLinear": round(rms, 8),
        "clippedSamples": 0,
        "provenance": "Original deterministic sine synthesis; no voice or sampled recording.",
    }
    return data, record


def build(check: bool) -> None:
    # Resolve every destination before writing; never follow a redirected pack.
    if DESTINATION.resolve() != DESTINATION.absolute():
        raise ValueError("The audio directory must not be a symlink or junction.")
    outputs: dict[Path, bytes] = {}
    cues = []
    for cue_id in ("bubble", "pet", "feed", "complete", "wake", "softclick"):
        data, cue = make_cue(cue_id)
        outputs[DESTINATION / f"{cue_id}.wav"] = data
        cues.append(cue)
    manifest = {
        "schemaVersion": 1,
        "defaultEnabled": False,
        "format": "PCM signed 16-bit little-endian mono WAV, 44100 Hz",
        "generator": "tools/build_experience_audio.py",
        "hapticIDsAreSemantic": True,
        "playbackPolicy": {
            "foregroundOnly": True,
            "requiresUserEnable": True,
            "respectMuteAndAudioRoute": True,
            "neverReplaceSystemSounds": True,
            "noBackgroundKeepAlive": True,
            "avoidOverlappingCues": True,
        },
        "cues": cues,
    }
    outputs[DESTINATION / "manifest.json"] = (
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    for path in outputs:
        if path.resolve() != path.absolute():
            raise ValueError(f"Refusing redirected destination: {path}")
    if check:
        mismatches = [str(path.relative_to(ROOT)) for path, data in outputs.items()
                      if not path.is_file() or path.read_bytes() != data]
        if mismatches:
            raise ValueError("Audio pack differs from deterministic source: " + ", ".join(mismatches))
    else:
        DESTINATION.mkdir(parents=True, exist_ok=True)
        for path, data in outputs.items():
            if not path.is_file() or path.read_bytes() != data:
                path.write_bytes(data)
    print(json.dumps({"status": "MATCH" if check else "BUILT", "cues": len(cues),
                      "defaultEnabled": False, "maximumFilePeak": MASTER_PEAK,
                      "deviceLoudnessVerified": False}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Read-only deterministic comparison")
    args = parser.parse_args()
    try:
        build(args.check)
    except (ValueError, OSError) as error:
        parser.exit(1, f"error: {error}\n")
