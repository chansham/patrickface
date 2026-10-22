#!/usr/bin/env python3
"""Capture already-built iPhone/watchOS apps on installed Apple simulators.

Example (after build_apple_simulators.sh has built both products):
  python3 tools/capture_apple_simulators.py \
    --phone-app /tmp/build/phone/Build/Products/Debug-iphonesimulator/PatrickCompanion.app \
    --watch-app /tmp/build/watch/Build/Products/Debug-watchsimulator/PatrickFace.app \
    --phone-udid "$IOS_TEST_DEVICE_ID" --output /tmp/patrick-ci-logs/native-screens

No build, download, signing, real-device operation, erase or unpair is performed.
The requested Watch size defaults to 46 mm (42 or any can be selected). Within
that size, Apple Watch Series 12 is preferred when an installed runtime lists
it. Otherwise the closest supported 46 mm type already on the machine is kept
(Series 11 on current watchOS 26 runners) and the report records that fallback.
An existing pair with the supplied phone or an unpaired Watch is used.
If none is free, a named QA simulator is created using an installed compatible
runtime/device type. A separate QA phone can be created if pairing is necessary
and the supplied phone already has a companion; existing pairs are never removed.
--no-pairing disables creating simulator pairs. No runtime is downloaded.
--watch-geometry reads the Debug simulator-only Watch JSON probe after every
Watch screenshot, including each layout. Missing/stale probes are reported as
missing geometry evidence; a successful screenshot never implies probe success.
The supplied iPhone is captured first, so a missing watch runtime preserves its
evidence. Each invocation creates a new run directory and never reuses old PNGs.

Exit codes: 0 = both screens captured; 2 = partial; 1 = no capture/setup failure.
Capture is NOT visual approval: report.visualReview always remains pending.
Inspect PNGs for the app, correct orientation, intact head/feet, time and layout.

Apple sources (the installed Xcode's simctl help is also recorded each run):
https://developer.apple.com/videos/play/wwdc2020/10647/
https://developer.apple.com/videos/play/wwdc2019/418/
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import plistlib
import re
import shutil
import struct
import subprocess
import sys
import time
import zlib


UUID = re.compile(r"^[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$")
LAYOUT_IDS = ("classic", "bold", "theater", "activity")
WATCH_GEOMETRY_FILENAME = "patrick-watch-geometry.json"


class CaptureError(RuntimeError):
    pass


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def version(value: str) -> tuple[int, ...]:
    parts = tuple(int(x) for x in re.findall(r"\d+", value))
    return (parts + (0, 0, 0))[:3]


def devices(payload: dict, platform: str, minimum: str = "0") -> list[dict]:
    runtimes = {x["identifier"]: x for x in payload.get("runtimes", [])}
    types = {x["identifier"]: x for x in payload.get("devicetypes", [])}
    result = []
    for runtime_id, entries in payload.get("devices", {}).items():
        match = re.fullmatch(r"com\.apple\.CoreSimulator\.SimRuntime\." + platform + r"-(\d+(?:-\d+)*)", runtime_id)
        runtime = runtimes.get(runtime_id, {})
        if not match or runtime.get("isAvailable") is not True or version(match[1]) < version(minimum):
            continue
        for entry in entries:
            if entry.get("isAvailable") is not True or not UUID.fullmatch(str(entry.get("udid", ""))):
                continue
            device_type = types.get(entry.get("deviceTypeIdentifier"), {})
            if platform == "iOS" and (device_type.get("productFamily") != "iPhone" if device_type
                                      else not entry.get("name", "").startswith("iPhone")):
                continue
            result.append({**entry, "runtime": runtime_id, "runtimeVersion": match[1],
                           "deviceTypeName": device_type.get("name", entry.get("name", "")),
                           "modelIdentifier": device_type.get("modelIdentifier")})
    return result


def pair_members(payload: dict) -> list[tuple[str, str, str]]:
    raw = payload.get("pairs")
    if not isinstance(raw, dict):
        raise CaptureError("simctl did not expose a recognizable pairs inventory; safe pairing is unavailable")
    result = []
    for pair_id, item in raw.items():
        try:
            watch, phone = item["watch"]["udid"], item["phone"]["udid"]
        except (KeyError, TypeError) as error:
            raise CaptureError("Unrecognized simulator pair; existing pairing will not be changed") from error
        if not UUID.fullmatch(str(watch)) or not UUID.fullmatch(str(phone)):
            raise CaptureError("Invalid simulator pair identifiers")
        result.append((str(pair_id), watch.upper(), phone.upper()))
    return result


def matches_watch_size(item: dict, size: str) -> bool:
    label = item.get("deviceTypeName", item.get("name", "")).replace(" ", "").lower()
    return size == "any" or f"{size}mm" in label


def watch_series_number(item: dict) -> int | None:
    label = item.get("deviceTypeName", item.get("name", ""))
    match = re.search(r"Series\s+(\d+)", str(label), re.IGNORECASE)
    return int(match.group(1)) if match else None


def series12_46_rank(item: dict) -> bool:
    """Owner's watch is Series 12 46mm. Prefer it only when this runtime can create it."""
    return watch_series_number(item) == 12 and matches_watch_size(item, "46")


def select_watch(payload: dict, phone_id: str, minimum: str, size: str = "any") -> dict:
    pairs = pair_members(payload)
    target = phone_id.upper()
    candidates = []
    for item in devices(payload, "watchOS", minimum):
        if not matches_watch_size(item, size):
            continue
        watch = item["udid"].upper()
        partners = [phone for _, paired_watch, phone in pairs if paired_watch == watch]
        # Do not borrow a watch belonging to another simulator phone.
        if any(phone != target for phone in partners):
            continue
        # Prefer the user's 46 mm target when it does not disturb an existing pair.
        # Series 12 46mm outranks an already-paired older case when this runtime has one.
        key = (series12_46_rank(item), target in partners, matches_watch_size(item, "46"),
               item.get("state") == "Booted", version(item["runtimeVersion"]), item.get("name", ""), watch)
        candidates.append((key, item))
    if not candidates:
        raise CaptureError("No available installed watchOS simulator meets the app minimum OS and safe-pairing constraints; no runtime was downloaded")
    return max(candidates, key=lambda candidate: candidate[0])[1]


