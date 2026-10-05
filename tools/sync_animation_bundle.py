"""Byte-copy validated animation assets into the native bundle; --check is read-only.

Only ROOT/animation is a source; Watch/iPhone Animation bundle folders are targets.
Unknown files are never removed. Conflicting unmanaged or locally edited files
stop the entire preflight before any copying. This does not compile the app.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import sys
import tempfile

sys.dont_write_bytecode = True
from validate_animation_catalog import ROOT, validate_catalog

TOOL = "tools/sync_animation_bundle.py"
MANAGED = "managed-assets.json"
TARGETS = {"watch": "PatrickFace/Animation", "iphone": "iOSCompanion/PatrickCompanion/Animation"}


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def relative_parts(value: object) -> tuple[str, ...]:
    if not isinstance(value, str) or not value or "\\" in value or ":" in value:
        raise ValueError(f"Unsafe relative path: {value!r}")
    parts = value.split("/")
    if any(part in ("", ".", "..") for part in parts) or PurePosixPath(value).is_absolute():
        raise ValueError(f"Unsafe relative path: {value!r}")
    return tuple(parts)


def confined_path(base: Path, relative: str) -> Path:
    """Reject redirects as well as traversal, including Windows junction escapes."""
    parts = relative_parts(relative)
    candidate = base.joinpath(*parts)
    resolved = candidate.resolve()
    if resolved != candidate or not resolved.is_relative_to(base):
        raise ValueError(f"Path is redirected or outside its allowed directory: {candidate}")
    return candidate


def roots(project_root: Path, target: str = "watch") -> tuple[Path, Path]:
    project_root = project_root.resolve()
    source = project_root / "animation"
    if target not in TARGETS:
        raise ValueError(f"Unknown bundle target: {target}")
    destination = project_root / TARGETS[target]
    for path in (source, destination):
        if path.resolve() != path or not path.resolve().is_relative_to(project_root):
            raise ValueError(f"Allowed directory must not be redirected: {path}")
        if path.exists() and not path.is_dir():
            raise ValueError(f"Allowed directory is not a folder: {path}")
    return source, destination


def read_managed(path: Path) -> dict:
    if not path.exists():
        return {}
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(data, dict) or data.get("tool") != TOOL or data.get("schemaVersion") != 1:
        raise ValueError(f"Existing {MANAGED} is not this tool's manifest; refusing to overwrite.")
    records = data.get("files")
    if not isinstance(records, list):
        raise ValueError("Managed manifest has an invalid files list.")
    result = {}
    for record in records:
        if not isinstance(record, dict):
            raise ValueError("Managed manifest contains a non-object record.")
        relative_parts(record.get("destination"))
        source_parts = relative_parts(record.get("source"))
        sha = record.get("sha256")
        if source_parts[0] != "animation" or not isinstance(sha, str) or len(sha) != 64 or any(c not in "0123456789abcdef" for c in sha):
            raise ValueError("Managed manifest contains an invalid source or SHA.")
        name = record["destination"]
        if name.casefold() in {key.casefold() for key in result} or name == MANAGED:
            raise ValueError("Managed manifest contains duplicate/reserved destinations.")
        result[name] = record
    return result


def atomic_copy_bytes(path: Path, payload: bytes, expected_sha: str, destination: Path) -> None:
    """Write only an owned temporary file, then atomically replace a preflighted target."""
    confined_path(destination, path.relative_to(destination).as_posix())
    path.parent.mkdir(parents=True, exist_ok=True)
    confined_path(destination, path.relative_to(destination).as_posix())
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(prefix=".animation-sync-", suffix=".tmp", dir=path.parent, delete=False) as handle:
            temporary = Path(handle.name)
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        if digest(temporary.read_bytes()) != expected_sha:
            raise ValueError(f"Temporary copy failed hash check: {path}")
        confined_path(destination, path.relative_to(destination).as_posix())
        os.replace(temporary, path)
        temporary = None
        if digest(path.read_bytes()) != expected_sha:
            raise ValueError(f"Destination failed hash check: {path}")
    finally:
        if temporary is not None and temporary.exists():
            confined_path(destination, temporary.relative_to(destination).as_posix())
            temporary.unlink()  # Only this invocation's known temporary file.


def synchronize(project_root: Path = ROOT, check: bool = False, target: str = "watch") -> dict:
    project_root = project_root.resolve()
    source, destination = roots(project_root, target)
    catalog_path = confined_path(source, "catalog.json")
    catalog_bytes = catalog_path.read_bytes()
    catalog = json.loads(catalog_bytes.decode("utf-8-sig"))
    # Constrain sources before the validator opens any image bytes.
    if isinstance(catalog, dict) and isinstance(catalog.get("clips"), list):
        for clip in catalog["clips"]:
            if isinstance(clip, dict) and clip.get("atlas"):
                parts = relative_parts(clip["atlas"])
                if len(parts) < 2 or parts[0] != "animation":
                    raise ValueError(f"Atlas source must be inside ROOT/animation: {clip['atlas']}")
                confined_path(source, "/".join(parts[1:]))
                if clip.get("frameRegions"):
                    parts = relative_parts(clip["frameRegions"].get("path"))
                    if len(parts) < 2 or parts[0] != "animation":
                        raise ValueError("Contour metadata source must be inside ROOT/animation")
                    confined_path(source, "/".join(parts[1:]))
    validation = validate_catalog(catalog, project_root)
    if validation["errors"]:
        details = "; ".join(f"{item['code']}: {item['message']}" for item in validation["errors"])
        raise ValueError(f"Catalog validation failed; nothing copied: {details}")
    manifest_path = confined_path(destination, MANAGED)
    previous_manifest_bytes = manifest_path.read_bytes() if manifest_path.exists() else None
    old = read_managed(manifest_path)
    expected = {}

    def add(source_name: str, destination_name: str, payload: bytes) -> None:
        target = confined_path(destination, destination_name)
        if destination_name == MANAGED:
            raise ValueError("An atlas collides with the managed manifest filename.")
        folded = destination_name.casefold()
        if any(name.casefold() == folded and name != destination_name for name in expected):
            raise ValueError("Case-insensitive destination collision.")
        record = {"source": source_name, "destination": destination_name, "sha256": digest(payload),
                  "bytes": len(payload), "active": True}
        if destination_name in expected and expected[destination_name]["record"] != record:
            raise ValueError(f"Multiple different sources target {destination_name}.")
        expected[destination_name] = {"record": record, "payload": payload, "path": target}

    available = []
    for clip in catalog["clips"]:
        if not clip.get("atlas"):
            continue  # Planned/blocked metadata is retained in the byte-identical catalog.
        parts = relative_parts(clip["atlas"])
        if len(parts) < 2 or parts[0] != "animation":
            raise ValueError(f"Atlas source must be inside ROOT/animation: {clip['atlas']}")
        source_relative = "/".join(parts[1:])
        atlas_path = confined_path(source, source_relative)
        atlas_bytes = atlas_path.read_bytes()
        if digest(atlas_bytes) != clip["sha256"].lower():
            raise ValueError(f"Source changed after validation: {clip['atlas']}")
        add(clip["atlas"], source_relative, atlas_bytes)
        if clip.get("frameRegions"):
            regions = clip["frameRegions"]
            region_parts = relative_parts(regions["path"])
            region_relative = "/".join(region_parts[1:])
            region_bytes = confined_path(source, region_relative).read_bytes()
            if digest(region_bytes) != regions["sha256"]:
                raise ValueError(f"Contour metadata changed after validation: {regions['path']}")
            add(regions["path"], region_relative, region_bytes)
        available.append(clip["id"])
    add("animation/catalog.json", "catalog.json", catalog_bytes)

    outdated = []
    for name, entry in expected.items():
        path, record = entry["path"], entry["record"]
        if path.exists():
            if not path.is_file():
                raise ValueError(f"Target is not a regular file: {path}")
            current_sha = digest(path.read_bytes())
            if current_sha != record["sha256"]:
                if name not in old:
                    raise ValueError(f"Conflicting unmanaged file; refusing to overwrite: {path}")
                if current_sha != old[name]["sha256"]:
                    raise ValueError(f"Managed file has local edits; refusing to overwrite: {path}")
                outdated.append(name)
        else:
            outdated.append(name)

    # Keep previous managed records and files. No cleanup or deletion is implicit.
    retained = []
    records = [entry["record"] for entry in expected.values()]
    for name, record in old.items():
        confined_path(destination, name)
        if name not in expected:
            records.append({**record, "active": False})
            retained.append(name)
    managed = {"schemaVersion": 1, "tool": TOOL, "catalogSource": "animation/catalog.json",
               "catalogSha256": digest(catalog_bytes), "availableClipIds": available,
               "plannedClipIds": catalog.get("plannedClips", []),
               "files": sorted(records, key=lambda item: item["destination"])}
    manifest_bytes = (json.dumps(managed, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    if not manifest_path.exists() or manifest_path.read_bytes() != manifest_bytes:
        outdated.append(MANAGED)
    result = {"status": "OUT_OF_DATE" if outdated else "UP_TO_DATE", "checkOnly": check,
              "availableClipIds": available, "plannedClipIds": catalog.get("plannedClips", []),
              "fileCount": len(expected), "outdated": outdated, "copied": [],
              "retainedPreviouslyManaged": retained, "validationWarnings": validation["warnings"],
              "artApproval": "not-assessed", "nativeBuild": "not-run", "target": target,
              "destination": TARGETS[target]}
    if check or not outdated:
        return result
    if catalog_path.read_bytes() != catalog_bytes:
        raise ValueError("Catalog changed during preflight; retry before syncing.")
    if (manifest_path.read_bytes() if manifest_path.exists() else None) != previous_manifest_bytes:
        raise ValueError("Managed manifest changed during preflight; retry before syncing.")
    destination.mkdir(parents=True, exist_ok=True)
    roots(project_root, target)
    # Atlas copies first; update the catalog only once its referenced bytes exist.
    for name in sorted(expected, key=lambda value: value == "catalog.json"):
        if name not in outdated:
            continue
        entry = expected[name]
        if entry["path"].exists():
            current_sha = digest(entry["path"].read_bytes())
            if current_sha != entry["record"]["sha256"] and (name not in old or current_sha != old[name]["sha256"]):
                raise ValueError(f"Target changed after preflight; refusing to overwrite: {entry['path']}")
        atomic_copy_bytes(entry["path"], entry["payload"], entry["record"]["sha256"], destination)
        result["copied"].append(name)
    if MANAGED in outdated:
        atomic_copy_bytes(manifest_path, manifest_bytes, digest(manifest_bytes), destination)
        result["copied"].append(MANAGED)
    for entry in expected.values():
        if digest(entry["path"].read_bytes()) != entry["record"]["sha256"]:
            raise ValueError(f"Final byte verification failed: {entry['path']}")
    result["status"] = "SYNCED"
    result["outdated"] = []
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Check freshness without making directories or writing files.")
    parser.add_argument("--json", action="store_true", help="Print JSON diagnostics to stdout.")
    parser.add_argument("--target", choices=("watch", "iphone", "all"), default="watch",
                        help="Native bundle destination; existing default remains watch.")
    args = parser.parse_args()
    try:
        if args.target == "all":
            # Check both target trees for conflicting local edits before either write.
            for target in TARGETS:
                synchronize(check=True, target=target)
            results = [synchronize(check=args.check, target=target) for target in TARGETS]
            result = {"status": "OUT_OF_DATE" if any(item["status"] == "OUT_OF_DATE" for item in results)
                      else "UP_TO_DATE" if all(item["status"] == "UP_TO_DATE" for item in results) else "SYNCED",
                      "checkOnly": args.check, "targets": results}
        else:
            result = synchronize(check=args.check, target=args.target)
    except (OSError, ValueError, TypeError) as error:
        result = {"status": "ERROR", "message": str(error), "checkOnly": args.check}
    if args.json or args.target == "all":
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print(f"{result['status']}: " + (result.get("message") or
              f"{result['fileCount']} source files; {len(result['availableClipIds'])} available clips; {len(result['plannedClipIds'])} planned clips; {len(result['validationWarnings'])} visual/technical warnings."))
        for name in result.get("copied", []):
            print(f"Copied and SHA-verified: {name}")
        if result.get("outdated"):
            print("Out of date: " + ", ".join(result["outdated"]))
    return 1 if result["status"] in {"ERROR", "OUT_OF_DATE"} else 0


if __name__ == "__main__":
    raise SystemExit(main())
