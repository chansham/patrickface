"""Create a local device archive. No uploads, provisioning downloads or installs.

Unsigned is the default structural archive check. Signed mode requires existing
certificates/profiles on the Mac and an explicit local configuration file.
"""
from pathlib import Path
import argparse
import json
import platform
import plistlib
import re
import subprocess
import tempfile
from check_apple_bundle import IDS, verify

ROOT = Path(__file__).resolve().parents[1]
PROFILE_KEYS = ["PATRICK_PHONE_PROFILE", "PATRICK_WIDGET_PROFILE", "PATRICK_WATCH_PROFILE", "PATRICK_COMPLICATION_PROFILE"]

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--signing-config", type=Path, help="Explicit local JSON; omit for unsigned archive")
    parser.add_argument("--build-number", default="1")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if platform.system() != "Darwin":
        parser.error("A Mac with Xcode is required; nothing built.")
    if not re.fullmatch(r"[1-9][0-9]*(?:\.[0-9]+){0,2}", args.build_number):
        parser.error("Invalid build number")
    config = None
    if args.signing_config:
        config = json.loads(args.signing_config.read_text(encoding="utf-8"))
        if not re.fullmatch(r"[A-Z0-9]{10}", config.get("teamID", "")):
            parser.error("Set your actual Team ID; the example is not runnable")
        if set(config.get("profiles", {})) != set(IDS.values()):
            parser.error("All four exact product profiles are required")
        if any(not isinstance(v, str) or not v or v.startswith("YOUR_") for v in config["profiles"].values()):
            parser.error("Replace profile-name placeholders with profiles installed on this Mac")
        if config.get("method") not in {"app-store-connect", "release-testing", "debugging"}:
            parser.error("Use a current Xcode export method: app-store-connect, release-testing or debugging")
        if config.get("signingCertificate") not in {"Apple Distribution", "Apple Development"}:
            parser.error("Choose Apple Distribution or Apple Development")
    output = args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix="patrick-device-archive-"))
    if output.exists() and any(output.iterdir()):
        parser.error("Output must be empty, to preserve any previous archive")
    output.mkdir(parents=True, exist_ok=True)
    archive = output / "PatrickCompanion.xcarchive"
    subprocess.run(["xcodebuild", "-version"], check=True)
    subprocess.run(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], check=True)
    subprocess.run(["xcrun", "--sdk", "watchos", "--show-sdk-path"], check=True)
    command = ["xcodebuild", "-workspace", str(ROOT / "iOSCompanion/PatrickFaceSuite.xcworkspace"),
        "-scheme", "PatrickCompanion", "-configuration", "Release", "-destination", "generic/platform=iOS",
        "-archivePath", str(archive), "-derivedDataPath", str(output / "DerivedData"),
        f"CURRENT_PROJECT_VERSION={args.build_number}"]
    if config:
        command += [f"DEVELOPMENT_TEAM={config['teamID']}", "CODE_SIGN_STYLE=Manual", f"CODE_SIGN_IDENTITY={config['signingCertificate']}"]
        command += [f"{key}={config['profiles'][identifier]}" for key, identifier in zip(PROFILE_KEYS, IDS.values())]
    else:
        command += ["CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY=", "DEVELOPMENT_TEAM="]
    subprocess.run(command + ["archive"], check=True)
    app = archive / "Products/Applications/PatrickCompanion.app"
    verify(app)
    if config:
        for relative in IDS:
            subprocess.run(["codesign", "--verify", "--strict", str(app / relative)], check=True)
        options = {"method": config["method"], "destination": "export", "teamID": config["teamID"],
            "signingStyle": "manual", "signingCertificate": config["signingCertificate"],
            "provisioningProfiles": config["profiles"], "manageAppVersionAndBuildNumber": False,
            "uploadSymbols": False}
        if config["method"] == "app-store-connect":
            options["testFlightInternalTestingOnly"] = bool(config.get("testFlightInternalTestingOnly", True))
        plist = output / "ExportOptions.plist"
        plist.write_bytes(plistlib.dumps(options))
        subprocess.run(["xcodebuild", "-exportArchive", "-archivePath", str(archive),
            "-exportPath", str(output / "Export"), "-exportOptionsPlist", str(plist)], check=True)
        print("Signed archive/export completed locally. No upload or installation performed.")
    else:
        print("Unsigned device archive checked. It cannot be installed or submitted.")
    print(f"Output: {output}")

if __name__ == "__main__":
    main()
