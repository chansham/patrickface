#!/usr/bin/env python3
"""SHA-verified byte copies of local experience resources; no image rewriting.

--check is read-only. Unknown destination files and local edits are preserved.
Source JSON/PNG/WAV files are included recursively; documentation is excluded.
"""
from __future__ import annotations

import argparse
from datetime import date
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
from PIL import Image
from sync_animation_bundle import atomic_copy_bytes, confined_path, digest, relative_parts
from validate_experience_audio import validate as validate_audio
from validate_experience_clock import validate as validate_clock

ROOT = Path(__file__).resolve().parents[1]
TOOL = "tools/sync_experience_bundle.py"
MANAGED = "managed-assets.json"
TARGETS = {"watch": "PatrickFace/Experience", "iphone": "iOSCompanion/PatrickCompanion/Experience"}


def roots(project_root: Path, target: str) -> tuple[Path, Path]:
    if target not in TARGETS:
        raise ValueError(f"Unknown bundle target: {target}")
    source, destination = project_root / "experience", project_root / TARGETS[target]
    for path in (source, destination):
        if path.resolve() != path or not path.is_relative_to(project_root):
            raise ValueError(f"Bundle directory is redirected: {path}")
        if path.exists() and not path.is_dir():
            raise ValueError(f"Bundle directory is not a folder: {path}")
    return source, destination


