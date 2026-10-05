#!/usr/bin/env python3
"""Select an installed iPhone accepted by this Xcode scheme; never install one."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys


UUID = r"[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}"


def eligible_ids(destinations: str) -> set[str]:
    """Only the available section counts; ineligible devices can also have IDs."""
    available = False
    result: set[str] = set()
    for line in destinations.splitlines():
        if "Available destinations for" in line:
            available = True
        elif "Ineligible destinations for" in line:
            available = False
        elif available and re.search(r"platform:\s*iOS Simulator\s*,", line):
            match = re.search(r"\bid:\s*(" + UUID + r")\s*[,}]", line)
            if match:
                result.add(match.group(1).upper())
    return result


def select_device(payload: dict, destinations: str) -> tuple[str, str, str]:
    accepted = eligible_ids(destinations)
    candidates = []
    for runtime, devices in payload.get("devices", {}).items():
        version = re.fullmatch(r"com\.apple\.CoreSimulator\.SimRuntime\.iOS-(\d+(?:-\d+)*)", runtime)
        if not version:
            continue
        version_parts = tuple(int(part) for part in version.group(1).split("-"))
        for device in devices:
            identifier = device.get("udid", "")
            name = device.get("name", "")
            if (device.get("isAvailable") is True and name.startswith("iPhone")
                    and isinstance(identifier, str) and identifier.upper() in accepted):
                # Prefer an already booted phone, then the newest numeric runtime.
                key = (device.get("state") == "Booted", version_parts, name, identifier)
                candidates.append((key, identifier, name, runtime))
    if not candidates:
        raise ValueError("No installed, available iPhone simulator is accepted by PatrickCompanion. "
                         "Check the selected Xcode and installed runtimes. No runtime was downloaded.")
    _, identifier, name, runtime = max(candidates)
    return identifier, name, runtime


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--devices", required=True, type=Path)
    parser.add_argument("--destinations", required=True, type=Path)
    args = parser.parse_args()
    try:
        identifier, name, runtime = select_device(
            json.loads(args.devices.read_text(encoding="utf-8")),
            args.destinations.read_text(encoding="utf-8"),
        )
    except (ValueError, OSError, TypeError) as error:
        print(f"XCTest destination unavailable: {error}", file=sys.stderr)
        return 1
    print(f"XCTest destination: {name} ({runtime})", file=sys.stderr)
    print(identifier)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