def watch_creation_spec(payload: dict, minimum: str, size: str) -> tuple[dict, dict]:
    """Only combinations explicitly advertised by an installed watchOS runtime."""
    types = {x["identifier"]: x for x in payload.get("devicetypes", [])}
    candidates = []
    for runtime in payload.get("runtimes", []):
        runtime_id = runtime.get("identifier", "")
        match = re.fullmatch(r"com\.apple\.CoreSimulator\.SimRuntime\.watchOS-(\d+(?:-\d+)*)", runtime_id)
        if not match or runtime.get("isAvailable") is not True or version(match[1]) < version(minimum):
            continue
        for supported in runtime.get("supportedDeviceTypes", []):
            identifier = supported.get("identifier") if isinstance(supported, dict) else supported
            device_type = types.get(identifier)
            if not device_type or device_type.get("productFamily") != "Apple Watch" or not matches_watch_size(device_type, size):
                continue
            runtime_version = version(match[1])
            if not version(device_type.get("minRuntimeVersionString", "0")) <= runtime_version <= version(device_type.get("maxRuntimeVersionString", "65535.255.255")):
                continue
            key = (series12_46_rank(device_type), runtime_version, matches_watch_size(device_type, "46"),
                   version(device_type.get("minRuntimeVersionString", "0")), device_type["name"])
            candidates.append((key, device_type, runtime))
    if not candidates:
        raise CaptureError(f"No installed watchOS runtime explicitly supports a {size} mm QA device; no runtime was downloaded")
    _, device_type, runtime = max(candidates, key=lambda item: item[0])
    return device_type, runtime


def create_qa_device(runner: Runner, device_type: dict, runtime: dict, platform: str, minimum: str) -> dict:
    name = f"Patrick QA {device_type['name']} {runner.output.name}"
    created = runner.simctl("create", name, device_type["identifier"], runtime["identifier"], timeout=60)
    identifier = created.stdout.strip()
    if not UUID.fullmatch(identifier):
        raise CaptureError("simctl create did not return an explicit simulator UUID")
    record = {"udid": identifier, "name": name, "deviceTypeName": device_type["name"],
              "deviceTypeIdentifier": device_type["identifier"], "runtime": runtime["identifier"]}
    runner.report.setdefault("createdSimulators", []).append(record)
    inventory = runner.inventory(f"devices-after-create-{len(runner.report['createdSimulators'])}.json")
    selected = next((d for d in devices(inventory, platform, minimum) if d["udid"].upper() == identifier.upper()), None)
    if not selected:
        raise CaptureError("Created simulator is not available on the requested installed runtime")
    return selected


def can_pair(payload: dict, phone: str, watch: str) -> bool:
    return phone.upper() != watch.upper() and not any(
        w == watch.upper() or p == phone.upper() for _, w, p in pair_members(payload))


def app_info(path: Path, platform: str) -> dict:
    if not path.is_dir() or path.suffix != ".app":
        raise CaptureError(f"Missing compiled .app directory: {path}")
    try:
        info = plistlib.loads((path / "Info.plist").read_bytes())
    except (OSError, plistlib.InvalidFileException) as error:
        raise CaptureError(f"Cannot read compiled app Info.plist: {path}") from error
    supported = "iPhoneSimulator" if platform == "iOS" else "WatchSimulator"
    if supported not in info.get("CFBundleSupportedPlatforms", []):
        raise CaptureError(f"{path.name} is not a {supported} build; no device app will be installed")
    identifier, executable = info.get("CFBundleIdentifier"), info.get("CFBundleExecutable")
    if not isinstance(identifier, str) or not re.fullmatch(r"[A-Za-z0-9_.-]+", identifier):
        raise CaptureError("Compiled app has an invalid bundle identifier")
    if not isinstance(executable, str) or Path(executable).name != executable or not (path / executable).is_file():
        raise CaptureError("Compiled app executable is missing or invalid")
    return {"path": str(path), "bundleID": identifier, "executable": executable,
            "minimumOS": str(info.get("MinimumOSVersion", "0")), "platform": supported}


def png_info(path: Path) -> dict:
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise CaptureError("Screenshot is not a PNG")
    offset, dimensions, has_pixels, ended = 8, None, False, False
    while offset + 12 <= len(data):
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        end = offset + 12 + length
        if end > len(data):
            raise CaptureError("Screenshot PNG is truncated")
        kind = data[offset + 4:offset + 8]
        chunk = data[offset + 8:offset + 8 + length]
        checksum = struct.unpack(">I", data[offset + 8 + length:end])[0]
        if zlib.crc32(kind + chunk) & 0xFFFFFFFF != checksum:
            raise CaptureError("Screenshot PNG checksum mismatch")
        if kind == b"IHDR" and length == 13:
            dimensions = struct.unpack(">II", chunk[:8])
        elif kind == b"IDAT" and length:
            has_pixels = True
        elif kind == b"IEND":
            ended = True
            break
        offset = end
    if not dimensions or min(dimensions) <= 0 or not has_pixels or not ended:
        raise CaptureError("Screenshot PNG has no complete image data")
    return {"width": dimensions[0], "height": dimensions[1], "bytes": len(data),
            "sha256": hashlib.sha256(data).hexdigest()}


class Runner:
    def __init__(self, output: Path, report: dict):
        self.output, self.report = output, report

    def command(self, args: list[str], *, timeout: float = 60, required: bool = True) -> subprocess.CompletedProcess:
        step = len(self.report["commands"]) + 1
        record = {"argv": args, "startedAt": utc_now(), "timeoutSeconds": timeout}
        self.report["commands"].append(record)
        print("+ " + " ".join(args), flush=True)
        try:
            value = subprocess.run(args, capture_output=True, text=True, errors="replace", timeout=timeout, check=False)
        except subprocess.TimeoutExpired as error:
            def as_text(raw):
                return raw.decode("utf-8", errors="replace") if isinstance(raw, bytes) else raw or ""
            value = subprocess.CompletedProcess(args, 124, as_text(error.stdout), as_text(error.stderr) + "\nCommand timed out")
        except OSError as error:
            value = subprocess.CompletedProcess(args, 127, "", str(error))
        stem = f"command-{step:03d}"
        (self.output / f"{stem}.stdout.txt").write_text(value.stdout, encoding="utf-8")
        (self.output / f"{stem}.stderr.txt").write_text(value.stderr, encoding="utf-8")
        record.update({"finishedAt": utc_now(), "returnCode": value.returncode,
                       "stdout": f"{stem}.stdout.txt", "stderr": f"{stem}.stderr.txt"})
        if required and value.returncode != 0:
            raise CaptureError(f"Command failed ({value.returncode}): {' '.join(args)}; {(value.stderr or value.stdout)[-1800:]}")
        return value

    def simctl(self, *args: str, **kwargs) -> subprocess.CompletedProcess:
        return self.command(["xcrun", "simctl", *args], **kwargs)

    def inventory(self, name: str) -> dict:
        value = self.simctl("list", "--json")
        (self.output / name).write_text(value.stdout, encoding="utf-8")
        return json.loads(value.stdout)


def boot(runner: Runner, item: dict, timeout: float) -> None:
    # -b boots a shutdown simulator and blocks until boot has completed.
    runner.simctl("bootstatus", item["udid"], "-b", timeout=timeout)


def install_and_launch(runner: Runner, device: dict, app: dict, arguments: tuple[str, ...]) -> subprocess.CompletedProcess:
    runner.simctl("install", device["udid"], app["path"], timeout=120)
    return runner.simctl("launch", "--terminate-running-process", device["udid"], app["bundleID"], *arguments, timeout=90)