def source_files(project_root: Path, source: Path) -> tuple[dict, list]:
    files, objects, warnings = {}, {}, []
    for path in sorted(source.rglob("*")):
        # Inspect directories too: a symlink/junction must never redirect traversal.
        if path.resolve() != path or not path.is_relative_to(source):
            raise ValueError(f"Redirected source is prohibited: {path}")
        if path.is_dir():
            continue
        if not path.is_file():
            raise ValueError(f"Source is not a regular file: {path}")
        name = path.relative_to(source).as_posix()
        confined_path(source, name)
        if path.suffix.lower() == ".md":
            continue
        if path.suffix.lower() not in {".json", ".png", ".wav"} or name == MANAGED:
            raise ValueError(f"Unexpected experience resource: {name}")
        payload = path.read_bytes()
        files[name] = payload
        if path.suffix.lower() == ".json":
            objects[name] = json.loads(payload.decode("utf-8-sig"))
        elif path.suffix.lower() == ".png":
            with Image.open(path) as image:
                if image.format != "PNG":
                    raise ValueError(f"Resource extension does not match PNG content: {name}")
                image.verify()
    contract = objects.get("contract.json")
    if not isinstance(contract, dict) or contract.get("schemaVersion") != 1:
        raise ValueError("A schemaVersion 1 experience/contract.json is required.")
    required_paths = ["themesPath", "soundsPath", "clockPath"]
    if "calendarPath" in contract:
        required_paths.append("calendarPath")
    for key in required_paths:
        path = contract.get(key)
        parts = relative_parts(path)
        if parts[0] != "experience":
            raise ValueError(f"{key} must remain inside experience/.")
        name = "/".join(parts[1:])
        if name not in files:
            if key == "clockPath" and contract.get("clockContract", {}).get("status") == "awaiting-generated-art":
                warnings.append("Clock drawing is unavailable; only digital time is usable.")
            else:
                raise ValueError(f"Required source resource is missing: {path}")
    audio = validate_audio(project_root)
    if audio["errors"]:
        raise ValueError("Audio validation failed: " + "; ".join(audio["errors"]))
    if "clock/manifest.json" in files:
        clock = validate_clock(project_root)
        warnings.extend(clock["warnings"])
    if "calendarPath" in contract:
        calendar_name = "/".join(relative_parts(contract["calendarPath"])[1:])
        calendar = objects[calendar_name]
        if calendar.get("schemaVersion") != 1 or not isinstance(calendar.get("holidays"), dict):
            raise ValueError("Calendar schema or holidays map is invalid.")
        for key, holiday in calendar["holidays"].items():
            if date.fromisoformat(key).year not in calendar.get("years", []):
                raise ValueError(f"Calendar date outside declared source years: {key}")
            if set(holiday) != {"id", "name", "motif"}:
                raise ValueError(f"Invalid calendar entry: {key}")
        origin = calendar.get("source", {})
        if origin.get("path") != "preview/holiday-calendar.js":
            raise ValueError("Calendar must identify its existing web data source.")
        if digest(confined_path(project_root, origin["path"]).read_bytes()) != origin.get("sha256"):
            raise ValueError("Native calendar is stale; rerun export_experience_calendar.py.")
        annual = calendar.get("annualHolidays")
        annual_origin = calendar.get("annualSource", {})
        if not isinstance(annual, dict) or annual_origin.get("path") != "preview/pet-core.js":
            raise ValueError("Annual holidays must identify the exact existing pet-core source.")
        for key, holiday in annual.items():
            date.fromisoformat(f"2000-{key}")
            if set(holiday) != {"id", "name", "motif"}:
                raise ValueError(f"Invalid fixed-date holiday: {key}")
        if digest(confined_path(project_root, annual_origin["path"]).read_bytes()) != annual_origin.get("sha256"):
            raise ValueError("Annual calendar is stale; rerun export_experience_calendar.py.")
    # A copied wardrobe must not refer to animations absent from the main bundle.
    theme_name = "/".join(relative_parts(contract["themesPath"])[1:])
    themes = objects.get(theme_name)
    if not isinstance(themes, dict) or not isinstance(themes.get("outfits"), list):
        raise ValueError("Themes require an outfits list.")
    catalog_path = project_root / "animation/catalog.json"
    if catalog_path.resolve() != catalog_path:
        raise ValueError("Animation catalog must not redirect.")
    catalog = json.loads(catalog_path.read_text(encoding="utf-8-sig"))
    clip_ids = {clip["id"] for clip in catalog["clips"] if clip.get("atlas")}
    outfits = themes["outfits"]
    outfit_ids = [outfit.get("id") for outfit in outfits]
    if any(not isinstance(name, str) or not name for name in outfit_ids) or len(set(outfit_ids)) != len(outfit_ids):
        raise ValueError("Outfit IDs must be unique non-empty strings.")
    for outfit in outfits:
        refs = [outfit.get("clipId")]
        for action in outfit.get("actions", {}).values():
            refs.extend(action if isinstance(action, list) else [action])
        if any(not isinstance(ref, str) or ref not in clip_ids for ref in refs):
            raise ValueError(f"Outfit references an unavailable main animation: {outfit['id']}")
    for defaults_key in ("defaultSceneOutfits", "defaultActionOutfits"):
        if any(value not in outfit_ids for value in themes.get(defaults_key, {}).values()):
            raise ValueError(f"{defaults_key} references an unavailable outfit.")

    def verify_references(value: object) -> None:
        if isinstance(value, dict):
            ref, sha = value.get("path"), value.get("sha256")
            if isinstance(ref, str) and ref.startswith("experience/"):
                parts = relative_parts(ref)
                relative = "/".join(parts[1:])
                confined_path(source, relative)
                if relative not in files:
                    raise ValueError(f"Missing manifest reference: {ref}")
                if sha is not None and digest(files[relative]) != sha:
                    raise ValueError(f"Manifest SHA mismatch: {ref}")
            for child in value.values():
                verify_references(child)
        elif isinstance(value, list):
            for child in value:
                verify_references(child)
    for value in objects.values():
        verify_references(value)
    return files, warnings


def read_previous(path: Path, destination: Path) -> dict:
    if not path.exists():
        return {}
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    if data.get("schemaVersion") != 1 or data.get("tool") != TOOL:
        raise ValueError("Refusing to overwrite an unknown managed manifest.")
    previous = {}
    for record in data.get("files", []):
        name, source, sha = record.get("destination"), record.get("source"), record.get("sha256")
        confined_path(destination, name)
        source_parts = relative_parts(source)
        if (name == MANAGED or name.casefold() in {item.casefold() for item in previous}
                or source_parts[0] != "experience" or not isinstance(sha, str) or len(sha) != 64
                or any(letter not in "0123456789abcdef" for letter in sha)):
            raise ValueError("Invalid managed resource record.")
        previous[name] = record
    return previous


