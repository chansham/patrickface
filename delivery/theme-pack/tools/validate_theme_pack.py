"""Validate the Patrick Face delivery package media, metadata, and audio."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import subprocess
import sys
import wave
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image


PACKAGE = Path(__file__).resolve().parent.parent
MANIFEST_PATH = PACKAGE / "MANIFEST.json"
REPORT_DIR = PACKAGE / "reports"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def ffprobe(path: Path) -> dict[str, Any]:
    process = subprocess.run(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "stream=codec_name,sample_rate,channels,duration:format=duration",
            "-of",
            "json",
            str(path),
        ],
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    return json.loads(process.stdout)


def validate() -> dict[str, Any]:
    errors: list[str] = []
    warnings: list[str] = []
    checks: list[dict[str, Any]] = []

    if not MANIFEST_PATH.exists():
        return {
            "status": "FAIL",
            "errors": [f"Missing manifest: {MANIFEST_PATH}"],
            "warnings": [],
            "checks": [],
        }

    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    records = manifest.get("assets", [])
    if manifest.get("asset_count") != len(records):
        errors.append(
            f"manifest asset_count={manifest.get('asset_count')} but has {len(records)} records"
        )

    duplicate_paths = [
        path for path, count in Counter(record["path"] for record in records).items() if count > 1
    ]
    if duplicate_paths:
        errors.append(f"Duplicate manifest paths: {duplicate_paths}")

    category_counts = Counter(record["category"] for record in records)
    retired = [
        "qr/create-new-shortcut-900x900.png",
        "qr/official-shortcuts-guide-900x900.png",
        "qr/run-patrick-mode-900x900.png",
        "qr/payloads/create-new-shortcut.txt",
        "qr/payloads/official-shortcuts-guide.txt",
        "qr/payloads/run-patrick-mode.txt",
        "source-layers/season1-3d-comparison-approved.png",
    ]
    for rel in retired:
        if (PACKAGE / rel).exists():
            errors.append(f"Retired/superseded delivery artifact reappeared: {rel}")
    current_sources = {
        "season1-2d-hour-arm-approved.png": "season1-hour-arm.png",
        "season1-2d-minute-arm-approved.png": "season1-minute-arm.png",
        "season1-3d-arm-approved.png": "season1-3d-arm.png",
    }
    for packaged, runtime in current_sources.items():
        candidate = PACKAGE / "source-layers" / packaged
        source = PACKAGE.parent.parent / "preview" / "assets" / runtime
        if not candidate.is_file() or not source.is_file() or sha256(candidate) != sha256(source):
            errors.append(f"Packaged source arm differs from current runtime: {packaged}")
    required_minimums = {
        "iphone-lock-wallpaper": 8,
        "iphone-home-wallpaper": 8,
        "standby-landscape-photo": 8,
        "apple-watch-photo-face-fallback": 12,
        "shortcuts-home-screen-icon": 20,
        "iphone-widget-background": 6,
        "watch-widget-complication-art": 12,
        "original-theme-sound": 10,
        "qr-deep-link": 3,
        "contact-sheet": 5,
    }
    for category, minimum in required_minimums.items():
        actual = category_counts.get(category, 0)
        if actual < minimum:
            errors.append(f"Category {category!r}: expected at least {minimum}, found {actual}")

    image_count = 0
    audio_count = 0
    total_bytes = 0
    manifest_media_paths: set[str] = set()
    wav_fingerprints: set[str] = set()

    for record in records:
        rel = record["path"]
        path = PACKAGE / Path(rel)
        manifest_media_paths.add(Path(rel).as_posix())
        if not path.exists():
            errors.append(f"Missing asset: {rel}")
            continue
        if not path.is_file():
            errors.append(f"Asset path is not a file: {rel}")
            continue

        actual_bytes = path.stat().st_size
        total_bytes += actual_bytes
        if actual_bytes <= 0:
            errors.append(f"Zero-byte asset: {rel}")
        if actual_bytes != record.get("bytes"):
            errors.append(
                f"Byte mismatch {rel}: manifest={record.get('bytes')} actual={actual_bytes}"
            )
        actual_hash = sha256(path)
        if actual_hash != record.get("sha256"):
            errors.append(f"SHA-256 mismatch: {rel}")

        suffix = path.suffix.lower()
        if suffix in {".png", ".jpg", ".jpeg"}:
            image_count += 1
            try:
                with Image.open(path) as image:
                    image.load()
                    width, height = image.size
                    mode = image.mode
                    if width != record.get("width") or height != record.get("height"):
                        errors.append(
                            f"Dimension mismatch {rel}: manifest="
                            f"{record.get('width')}x{record.get('height')} actual={width}x{height}"
                        )
                    if width < 1 or height < 1:
                        errors.append(f"Invalid image dimensions: {rel}")

                    filename_match = re.search(r"-(\d+)x(\d+)(?:@(?:2x|3x))?(?:-|\.|$)", path.name)
                    if filename_match:
                        named = (int(filename_match.group(1)), int(filename_match.group(2)))
                        if named != (width, height):
                            errors.append(
                                f"Filename dimensions do not match {rel}: "
                                f"name={named[0]}x{named[1]} actual={width}x{height}"
                            )

                    if record["category"] in {
                        "approved-source-layer",
                        "candidate-source-layer",
                        "transparent-character-composite",
                        "watch-complication-template",
                    }:
                        if "A" not in image.getbands():
                            errors.append(f"Expected alpha channel: {rel}")
                        elif image.getchannel("A").getextrema()[0] == 255:
                            errors.append(f"Expected transparent pixels: {rel}")

                    if record["category"] == "shortcuts-home-screen-icon":
                        if (width, height) != (1024, 1024):
                            errors.append(f"Shortcut icon is not 1024x1024: {rel}")
                        if mode not in {"RGB", "RGBA"}:
                            errors.append(f"Unexpected shortcut icon mode {mode}: {rel}")

                    if record["category"] == "iphone-lock-wallpaper":
                        top = image.convert("RGB").crop((0, 0, width, max(1, height // 4)))
                        luminance = float(np.asarray(top, dtype=np.float32).mean())
                        if luminance > 82:
                            warnings.append(
                                f"Lock clock-safe zone is relatively bright ({luminance:.1f}): {rel}"
                            )
            except Exception as exc:  # Pillow reports detailed decode errors.
                errors.append(f"Image decode failed {rel}: {exc}")

        elif suffix == ".wav":
            audio_count += 1
            try:
                with wave.open(str(path), "rb") as handle:
                    channels = handle.getnchannels()
                    sample_rate = handle.getframerate()
                    sample_width = handle.getsampwidth()
                    frames = handle.getnframes()
                    samples = np.frombuffer(handle.readframes(frames), dtype="<i2")
                duration = frames / sample_rate
                if channels != 2:
                    errors.append(f"WAV is not stereo: {rel}")
                if sample_rate != 48_000:
                    errors.append(f"WAV is not 48 kHz: {rel}")
                if sample_width != 2:
                    errors.append(f"WAV is not 16-bit PCM: {rel}")
                if not math.isclose(duration, float(record["duration_seconds"]), abs_tol=0.005):
                    errors.append(
                        f"WAV duration mismatch {rel}: manifest={record['duration_seconds']} actual={duration:.3f}"
                    )
                if samples.size == 0:
                    errors.append(f"WAV has no samples: {rel}")
                else:
                    peak = int(np.max(np.abs(samples.astype(np.int32))))
                    rms = float(np.sqrt(np.mean((samples.astype(np.float64) / 32768.0) ** 2)))
                    if peak >= 32767:
                        errors.append(f"WAV clips at full scale: {rel}")
                    if rms < 0.005:
                        errors.append(f"WAV is effectively silent: {rel}")
                    wav_fingerprints.add(hashlib.sha256(samples.tobytes()).hexdigest())
            except Exception as exc:
                errors.append(f"WAV validation failed {rel}: {exc}")

        elif suffix == ".m4a":
            audio_count += 1
            try:
                probe = ffprobe(path)
                streams = probe.get("streams", [])
                if len(streams) != 1:
                    errors.append(f"Expected one audio stream in {rel}, found {len(streams)}")
                else:
                    stream = streams[0]
                    if stream.get("codec_name") != "aac":
                        errors.append(f"M4A codec is not AAC: {rel}")
                    if int(stream.get("sample_rate", 0)) != 48_000:
                        errors.append(f"M4A is not 48 kHz: {rel}")
                    if int(stream.get("channels", 0)) != 2:
                        errors.append(f"M4A is not stereo: {rel}")
                    duration_value = stream.get("duration") or probe.get("format", {}).get("duration")
                    if duration_value is None:
                        errors.append(f"M4A duration unavailable: {rel}")
                    elif not math.isclose(
                        float(duration_value),
                        float(record["duration_seconds"]),
                        abs_tol=0.08,
                    ):
                        errors.append(
                            f"M4A duration mismatch {rel}: manifest={record['duration_seconds']} "
                            f"actual={float(duration_value):.3f}"
                        )
            except Exception as exc:
                errors.append(f"M4A validation failed {rel}: {exc}")

    if len(wav_fingerprints) != 5:
        errors.append(f"Expected five distinct WAV masters, found {len(wav_fingerprints)}")

    actual_media_paths = {
        path.relative_to(PACKAGE).as_posix()
        for pattern in ("*.png", "*.jpg", "*.jpeg", "*.wav", "*.m4a")
        for path in PACKAGE.rglob(pattern)
    }
    unmanifested = sorted(actual_media_paths - manifest_media_paths)
    if unmanifested:
        errors.append(f"Media files missing from manifest: {unmanifested}")
    nonexistent_records = sorted(manifest_media_paths - actual_media_paths)
    if nonexistent_records:
        errors.append(f"Manifest media paths not found on disk: {nonexistent_records}")

    required_docs = {
        "README.md": [
            "passive NFC tag",
            "cannot power case LEDs",
        ],
        "SETUP-GUIDE.md": [
            "Run Immediately",
            "inside the same phone’s fitted case is not a reliable trigger",
            "cannot directly power case LEDs",
            "personal automation is device-specific",
            "shortcuts://run-shortcut?name=Patrick%20Mode",
        ],
    }
    for filename, phrases in required_docs.items():
        path = PACKAGE / filename
        if not path.exists():
            errors.append(f"Missing required document: {filename}")
            continue
        content = path.read_text(encoding="utf-8")
        for phrase in phrases:
            if phrase not in content:
                errors.append(f"Required limitation missing from {filename}: {phrase!r}")

    payload_expectations = {
        "qr/payloads/verified-create-new-shortcut.txt": "shortcuts://create-shortcut",
        "qr/payloads/verified-run-patrick-mode.txt": "shortcuts://run-shortcut?name=Patrick%20Mode",
        "qr/payloads/verified-official-shortcuts-guide.txt": "https://support.apple.com/guide/shortcuts/welcome/ios",
    }
    for rel, expected in payload_expectations.items():
        path = PACKAGE / rel
        if not path.exists():
            errors.append(f"Missing QR payload: {rel}")
            continue
        if path.read_bytes() != expected.encode("utf-8"):
            errors.append(f"QR payload mismatch or trailing bytes: {rel}")
            continue
        qr_name = Path(rel).stem + "-900x900.png"
        qr_path = PACKAGE / "qr" / qr_name
        if not qr_path.exists():
            errors.append(f"Missing verified QR image: qr/{qr_name}")
            continue
        process = subprocess.run(
            [
                "ffmpeg",
                "-hide_banner",
                "-i",
                str(qr_path),
                "-vf",
                "quirc",
                "-frames:v",
                "1",
                "-f",
                "null",
                "NUL",
            ],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
        if process.returncode != 0 or f"payload: {expected}" not in process.stderr:
            errors.append(f"QR decode did not return expected payload: qr/{qr_name}")

    checks.extend(
        [
            {"name": "manifest_records", "value": len(records)},
            {"name": "decoded_images", "value": image_count},
            {"name": "validated_audio_files", "value": audio_count},
            {"name": "distinct_wav_masters", "value": len(wav_fingerprints)},
            {"name": "manifest_total_bytes", "value": total_bytes},
            {"name": "category_counts", "value": dict(sorted(category_counts.items()))},
            {"name": "unmanifested_media", "value": unmanifested},
        ]
    )
    return {
        "status": "PASS" if not errors else "FAIL",
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "package": str(PACKAGE),
        "manifest_package_version": manifest.get("package_version"),
        "errors": errors,
        "warnings": warnings,
        "checks": checks,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report-prefix", default="validation-report", help="Use a separate name to preserve an earlier report.")
    args = parser.parse_args()
    if Path(args.report_prefix).name != args.report_prefix:
        parser.error("Report prefix must be a filename, not a path.")
    result = validate()
    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    json_path = REPORT_DIR / f"{args.report_prefix}.json"
    text_path = REPORT_DIR / f"{args.report_prefix}.txt"
    json_path.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    lines = [
        f"Patrick Face theme pack validation: {result['status']}",
        f"Generated: {result.get('generated_utc', 'n/a')}",
        f"Package: {result.get('package', PACKAGE)}",
        "",
    ]
    for check in result.get("checks", []):
        lines.append(f"[CHECK] {check['name']}: {check['value']}")
    if result.get("warnings"):
        lines.append("")
        lines.extend(f"[WARN] {warning}" for warning in result["warnings"])
    if result.get("errors"):
        lines.append("")
        lines.extend(f"[ERROR] {error}" for error in result["errors"])
    lines.append("")
    text_path.write_text("\n".join(lines), encoding="utf-8")

    print("\n".join(lines))
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