def validate_watch_geometry(payload: dict, *, bundle_id: str, pid: int, layout: str | None,
                            launch_started_at: str) -> dict:
    """Validate identity and arithmetic, never invent active or wrist state."""
    if not isinstance(payload, dict) or payload.get("schemaVersion") != 1 or payload.get("kind") != "patrick-watch-geometry" \
            or payload.get("debugSimulator") is not True or payload.get("bundleID") != bundle_id or payload.get("processID") != pid:
        raise CaptureError("Geometry probe is not from this Debug simulator app process")
    timestamp, epoch_ms = payload.get("recordedAt"), payload.get("recordedAtEpochMS")
    if not isinstance(timestamp, str) or type(epoch_ms) not in (int, float) or not math.isfinite(epoch_ms):
        raise CaptureError("Geometry probe has no valid ISO and epoch timestamps")
    recorded = datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
    launched = datetime.fromisoformat(launch_started_at.replace("Z", "+00:00"))
    if recorded.tzinfo is None or launched.tzinfo is None or (recorded - launched).total_seconds() < -2 \
            or (recorded - datetime.now(timezone.utc)).total_seconds() > 5:
        raise CaptureError("Geometry probe timestamp is stale or invalid")
    if abs(recorded.timestamp() * 1000 - epoch_ms) > 2:
        raise CaptureError("Geometry probe ISO and epoch timestamps disagree")
    value = payload.get("observation")
    if not isinstance(value, dict) or value.get("layoutID") not in LAYOUT_IDS \
            or (layout is not None and value["layoutID"] != layout):
        raise CaptureError("Geometry probe is for a different layout")
    if value.get("scenePhase") not in ("active", "inactive", "background", "unknown") \
            or any(type(value.get(key)) is not bool for key in ("visible", "wristDown", "monitoring", "reduceMotion", "lowPower")):
        raise CaptureError("Geometry probe has no recognizable actual lifecycle state")

    def number(raw, low: float = -8192, high: float = 8192) -> float:
        if type(raw) not in (int, float) or not math.isfinite(raw) or not low <= raw <= high:
            raise CaptureError("Geometry probe contains an invalid or implausible measurement")
        return float(raw)

    def pair(key: str) -> tuple[float, float]:
        item = value.get(key, {})
        if not isinstance(item, dict): raise CaptureError("Geometry size is not an object")
        return number(item.get("width"), 0.001), number(item.get("height"), 0.001)

    width, height = pair("geometrySizePoints")
    stage_width, stage_height = pair("stageSizePoints")
    pixels = pair("stageSizePixels")
    pair("screenBoundsPoints")
    pair("geometryFrameGlobalPoints")
    insets = value.get("safeAreaInsetsPoints", {})
    if not isinstance(insets, dict): raise CaptureError("Geometry safe area is not an object")
    for key in ("top", "leading", "bottom", "trailing"): number(insets.get(key), 0)
    for key in ("screenBoundsPoints", "geometryFrameGlobalPoints", "stageOriginInGeometryPoints"):
        item = value.get(key, {})
        if not isinstance(item, dict): raise CaptureError("Geometry position is not an object")
        for axis in ("x", "y"): number(item.get(axis))
    scale = number(value.get("screenScale"), 0.5, 8)
    unit = number(value.get("outerUnit416"), 0.000001, 20)
    inner = number(value.get("innerUnit832"), 0.000001, 10)
    expected = [(unit, min(width / 416, height / 496)), (inner, unit / 2),
                (stage_width, 416 * unit), (stage_height, 496 * unit),
                (pixels[0], stage_width * scale), (pixels[1], stage_height * scale),
                (value["stageOriginInGeometryPoints"]["x"], (width - stage_width) / 2),
                (value["stageOriginInGeometryPoints"]["y"], (height - stage_height) / 2)]
    if any(not math.isclose(a, b, abs_tol=1e-6, rel_tol=1e-9) for a, b in expected):
        raise CaptureError("Geometry probe stage arithmetic does not match the native renderer")
    return payload


def collect_watch_geometry(runner: Runner, device: dict, app: dict, pid: int, layout: str | None,
                           launch_started_at: str, stem: str, screenshot: dict) -> dict:
    result = {"status": "unavailable", "evidence": "No valid native geometry evidence was collected."}
    try:
        # The installed tool's own help must advertise the operation before use.
        support = runner.report.get("geometryContainerSupport")
        if support is None:
            help_result = runner.simctl("help", "get_app_container", required=False)
            help_text = help_result.stdout + help_result.stderr
            support = {"supported": help_result.returncode == 0 and "get_app_container" in help_text
                       and re.search(r"\bdata\b", help_text) is not None,
                       "syntax": "simctl get_app_container <device> <bundle-id> data"}
            runner.report["geometryContainerSupport"] = support
        if not support["supported"]:
            raise CaptureError("Installed simctl help does not confirm get_app_container with a data container")
        command = runner.simctl("get_app_container", device["udid"], app["bundleID"], "data", required=False)
        if command.returncode != 0:
            raise CaptureError("simctl could not locate this app's data container")
        raw_path = command.stdout.strip()
        container = Path(raw_path)
        if not container.is_absolute() or not container.is_dir():
            raise CaptureError("simctl returned no existing absolute app data container")
        container = container.resolve()
        source = (container / "Documents" / WATCH_GEOMETRY_FILENAME).resolve()
        source.relative_to(container)
        if not source.is_file():
            raise CaptureError("Debug simulator geometry file is missing; no geometry was inferred from the PNG")
        if source.stat().st_size > 65536:
            raise CaptureError("Geometry probe exceeds the diagnostic size limit")
        raw = source.read_bytes()
        payload = validate_watch_geometry(json.loads(raw), bundle_id=app["bundleID"], pid=pid,
                                          layout=layout, launch_started_at=launch_started_at)
        filename = f"{stem}.geometry.json"
        (runner.output / filename).write_bytes(raw)
        observation = payload["observation"]
        scale = observation["screenScale"]
        bounds = observation["screenBoundsPoints"]
        return {"status": "captured", "path": filename, "sha256": hashlib.sha256(raw).hexdigest(),
                "source": "App Documents Debug simulator probe", "payload": payload,
                "screenMatchesScreenshot": abs(bounds["width"] * scale - screenshot["width"]) <= 1
                    and abs(bounds["height"] * scale - screenshot["height"]) <= 1}
    except (CaptureError, OSError, ValueError, TypeError, KeyError) as error:
        result["reason"] = str(error)
        return result