def synchronize(project_root: Path = ROOT, check: bool = False, target: str = "watch") -> dict:
    project_root = project_root.resolve()
    source, destination = roots(project_root, target)
    files, warnings = source_files(project_root, source)
    manifest_path = confined_path(destination, MANAGED)
    before_manifest = manifest_path.read_bytes() if manifest_path.exists() else None
    old = read_previous(manifest_path, destination)
    expected, outdated = {}, []
    for name, payload in files.items():
        path = confined_path(destination, name)
        record = {"source": f"experience/{name}", "destination": name,
                  "sha256": digest(payload), "bytes": len(payload), "active": True}
        if any(name.casefold() == other.casefold() for other in expected):
            raise ValueError(f"Case-insensitive resource collision: {name}")
        expected[name] = record
        if path.exists():
            if not path.is_file():
                raise ValueError(f"Destination is not a regular file: {path}")
            current = digest(path.read_bytes())
            if current != record["sha256"]:
                if name not in old:
                    raise ValueError(f"Conflicting unmanaged resource: {name}")
                if current != old[name]["sha256"]:
                    raise ValueError(f"Managed resource has local edits: {name}")
                outdated.append(name)
        else:
            outdated.append(name)
    retained = [name for name in old if name not in expected]
    records = list(expected.values()) + [{**old[name], "active": False} for name in retained]
    managed = {"schemaVersion": 1, "tool": TOOL,
               "files": sorted(records, key=lambda record: record["destination"])}
    manifest_bytes = (json.dumps(managed, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    if before_manifest != manifest_bytes:
        outdated.append(MANAGED)
    result = {"status": "OUT_OF_DATE" if outdated else "UP_TO_DATE", "target": target,
              "destination": TARGETS[target], "checkOnly": check, "fileCount": len(files),
              "outdated": outdated, "copied": [], "retainedPreviouslyManaged": retained,
              "warnings": warnings, "artApproval": "not-assessed", "nativeBuild": "not-run"}
    if check or not outdated:
        return result
    # Prevent a changed source or destination manifest from invalidating preflight.
    for name, payload in files.items():
        if confined_path(source, name).read_bytes() != payload:
            raise ValueError(f"Source changed after preflight: {name}")
    if (manifest_path.read_bytes() if manifest_path.exists() else None) != before_manifest:
        raise ValueError("Managed manifest changed after preflight.")
    destination.mkdir(parents=True, exist_ok=True)
    roots(project_root, target)
    # Resource bytes precede manifests so their dependencies already exist.
    for name in sorted(files, key=lambda name: (name.endswith(".json"), name)):
        if name not in outdated:
            continue
        path = confined_path(destination, name)
        if path.exists():
            current = digest(path.read_bytes())
            if current != expected[name]["sha256"] and (name not in old or current != old[name]["sha256"]):
                raise ValueError(f"Destination changed after preflight: {name}")
        atomic_copy_bytes(path, files[name], expected[name]["sha256"], destination)
        result["copied"].append(name)
    if MANAGED in outdated:
        atomic_copy_bytes(manifest_path, manifest_bytes, digest(manifest_bytes), destination)
        result["copied"].append(MANAGED)
    for name, record in expected.items():
        if digest(confined_path(destination, name).read_bytes()) != record["sha256"]:
            raise ValueError(f"Final destination SHA mismatch: {name}")
    result.update(status="SYNCED", outdated=[])
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--target", choices=("watch", "iphone", "all"), default="watch")
    args = parser.parse_args()
    try:
        targets = list(TARGETS) if args.target == "all" else [args.target]
        for target in targets:
            synchronize(check=True, target=target)
        reports = [synchronize(check=args.check, target=target) for target in targets]
        result = {"status": "OUT_OF_DATE" if any(report["status"] == "OUT_OF_DATE" for report in reports)
                  else "UP_TO_DATE" if all(report["status"] == "UP_TO_DATE" for report in reports) else "SYNCED",
                  "targets": reports}
    except (OSError, ValueError, TypeError, KeyError) as error:
        result = {"status": "ERROR", "message": str(error), "checkOnly": args.check}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 1 if result["status"] in {"ERROR", "OUT_OF_DATE"} else 0


if __name__ == "__main__":
    raise SystemExit(main())
