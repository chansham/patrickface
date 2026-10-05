#!/usr/bin/env python3
"""Capture already-built iPhone/watchOS apps on installed Apple simulators.

Example (after build_apple_simulators.sh has built both products):
  python3 tools/capture_apple_simulators.py \
    --phone-app /tmp/build/phone/Build/Products/Debug-iphonesimulator/PatrickCompanion.app \
    --watch-app /tmp/build/watch/Build/Products/Debug-watchsimulator/PatrickFace.app \
    --phone-udid "$IOS_TEST_DEVICE_ID" --output /tmp/patrick-ci-logs/native-screens

No build, download, signing, real-device operation, erase or unpair is performed.
An existing watch paired with the supplied phone is preferred. Otherwise an
available, unpaired watch is tried directly. If that fails, only two unpaired
simulators may be shut down temporarily and paired; --no-pairing disables this.
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


class CaptureError(RuntimeError):
    pass


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def version(value: str) -> tuple[int, ...]:
    parts = tuple(int(x) for x in re.findall(r"\d+", value))
    return (parts + (0, 0, 0))[:3]


def devices(payload: dict, platform: str, minimum: str = "0") -> list[dict]:
    runtimes = {x["identifier"]: x for x in payload.get("runtimes", [])}
    result = []
    for runtime_id, entries in payload.get("devices", {}).items():
        match = re.fullmatch(r"com\.apple\.CoreSimulator\.SimRuntime\." + platform + r"-(\d+(?:-\d+)*)", runtime_id)
        runtime = runtimes.get(runtime_id, {})
        if not match or runtime.get("isAvailable") is not True or version(match[1]) < version(minimum):
            continue
        for entry in entries:
            if entry.get("isAvailable") is not True or not UUID.fullmatch(str(entry.get("udid", ""))):
                continue
            if platform == "iOS" and not entry.get("name", "").startswith("iPhone"):
                continue
            result.append({**entry, "runtime": runtime_id, "runtimeVersion": match[1]})
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


def select_watch(payload: dict, phone_id: str, minimum: str) -> dict:
    pairs = pair_members(payload)
    target = phone_id.upper()
    candidates = []
    for item in devices(payload, "watchOS", minimum):
        watch = item["udid"].upper()
        partners = [phone for _, paired_watch, phone in pairs if paired_watch == watch]
        # Do not borrow a watch belonging to another simulator phone.
        if any(phone != target for phone in partners):
            continue
        # Prefer the user's 46 mm target when it does not disturb an existing pair.
        key = (target in partners, "46mm" in item.get("name", "").replace(" ", ""),
               item.get("state") == "Booted", version(item["runtimeVersion"]), item.get("name", ""), watch)
        candidates.append((key, item))
    if not candidates:
        raise CaptureError("No available installed watchOS simulator meets the app minimum OS and safe-pairing constraints; no runtime was downloaded")
    return max(candidates, key=lambda candidate: candidate[0])[1]


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


def capture(runner: Runner, label: str, device: dict, app: dict, delays: list[float], boot_timeout: float) -> dict:
    result = {"device": device, "app": app, "status": "failed", "screenshots": [],
              "visualReview": "pending", "startedAt": utc_now()}
    try:
        boot(runner, device, boot_timeout)
        runner.simctl("install", device["udid"], app["path"], timeout=120)
        launch = runner.simctl("launch", "--terminate-running-process", device["udid"], app["bundleID"], timeout=90)
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
            result["screenshots"].append({"path": filename, "elapsedSeconds": round(time.monotonic() - launched, 3),
                                          "capturedAt": utc_now(), **png_info(path)})
        result["status"] = "captured"
    except (CaptureError, OSError) as error:
        result["error"] = str(error)
    result["finishedAt"] = utc_now()
    return result


def capture_watch(runner: Runner, args, phone: dict, app: dict, delays: list[float]) -> dict:
    result = {"status": "blocked", "visualReview": "pending", "attempts": [], "pairing": "not-needed"}
    try:
        inventory = runner.inventory("devices-before-watch.json")
        watch = select_watch(inventory, phone["udid"], app["minimumOS"])
        result["device"] = watch
        first = capture(runner, "watch", watch, app, delays, args.boot_timeout)
        result["attempts"].append(first)
        if first["status"] == "captured":
            result["status"] = "captured"
            return result
        if args.no_pairing:
            raise CaptureError("Watch direct launch/capture failed and simulator pairing was disabled")
        inventory = runner.inventory("devices-before-pair.json")
        if not can_pair(inventory, phone["udid"], watch["udid"]):
            raise CaptureError("Watch direct launch/capture failed; an existing pair prevents a safe new pairing. No existing pair was removed")
        result["pairing"] = "attempted-with-two-unpaired-simulators"
        # Only the explicit test phone and the selected unpaired watch are touched.
        # simctl is authoritative about platform compatibility; failure is reported.
        for item in (watch, phone):
            current = next((d for values in inventory.get("devices", {}).values() for d in values
                            if d.get("udid", "").upper() == item["udid"].upper()), None)
            if current and current.get("state") != "Shutdown":
                runner.simctl("shutdown", item["udid"], timeout=60)
        try:
            paired = runner.simctl("pair", watch["udid"], phone["udid"], timeout=120)
            result["pairing"] = "created"
            result["pairOutput"] = paired.stdout.strip()
        finally:
            # Return the explicit test phone to its booted state even if pairing fails.
            boot(runner, phone, args.boot_timeout)
        second = capture(runner, "watch-paired", watch, app, delays, args.boot_timeout)
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
    report = {"schemaVersion": 1, "startedAt": utc_now(), "status": "failed", "visualReview": "pending",
              "captureIsNotVisualApproval": True, "commands": [],
              "phone": {"status": "blocked"}, "watch": {"status": "blocked"},
              "limitations": ["PNG capture and process liveness do not prove foreground UI or correct artwork. Inspect every PNG.",
                              "No real device, WatchConnectivity correctness, signing or installation eligibility is tested."]}
    runner = Runner(output, report)
    try:
        if sys.platform != "darwin" or not shutil.which("xcrun"):
            raise CaptureError("Capture requires macOS and an existing Xcode installation; no runtime or tool will be downloaded")
        phone_app = app_info(args.phone_app.expanduser().resolve(), "iOS")
        runner.command(["xcodebuild", "-version"])
        for topic in ((), ("bootstatus",), ("launch",), ("pair",), ("io",)):
            runner.simctl("help", *topic, required=False)
        inventory = runner.inventory("devices-initial.json")
        eligible = devices(inventory, "iOS", phone_app["minimumOS"])
        phone = next((d for d in eligible if d["udid"].upper() == args.phone_udid.upper()), None)
        if phone is None:
            raise CaptureError("The supplied phone UDID is not an available installed iPhone simulator compatible with this build")
        report["phone"] = capture(runner, "phone", phone, phone_app, args.delays, args.boot_timeout)
        # A broken/missing watch product must not prevent the iPhone capture above.
        try:
            watch_app = app_info(args.watch_app.expanduser().resolve(), "watchOS")
            report["watch"] = capture_watch(runner, args, phone, watch_app, args.delays)
        except (CaptureError, OSError) as error:
            report["watch"]["error"] = str(error)
        runner.inventory("devices-final.json")
    except (CaptureError, OSError, ValueError) as error:
        report["error"] = str(error)
    finally:
        count = sum(report[key].get("status") == "captured" for key in ("phone", "watch"))
        report["status"] = "captured" if count == 2 and "error" not in report else "partial" if count else "failed"
        report["finishedAt"] = utc_now()
        (output / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"Native capture: {report['status']}; visual review: pending; report: {output / 'report.json'}", flush=True)
    return 0 if report["status"] == "captured" else 2 if report["status"] == "partial" else 1


def self_test() -> int:
    """Pure fixtures only: these are not simulator or native UI test results."""
    import tempfile
    import unittest
    from unittest.mock import patch

    class Fixtures(unittest.TestCase):
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
    parser.add_argument("--no-pairing", action="store_true", help="Never create even a new simulator-only pair")
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