def capture(runner: Runner, label: str, device: dict, app: dict, delays: list[float], boot_timeout: float,
            layout: str | None = None, *, geometry_probe: bool = False) -> dict:
    result = {"device": device, "app": app, "status": "failed", "screenshots": [],
              "visualReview": "pending", "startedAt": utc_now()}
    try:
        if layout is not None and layout not in LAYOUT_IDS:
            raise CaptureError("Unknown layout override")
        boot(runner, device, boot_timeout)
        arguments = ("--patrick-preview-layout", layout) if layout else ()
        result["requestedLayout"] = layout
        launch_started_at = utc_now()
        result["launchStartedAt"] = launch_started_at
        # XCTest leaves this simulator booted. simctl launch can then sit until the
        # timeout (exit 124) without returning a pid. One shutdown and boot is enough
        # to recover; a second timeout is still a capture failure.
        try:
            launch = install_and_launch(runner, device, app, arguments)
        except CaptureError as error:
            if "(124)" not in str(error):
                raise
            result["launchRetry"] = "rebooted after simctl launch timed out"
            runner.simctl("shutdown", device["udid"], timeout=60, required=False)
            boot(runner, device, boot_timeout)
            launch_started_at = utc_now()
            result["launchStartedAt"] = launch_started_at
            launch = install_and_launch(runner, device, app, arguments)
        match = re.search(r"^" + re.escape(app["bundleID"]) + r":\s*(\d+)\s*$", launch.stdout, re.MULTILINE)
        if not match:
            raise CaptureError("simctl launch did not report the requested app's process ID")
        pid = int(match[1])
        result["pid"] = pid
        launched = time.monotonic()
        for index, delay in enumerate(delays, 1):
            time.sleep(max(0, delay - (time.monotonic() - launched)))
            process = runner.command(["/bin/ps", "-p", str(pid), "-o", "pid=", "-o", "command="], timeout=10)
            if app["executable"] not in process.stdout:
                raise CaptureError("Launched app process is no longer identifiable; refusing a success claim for a system-screen capture")
            filename = f"{label}-{index:02d}-{delay:g}s.png"
            path = runner.output / filename
            runner.simctl("io", device["udid"], "screenshot", "--type=png", str(path), timeout=45)
            screenshot = {"path": filename, "elapsedSeconds": round(time.monotonic() - launched, 3),
                          "capturedAt": utc_now(), **png_info(path)}
            if geometry_probe:
                screenshot["geometryProbe"] = collect_watch_geometry(runner, device, app, pid, layout,
                    launch_started_at, path.stem, screenshot)
            result["screenshots"].append(screenshot)
        result["status"] = "captured"
    except (CaptureError, OSError) as error:
        result["error"] = str(error)
    result["finishedAt"] = utc_now()
    return result


def capture_watch(runner: Runner, args, phone: dict, app: dict, delays: list[float]) -> dict:
    size = getattr(args, "watch_size", "46")
    result = {"status": "blocked", "visualReview": "pending", "attempts": [], "pairing": "not-needed",
              "requestedSizeMM": size, "deviceSelection": "existing"}
    try:
        inventory = runner.inventory("devices-before-watch.json")
        pair_members(inventory)  # Refuse unknown pairing state before creating anything.
        try:
            watch = select_watch(inventory, phone["udid"], app["minimumOS"], size)
        except CaptureError:
            device_type, runtime = watch_creation_spec(inventory, app["minimumOS"], size)
            watch = create_qa_device(runner, device_type, runtime, "watchOS", app["minimumOS"])
            result["deviceSelection"] = "created-qa-watch"
        result["device"] = watch
        if not series12_46_rank(watch):
            result["series12Fallback"] = (
                "Installed runtime has no usable Apple Watch Series 12 46mm; "
                "kept the closest supported 46mm."
            )
        first = capture(runner, "watch", watch, app, delays, args.boot_timeout,
                        geometry_probe=getattr(args, "watch_geometry", False))
        result["attempts"].append(first)
        if first["status"] == "captured":
            result["status"] = "captured"
            return result
        if args.no_pairing:
            raise CaptureError("Watch direct launch/capture failed and simulator pairing was disabled")
        inventory = runner.inventory("devices-before-pair.json")
        pairs = pair_members(inventory)
        if any(w == watch["udid"].upper() for _, w, _ in pairs):
            raise CaptureError("Watch direct launch/capture failed on an already-paired Watch; no existing pair was changed")
        pair_phone = phone
        if any(p == phone["udid"].upper() for _, _, p in pairs):
            # The original test phone and its companion remain untouched. A new
            # installed-runtime phone is used only for this QA Watch's pairing.
            device_type = next((t for t in inventory.get("devicetypes", [])
                                if t.get("identifier") == phone.get("deviceTypeIdentifier")), None)
            runtime = next((r for r in inventory.get("runtimes", [])
                            if r.get("identifier") == phone["runtime"] and r.get("isAvailable") is True), None)
            if not device_type or not runtime:
                raise CaptureError("No installed type/runtime is available to create a separate QA pairing phone")
            pair_phone = create_qa_device(runner, device_type, runtime, "iOS", "0")
            inventory = runner.inventory("devices-before-qa-pair.json")
        if not can_pair(inventory, pair_phone["udid"], watch["udid"]):
            raise CaptureError("A pre-existing pair prevents safe QA pairing; no existing pair was removed")
        result["pairingPhone"] = pair_phone
        result["pairing"] = "attempted-with-two-unpaired-simulators"
        # Only the explicit test phone and the selected unpaired watch are touched.
        # simctl is authoritative about platform compatibility; failure is reported.
        for item in (watch, pair_phone):
            current = next((d for values in inventory.get("devices", {}).values() for d in values
                            if d.get("udid", "").upper() == item["udid"].upper()), None)
            if current and current.get("state") != "Shutdown":
                runner.simctl("shutdown", item["udid"], timeout=60)
        try:
            paired = runner.simctl("pair", watch["udid"], pair_phone["udid"], timeout=120)
            result["pairing"] = "created"
            result["pairOutput"] = paired.stdout.strip()
        finally:
            # Restore only the phone participating in this new QA pair.
            boot(runner, pair_phone, args.boot_timeout)
        if pair_phone["udid"] != phone["udid"]:
            runner.simctl("install", pair_phone["udid"], str(args.phone_app.expanduser().resolve()), timeout=120)
        second = capture(runner, "watch-paired", watch, app, delays, args.boot_timeout,
                         geometry_probe=getattr(args, "watch_geometry", False))
        result["attempts"].append(second)
        result["status"] = second["status"]
        if second["status"] != "captured":
            result["error"] = second.get("error", "Paired watch capture failed")
    except (CaptureError, OSError, ValueError) as error:
        result["error"] = str(error)
        result["status"] = "failed" if result["attempts"] else "blocked"
    return result


def run(args) -> int:
    root = args.output.expanduser().resolve()
    output = root / (datetime.now(timezone.utc).strftime("run-%Y%m%dT%H%M%SZ-") + str(os.getpid()))
    output.mkdir(parents=True, exist_ok=False)
    report = {"schemaVersion": 2, "startedAt": utc_now(), "status": "failed", "visualReview": "pending",
              "captureIsNotVisualApproval": True, "commands": [],
              "requestedWatchSizeMM": getattr(args, "watch_size", "46"), "createdSimulators": [],
              "phone": {"status": "blocked"}, "watch": {"status": "blocked"},
              "limitations": ["PNG capture and process liveness do not prove foreground UI or correct artwork. Inspect every PNG.",
                              "No real device, WatchConnectivity correctness, signing or installation eligibility is tested."]}
    runner = Runner(output, report)
    try:
        if sys.platform != "darwin" or not shutil.which("xcrun"):
            raise CaptureError("Capture requires macOS and an existing Xcode installation; no runtime or tool will be downloaded")
        phone_app = app_info(args.phone_app.expanduser().resolve(), "iOS")
        runner.command(["xcodebuild", "-version"])
        for topic in ((), ("bootstatus",), ("launch",), ("pair",), ("create",), ("io",)):
            runner.simctl("help", *topic, required=False)
        inventory = runner.inventory("devices-initial.json")
        eligible = devices(inventory, "iOS", phone_app["minimumOS"])
        phone = next((d for d in eligible if d["udid"].upper() == args.phone_udid.upper()), None)
        if phone is None:
            raise CaptureError("The supplied phone UDID is not an available installed iPhone simulator compatible with this build")
        report["phone"] = capture(runner, "phone", phone, phone_app, args.delays, args.boot_timeout)
        # A broken/missing watch product must not prevent the iPhone capture above.
        watch_app = None
        try:
            watch_app = app_info(args.watch_app.expanduser().resolve(), "watchOS")
            report["watch"] = capture_watch(runner, args, phone, watch_app, args.delays)
        except (CaptureError, OSError) as error:
            report["watch"]["error"] = str(error)
        # Explicit simulator-only view overrides. No preferences, real devices or
        # source image pixels are changed; successful captures still need review.
        for key, device, app in (("phone", phone, phone_app),
                                 ("watch", report["watch"].get("device"), watch_app)):
            if report[key]["status"] != "captured" or not app or not device:
                continue
            if getattr(args, "layouts", []):
                report[key]["layouts"] = {
                    layout: capture(runner, f"{key}-layout-{layout}", device, app, [3], args.boot_timeout, layout,
                                    geometry_probe=key == "watch" and getattr(args, "watch_geometry", False))
                    for layout in args.layouts
                }
        runner.inventory("devices-final.json")
    except (CaptureError, OSError, ValueError) as error:
        report["error"] = str(error)
    finally:
        count = sum(report[key].get("status") == "captured" for key in ("phone", "watch"))
        layouts_ok = all(set(report[key].get("layouts", {})) == set(getattr(args, "layouts", []))
                         and all(item["status"] == "captured" for item in report[key].get("layouts", {}).values())
                         for key in ("phone", "watch"))
        report["status"] = "captured" if count == 2 and layouts_ok and "error" not in report else "partial" if count else "failed"
        watch_captures = [*report["watch"].get("attempts", []), *report["watch"].get("layouts", {}).values()]
        probes = [shot.get("geometryProbe", {}) for item in watch_captures for shot in item.get("screenshots", [])]
        good = sum(probe.get("status") == "captured" for probe in probes)
        requested = getattr(args, "watch_geometry", False)
        report["geometryEvidence"] = {"requested": requested, "captured": good, "screenshots": len(probes),
            "status": "not-requested" if not requested else "complete" if probes and good == len(probes)
                else "partial" if good else "unavailable"}
        report["finishedAt"] = utc_now()
        (output / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        fallback = report.get("watch", {}).get("series12Fallback")
        note = f"; {fallback}" if fallback else ""
        print(f"Native capture: {report['status']}; visual review: pending{note}; report: {output / 'report.json'}", flush=True)
    return 0 if report["status"] == "captured" else 2 if report["status"] == "partial" else 1


def self_test() -> int:
    """Pure fixtures only: these are not simulator or native UI test results."""
    import tempfile
    import unittest
    from unittest.mock import patch

    class Fixtures(unittest.TestCase):
        def geometry_payload(self, layout="classic"):
            now = datetime.now(timezone.utc)
            unit = 160 / 496
            return {"schemaVersion": 1, "kind": "patrick-watch-geometry", "debugSimulator": True,
                "bundleID": "example.fixture", "processID": 123, "recordedAt": now.isoformat(),
                "recordedAtEpochMS": now.timestamp() * 1000, "event": "change",
                "observation": {"layoutID": layout, "scenePhase": "inactive", "visible": True,
                    "wristDown": True, "monitoring": False, "reduceMotion": False, "lowPower": False,
                    "geometrySizePoints": {"width": 208, "height": 160},
                    "geometryFrameGlobalPoints": {"x": 0, "y": 44, "width": 208, "height": 160},
                    "safeAreaInsetsPoints": {"top": 28, "bottom": 16, "leading": 0, "trailing": 0},
                    "outerUnit416": unit, "innerUnit832": unit / 2,
                    "stageSizePoints": {"width": 416 * unit, "height": 160},
                    "stageOriginInGeometryPoints": {"x": (208 - 416 * unit) / 2, "y": 0},
                    "stageSizePixels": {"width": 832 * unit, "height": 320},
                    "screenBoundsPoints": {"x": 0, "y": 0, "width": 208, "height": 248}, "screenScale": 2}}

        def test_geometry_identity_freshness_and_arithmetic(self):
            source = self.geometry_payload()
            args = {"bundle_id": "example.fixture", "pid": 123, "layout": "classic", "launch_started_at": utc_now()}
            self.assertEqual(validate_watch_geometry(source, **args), source)
            self.assertTrue(source["observation"]["wristDown"])
            self.assertEqual(source["observation"]["scenePhase"], "inactive")
            for key, value in (("processID", 122), ("bundleID", "another.app"), ("debugSimulator", False),
                               ("recordedAt", "2000-01-01T00:00:00Z"), ("recordedAtEpochMS", 0)):
                with self.subTest(key=key), self.assertRaises(CaptureError):
                    validate_watch_geometry({**source, key: value}, **args)
            for key, value in (("layoutID", "bold"), ("screenScale", float("nan")), ("outerUnit416", 1),
                               ("stageSizePixels", {"width": 416, "height": 496})):
                with self.subTest(observation=key), self.assertRaises(CaptureError):
                    validate_watch_geometry({**source, "observation": {**source["observation"], key: value}}, **args)

        def test_geometry_collect_queries_help_then_copies_this_process(self):
            with tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary); output = root / "qa"; output.mkdir()
                container = root / "data"; documents = container / "Documents"; documents.mkdir(parents=True)
                payload = self.geometry_payload("bold")
                raw = json.dumps(payload).encode(); (documents / WATCH_GEOMETRY_FILENAME).write_bytes(raw)
                runner = Runner(output, {"commands": []})
                replies = [subprocess.CompletedProcess([], 0, "Usage: simctl get_app_container <device> <app> [data]", ""),
                           subprocess.CompletedProcess([], 0, str(container), "")]
                with patch.object(runner, "simctl", side_effect=replies) as command:
                    result = collect_watch_geometry(runner, {"udid": "fixture-watch"}, {"bundleID": "example.fixture"},
                        123, "bold", utc_now(), "watch-layout-bold", {"width": 416, "height": 496})
                self.assertEqual([call.args for call in command.call_args_list],
                    [("help", "get_app_container"), ("get_app_container", "fixture-watch", "example.fixture", "data")])
                self.assertEqual(result["status"], "captured")
                self.assertEqual((output / result["path"]).read_bytes(), raw)
                self.assertTrue(result["screenMatchesScreenshot"])
                self.assertTrue(result["payload"]["observation"]["wristDown"])

        def test_geometry_missing_or_unsupported_is_not_capture_evidence(self):
            with tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary); runner = Runner(root, {"commands": []})
                common = (runner, {"udid": "fixture-watch"}, {"bundleID": "example.fixture"}, 123,
                          "classic", utc_now(), "missing", {"width": 416, "height": 496})
                with patch.object(runner, "simctl", return_value=subprocess.CompletedProcess([], 1, "", "unsupported")) as command:
                    result = collect_watch_geometry(*common)
                self.assertEqual(result["status"], "unavailable")
                self.assertEqual(command.call_count, 1)
                runner.report["geometryContainerSupport"] = {"supported": True}
                with patch.object(runner, "simctl", return_value=subprocess.CompletedProcess([], 0, str(root), "")):
                    result = collect_watch_geometry(*common)
                self.assertEqual(result["status"], "unavailable")
                self.assertIn("missing", result["reason"])
                self.assertFalse((root / "missing.geometry.json").exists())

        def test_every_layout_capture_collects_its_own_geometry(self):
            _, watch, _, data = self.payload()
            device = devices(data, "watchOS")[0]
            app = {"path": "Watch.app", "bundleID": "example.fixture", "executable": "Fixture"}
            with tempfile.TemporaryDirectory() as temporary:
                runner = Runner(Path(temporary), {"commands": []})
                with patch(__name__ + ".boot"), patch(__name__ + ".png_info", return_value={"width": 416, "height": 496}), \
                     patch.object(runner, "simctl", return_value=subprocess.CompletedProcess([], 0, "example.fixture: 123\n", "")), \
                     patch.object(runner, "command", return_value=subprocess.CompletedProcess([], 0, "123 Fixture", "")), \
                     patch(__name__ + ".collect_watch_geometry", return_value={"status": "unavailable"}) as collect:
                    for layout in LAYOUT_IDS:
                        result = capture(runner, f"watch-{layout}", device, app, [0], 30, layout, geometry_probe=True)
                        self.assertEqual(result["status"], "captured")
                        self.assertEqual(result["screenshots"][0]["geometryProbe"]["status"], "unavailable")
                self.assertEqual([call.args[4] for call in collect.call_args_list], list(LAYOUT_IDS))

        def payload(self):
            phone, a, b = (f"00000000-0000-0000-0000-{n:012d}" for n in (1, 2, 3))
            ios, watch = "com.apple.CoreSimulator.SimRuntime.iOS-26-0", "com.apple.CoreSimulator.SimRuntime.watchOS-26-0"
            return phone, a, b, {"runtimes": [{"identifier": x, "isAvailable": True} for x in (ios, watch)],
                "devices": {ios: [{"udid": phone, "name": "iPhone", "isAvailable": True, "state": "Booted"}],
                            watch: [{"udid": x, "name": "Apple Watch", "isAvailable": True, "state": "Booted"} for x in (a, b)]},
                "pairs": {"pair": {"watch": {"udid": a}, "phone": {"udid": phone}}}}

        def test_pair_preference_and_no_unpair(self):
            phone, a, b, data = self.payload()
            self.assertEqual(select_watch(data, phone, "10.0")["udid"], a)
            self.assertFalse(can_pair(data, phone, b))
            self.assertEqual(select_watch(data, b, "10")["udid"], b)
            self.assertFalse(can_pair(data, b, b))
            self.assertTrue(can_pair(data, "00000000-0000-0000-0000-000000000004", b))

        def test_missing_runtime_and_unrecognized_pair_are_blocked(self):
            phone, _, _, data = self.payload()
            with self.assertRaises(CaptureError): select_watch(data, phone, "27")
            data["runtimes"][1]["isAvailable"] = False
            with self.assertRaises(CaptureError): select_watch(data, phone, "10")
            data["pairs"] = []
            with self.assertRaises(CaptureError): pair_members(data)

        def test_requested_size_wins_over_smaller_existing_pair(self):
            phone, a, b, data = self.payload()
            entries = list(data["devices"].values())[1]
            entries[0]["name"] = "Apple Watch Series 11 (42mm)"
            entries[1]["name"] = "Apple Watch Series 11 (46mm)"
            self.assertEqual(select_watch(data, phone, "10", "46")["udid"], b)
            self.assertEqual(select_watch(data, phone, "10", "42")["udid"], a)
            data["pairs"]["another"] = {"watch": {"udid": b}, "phone": {"udid": "00000000-0000-0000-0000-000000000004"}}
            with self.assertRaises(CaptureError): select_watch(data, phone, "10", "46")

        def test_creation_uses_only_installed_supported_size_and_runtime(self):
            _, _, _, data = self.payload()
            older = {"identifier": "watch10", "name": "Apple Watch Series 10 (46mm)",
                     "productFamily": "Apple Watch", "minRuntimeVersionString": "11"}
            newer = {"identifier": "watch11", "name": "Apple Watch Series 11 (46mm)",
                     "productFamily": "Apple Watch", "minRuntimeVersionString": "26"}
            unsupported = {"identifier": "watch12", "name": "Apple Watch Series 12 (46mm)",
                           "productFamily": "Apple Watch", "minRuntimeVersionString": "27"}
            data["devicetypes"] = [older, newer, unsupported]
            data["runtimes"][1]["supportedDeviceTypes"] = [older, newer]
            selected, runtime = watch_creation_spec(data, "10", "46")
            self.assertEqual(selected["identifier"], "watch11")
            self.assertTrue(runtime["identifier"].endswith("watchOS-26-0"))
            with self.assertRaises(CaptureError): watch_creation_spec(data, "10", "42")
            with self.assertRaises(CaptureError): watch_creation_spec(data, "27", "46")
            data["runtimes"][1]["isAvailable"] = False
            with self.assertRaises(CaptureError): watch_creation_spec(data, "10", "46")

        def test_series_12_46_wins_only_when_the_installed_runtime_supports_it(self):
            phone, a, b, data = self.payload()
            series11 = {"identifier": "watch11", "name": "Apple Watch Series 11 (46mm)",
                        "productFamily": "Apple Watch", "minRuntimeVersionString": "26"}
            series12 = {"identifier": "watch12", "name": "Apple Watch Series 12 (46mm)",
                        "productFamily": "Apple Watch", "minRuntimeVersionString": "26"}
            data["devicetypes"] = [series11, series12]
            data["runtimes"][1]["supportedDeviceTypes"] = [series11, series12]
            selected, _runtime = watch_creation_spec(data, "10", "46")
            self.assertEqual(selected["identifier"], "watch12")
            entries = list(data["devices"].values())[1]
            entries[0].update(name="Apple Watch Series 11 (46mm)", deviceTypeIdentifier="watch11")
            entries[1].update(name="Apple Watch Series 12 (46mm)", deviceTypeIdentifier="watch12")
            self.assertEqual(select_watch(data, phone, "10", "46")["udid"], b)
            data["runtimes"][1]["supportedDeviceTypes"] = [series11]
            series12["minRuntimeVersionString"] = "27"
            selected, _runtime = watch_creation_spec(data, "10", "46")
            self.assertEqual(selected["identifier"], "watch11")
            self.assertFalse(series12_46_rank(selected))

        def test_created_device_records_real_type_not_qa_display_name(self):
            phone, _, b, data = self.payload()
            data["devicetypes"] = [{"identifier": "watch11", "name": "Apple Watch Series 11 (46mm)",
                                    "productFamily": "Apple Watch", "modelIdentifier": "Watch7,18"}]
            created = list(data["devices"].values())[1][1]
            created.update(name="Patrick QA session", deviceTypeIdentifier="watch11")
            with tempfile.TemporaryDirectory() as temporary:
                runner = Runner(Path(temporary), {"commands": []})
                with patch.object(runner, "simctl", return_value=subprocess.CompletedProcess([], 0, b + "\n", "")) as command, \
                     patch.object(runner, "inventory", return_value=data):
                    item = create_qa_device(runner, data["devicetypes"][0], data["runtimes"][1], "watchOS", "10")
                self.assertEqual(command.call_args.args[0], "create")
                self.assertEqual(item["deviceTypeName"], "Apple Watch Series 11 (46mm)")
                self.assertEqual(item["modelIdentifier"], "Watch7,18")
                self.assertTrue(matches_watch_size(item, "46"))
                self.assertEqual(runner.report["createdSimulators"][0]["udid"], b)

        def test_created_qa_phone_is_recognized_by_type(self):
            phone, _, _, data = self.payload()
            data["devicetypes"] = [{"identifier": "phone17", "name": "iPhone 17 Pro",
                                    "productFamily": "iPhone", "modelIdentifier": "iPhone18,1"}]
            created = list(data["devices"].values())[0][0]
            created.update(name="Patrick QA iPhone 17 Pro session", deviceTypeIdentifier="phone17")
            with tempfile.TemporaryDirectory() as temporary:
                runner = Runner(Path(temporary), {"commands": []})
                with patch.object(runner, "simctl", return_value=subprocess.CompletedProcess([], 0, phone + "\n", "")), \
                     patch.object(runner, "inventory", return_value=data):
                    item = create_qa_device(runner, data["devicetypes"][0], data["runtimes"][0], "iOS", "17")
                self.assertEqual(item["udid"], phone)
                self.assertEqual(item["deviceTypeName"], "iPhone 17 Pro")
                self.assertEqual(item["modelIdentifier"], "iPhone18,1")

        def test_pairing_uses_new_phone_without_unpairing_original(self):
            phone, a, b, data = self.payload()
            phone_entry = list(data["devices"].values())[0][0]
            phone_entry["deviceTypeIdentifier"] = "iphone-type"
            data["devicetypes"] = [{"identifier": "iphone-type", "name": "iPhone Fixture", "productFamily": "iPhone"}]
            watch_entry = list(data["devices"].values())[1][1]
            watch_entry.update(name="Apple Watch Series 11 (46mm)", state="Shutdown")
            new_phone_id = "00000000-0000-0000-0000-000000000004"
            new_phone = {**phone_entry, "udid": new_phone_id, "name": "Patrick QA iPhone Fixture", "state": "Shutdown"}
            list(data["devices"].values())[0].append(new_phone)
            selected_phone = devices(data, "iOS")[0]
            selected_qa_phone = next(x for x in devices(data, "iOS") if x["udid"] == new_phone_id)
            with tempfile.TemporaryDirectory() as temporary:
                runner = Runner(Path(temporary), {"commands": []})
                args = argparse.Namespace(watch_size="46", boot_timeout=30, no_pairing=False, phone_app=Path("Phone.app"))
                with patch.object(runner, "inventory", return_value=data), \
                     patch.object(runner, "simctl", return_value=subprocess.CompletedProcess([], 0, "new-pair", "")) as command, \
                     patch(__name__ + ".capture", side_effect=[{"status": "failed"}, {"status": "captured"}]), \
                     patch(__name__ + ".create_qa_device", return_value=selected_qa_phone) as create, \
                     patch(__name__ + ".boot"):
                    result = capture_watch(runner, args, selected_phone, {"minimumOS": "10"}, [0])
                self.assertEqual(result["status"], "captured")
                self.assertEqual(result["pairingPhone"]["udid"], new_phone_id)
                create.assert_called_once()
                calls = [call.args for call in command.call_args_list]
                self.assertIn(("pair", b, new_phone_id), calls)
                self.assertFalse(any(call[0] in ("unpair", "delete", "erase") for call in calls))
                self.assertFalse(any(call[0] == "shutdown" and call[1] == phone for call in calls))

        def test_compiled_platform_is_required(self):
            with tempfile.TemporaryDirectory() as temporary:
                app = Path(temporary) / "Fixture.app"
                app.mkdir(); (app / "Fixture").write_bytes(b"fixture")
                info = {"CFBundleIdentifier": "example.fixture", "CFBundleExecutable": "Fixture", "CFBundleSupportedPlatforms": ["iPhoneOS"]}
                (app / "Info.plist").write_bytes(plistlib.dumps(info))
                with self.assertRaises(CaptureError): app_info(app, "iOS")
                info["CFBundleSupportedPlatforms"] = ["iPhoneSimulator"]
                (app / "Info.plist").write_bytes(plistlib.dumps(info))
                self.assertEqual(app_info(app, "iOS")["bundleID"], "example.fixture")

        def test_png_integrity(self):
            def chunk(kind, data):
                return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
            png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
            png += chunk(b"IDAT", zlib.compress(b"\0\0\0\0")) + chunk(b"IEND", b"")
            with tempfile.TemporaryDirectory() as temporary:
                path = Path(temporary) / "fixture.png"; path.write_bytes(png)
                self.assertEqual(png_info(path)["width"], 1)
                path.write_bytes(png[:-3])
                with self.assertRaises(CaptureError): png_info(path)

        def test_layout_override_uses_launch_argument_and_rejects_unknown_id(self):
            phone, _, _, data = self.payload()
            device = devices(data, "iOS")[0]
            app = {"path": "Phone.app", "bundleID": "example.fixture", "executable": "Fixture"}
            with tempfile.TemporaryDirectory() as temporary:
                runner = Runner(Path(temporary), {"commands": []})
                with patch(__name__ + ".boot"), patch(__name__ + ".png_info", return_value={"width": 1, "height": 1}), \
                     patch.object(runner, "simctl", return_value=subprocess.CompletedProcess([], 0, "example.fixture: 123\n", "")) as command, \
                     patch.object(runner, "command", return_value=subprocess.CompletedProcess([], 0, "123 Fixture", "")):
                    result = capture(runner, "phone-layout-activity", device, app, [0], 30, "activity")
                    self.assertEqual(result["status"], "captured")
                    self.assertEqual(result["requestedLayout"], "activity")
                    self.assertIn(("launch", "--terminate-running-process", phone, "example.fixture", "--patrick-preview-layout", "activity"),
                                  [call.args for call in command.call_args_list])
                    command.reset_mock()
                    invalid = capture(runner, "invalid", device, app, [0], 30, "not-a-layout")
                    self.assertEqual(invalid["status"], "failed")
                    command.assert_not_called()

        def test_launch_timeout_reboots_once_then_captures(self):
            phone, _, _, data = self.payload()
            device = devices(data, "iOS")[0]
            app = {"path": "Phone.app", "bundleID": "example.fixture", "executable": "Fixture"}
            ok = subprocess.CompletedProcess([], 0, "example.fixture: 123\n", "")
            timed_out = CaptureError("Command failed (124): xcrun simctl launch; Command timed out")
            with tempfile.TemporaryDirectory() as temporary:
                runner = Runner(Path(temporary), {"commands": []})
                with patch(__name__ + ".boot") as booted, patch(__name__ + ".png_info", return_value={"width": 1, "height": 1}), \
                     patch.object(runner, "simctl", side_effect=[ok, timed_out, ok, ok, ok, ok]) as command, \
                     patch.object(runner, "command", return_value=subprocess.CompletedProcess([], 0, "123 Fixture", "")):
                    result = capture(runner, "phone", device, app, [0], 30)
            self.assertEqual(result["status"], "captured")
            self.assertEqual(result["launchRetry"], "rebooted after simctl launch timed out")
            self.assertEqual(booted.call_count, 2)
            self.assertEqual([call.args[0] for call in command.call_args_list],
                             ["install", "launch", "shutdown", "install", "launch", "io"])
            self.assertEqual(command.call_args_list[2].kwargs["required"], False)

        def test_non_timeout_launch_failure_does_not_reboot(self):
            _, _, _, data = self.payload()
            device = devices(data, "iOS")[0]
            app = {"path": "Phone.app", "bundleID": "example.fixture", "executable": "Fixture"}
            ok = subprocess.CompletedProcess([], 0, "", "")
            failed = CaptureError("Command failed (1): xcrun simctl launch; bundle not found")
            with tempfile.TemporaryDirectory() as temporary:
                runner = Runner(Path(temporary), {"commands": []})
                with patch(__name__ + ".boot"), \
                     patch.object(runner, "simctl", side_effect=[ok, failed]) as command:
                    result = capture(runner, "phone", device, app, [0], 30)
            self.assertEqual(result["status"], "failed")
            self.assertNotIn("launchRetry", result)
            self.assertEqual([call.args[0] for call in command.call_args_list], ["install", "launch"])

        def test_watch_failure_preserves_phone_capture_and_returns_partial(self):
            phone, _, _, data = self.payload()
            phone_info = {"minimumOS": "17", "bundleID": "example.fixture"}
            with tempfile.TemporaryDirectory() as temporary:
                args = argparse.Namespace(output=Path(temporary), phone_app=Path("Phone.app"),
                    watch_app=Path("MissingWatch.app"), phone_udid=phone, delays=[0], boot_timeout=30)
                with patch.object(sys, "platform", "darwin"), patch.object(shutil, "which", return_value="/usr/bin/xcrun"), \
                     patch.object(Runner, "command", return_value=subprocess.CompletedProcess([], 0, "", "")), \
                     patch.object(Runner, "inventory", return_value=data), \
                     patch(__name__ + ".app_info", side_effect=[phone_info, CaptureError("Missing watch fixture")]), \
                     patch(__name__ + ".capture", return_value={"status": "captured", "screenshots": ["fixture-only"]}) as captured:
                    self.assertEqual(run(args), 2)
                saved = json.loads(next(Path(temporary).glob("run-*/report.json")).read_text(encoding="utf-8"))
                self.assertEqual(captured.call_count, 1)
                self.assertEqual(saved["status"], "partial")
                self.assertEqual(saved["phone"]["status"], "captured")
                self.assertEqual(saved["watch"]["status"], "blocked")
                self.assertEqual(saved["visualReview"], "pending")

    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(Fixtures))
    return 0 if result.wasSuccessful() else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--phone-app", type=Path)
    parser.add_argument("--watch-app", type=Path)
    parser.add_argument("--phone-udid")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--delays", default="3,8", help="Seconds after each successful app launch, comma separated (default: 3,8)")
    parser.add_argument("--boot-timeout", type=float, default=240)
    parser.add_argument("--watch-size", choices=("46", "42", "any"), default="46",
                        help="Required Watch case size; no silent fallback to another size (default: 46)")
    parser.add_argument("--no-pairing", action="store_true", help="Never create even a new simulator-only pair")
    parser.add_argument("--layouts", nargs="+", choices=LAYOUT_IDS, default=[],
                        help="Also launch each simulator-only layout override and capture its real screen")
    parser.add_argument("--watch-geometry", action="store_true",
                        help="Read the Debug simulator Watch geometry probe after every Watch screenshot/layout; missing evidence is reported")
    parser.add_argument("--self-test", action="store_true", help="Run local pure fixtures, without Xcode or simulators")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if not all((args.phone_app, args.watch_app, args.phone_udid, args.output)):
        parser.error("--phone-app, --watch-app, --phone-udid and --output are required")
    if not UUID.fullmatch(args.phone_udid):
        parser.error("--phone-udid must be an explicit simulator UUID (not 'booted')")
    try:
        args.delays = sorted(set(float(value) for value in args.delays.split(",")))
        if not args.delays or not all(0 <= value <= 60 for value in args.delays): raise ValueError()
        if not 30 <= args.boot_timeout <= 600: raise ValueError()
    except ValueError:
        parser.error("delays must be 0..60 seconds; boot-timeout must be 30..600 seconds")
    return run(args)


if __name__ == "__main__":
    raise SystemExit(main())
