#!/usr/bin/env python3
"""Windows-safe structural checks for the companion Xcode project.

This does not replace xcodebuild, actool, Swift compilation, signing, or device
tests. It deliberately prints the pending Mac-only gate.
"""

from __future__ import annotations

import json
import plistlib
import re
import struct
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # Pillow is optional; PNG structure still validates below.
    Image = None

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "PatrickCompanion.xcodeproj" / "project.pbxproj"
REPO_ROOT = ROOT.parent
WATCH_PROJECT = REPO_ROOT / "PatrickFace.xcodeproj" / "project.pbxproj"
WATCH_APP = REPO_ROOT / "PatrickFace"
WATCH_EXTENSION = REPO_ROOT / "PatrickFaceComplications"

APP_GROUP = "group.com.chans.patrickface.shared"
IOS_BUNDLE_ID = "com.chans.patrickface.companion"
WIDGET_BUNDLE_ID = f"{IOS_BUNDLE_ID}.widgets"
WATCH_BUNDLE_ID = f"{IOS_BUNDLE_ID}.watchkitapp"
WATCH_EXTENSION_BUNDLE_ID = f"{WATCH_BUNDLE_ID}.complications"
PROTOCOL_VERSION = 1
TRANSPORT_KEY = "patrick.envelope.v1"

REQUIRED_FILES = [
    "Shared/PatrickModels.swift",
    "Shared/PatrickMessageSchema.swift",
    "Shared/PatrickDeepLink.swift",
    "Shared/PatrickActivityAttributes.swift",
    "Shared/PatrickSharedStore.swift",
    "Shared/PatrickArtworkView.swift",
    "PatrickCompanion/PatrickCompanionApp.swift",
    "PatrickCompanion/AppModel.swift",
    "PatrickCompanion/WatchSyncService.swift",
    "PatrickCompanion/PatrickIntents.swift",
    "PatrickCompanion/PatrickActivityController.swift",
    "PatrickWidgets/PatrickWidgetsBundle.swift",
    "PatrickWidgets/PatrickStatusWidget.swift",
    "PatrickWidgets/PatrickLiveActivity.swift",
    "WatchIntegration/PatrickWatchReceiver.swift",
    "PatrickCompanionTests/PatrickContractTests.swift",
    "Resources/Assets.xcassets/Contents.json",
    "Resources/PrivacyInfo.xcprivacy",
    "WatchIntegration/PatrickWatchWire.swift",
    "PatrickCompanion.xcodeproj/project.pbxproj",
    "PatrickFaceSuite.xcworkspace/contents.xcworkspacedata",
    "PatrickCompanion.xcodeproj/xcshareddata/xcschemes/PatrickCompanion.xcscheme",
    "PatrickCompanion.xcodeproj/xcshareddata/xcschemes/PatrickCompanion-Demo.xcscheme",
    "README.md",
    "docs/WATCH_INTEGRATION.md",
    "tools/verify_companion_on_mac.sh",
]

REQUIRED_PROJECT_TOKENS = [
    'name = PatrickCompanion;',
    'name = PatrickWidgets;',
    'name = PatrickCompanionTests;',
    'productType = "com.apple.product-type.application";',
    'productType = "com.apple.product-type.app-extension";',
    'productType = "com.apple.product-type.bundle.unit-test";',
    'PatrickWidgets.appex in Embed App Extensions',
    'CODE_SIGN_ENTITLEMENTS = PatrickCompanion/PatrickCompanion.entitlements;',
    'CODE_SIGN_ENTITLEMENTS = PatrickWidgets/PatrickWidgets.entitlements;',
    'PRODUCT_BUNDLE_IDENTIFIER = com.chans.patrickface.companion;',
    'PRODUCT_BUNDLE_IDENTIFIER = com.chans.patrickface.companion.widgets;',
    'IPHONEOS_DEPLOYMENT_TARGET = 26.0;',
    'path = ../PatrickFace.xcodeproj;',
    'isa = PBXReferenceProxy;',
    'PatrickFace.app in Embed Watch Content',
    'name = "Embed Watch Content";',
    'dstPath = "$(CONTENTS_FOLDER_PATH)/Watch";',
    'dstSubfolderSpec = 16;',
    'name = PatrickFace;',
]

REQUIRED_SOURCE_REFERENCES = [
    "PatrickModels.swift in Sources",
    "PatrickMessageSchema.swift in Sources",
    "PatrickDeepLink.swift in Sources",
    "PatrickActivityAttributes.swift in Sources",
    "PatrickSharedStore.swift in Sources",
    "PatrickArtworkView.swift in Sources",
    "PatrickCompanionApp.swift in Sources",
    "WatchSyncService.swift in Sources",
    "PatrickIntents.swift in Sources",
    "PatrickWidgetsBundle.swift in Sources",
    "PatrickStatusWidget.swift in Sources",
    "PatrickLiveActivity.swift in Sources",
    "PatrickContractTests.swift in Sources",
]


def fail(errors: list[str], message: str) -> None:
    errors.append(message)


def display_path(path: Path) -> Path:
    try:
        return path.relative_to(ROOT)
    except ValueError:
        return path.relative_to(REPO_ROOT)


def struct_fields(source: str, name: str) -> set[str]:
    match = re.search(rf"\bstruct\s+{re.escape(name)}\b[^{{]*\{{", source)
    if match is None:
        return set()
    opening = match.end() - 1
    depth = 0
    for index in range(opening, len(source)):
        character = source[index]
        if character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
            if depth == 0:
                body = source[opening + 1 : index]
                return set(
                    re.findall(
                        r"^\s*(?:var|let)\s+([A-Za-z_][A-Za-z0-9_]*)\s*:",
                        body,
                        flags=re.MULTILINE,
                    )
                )
    return set()


def load_plist(path: Path, errors: list[str]) -> dict:
    try:
        with path.open("rb") as file:
            value = plistlib.load(file)
        if not isinstance(value, dict):
            fail(errors, f"{display_path(path)} is not a plist dictionary")
            return {}
        return value
    except Exception as error:  # noqa: BLE001 - validator reports all failures
        fail(errors, f"cannot parse {display_path(path)}: {error}")
        return {}


def png_dimensions(path: Path) -> tuple[int, int]:
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise ValueError("not a PNG with an IHDR header")
    return struct.unpack(">II", data[16:24])


def validate_files(errors: list[str]) -> None:
    for relative in REQUIRED_FILES:
        if not (ROOT / relative).is_file():
            fail(errors, f"missing required file: {relative}")
    for path in [
        WATCH_PROJECT,
        WATCH_APP / "Info.plist",
        WATCH_APP / "PatrickFace.entitlements",
        WATCH_APP / "PrivacyInfo.xcprivacy",
        WATCH_EXTENSION / "PatrickFaceComplications.entitlements",
    ]:
        if not path.is_file():
            fail(errors, f"missing required file: {display_path(path)}")


def validate_plists(errors: list[str]) -> None:
    app = load_plist(ROOT / "PatrickCompanion" / "Info.plist", errors)
    widget = load_plist(ROOT / "PatrickWidgets" / "Info.plist", errors)
    app_entitlements = load_plist(
        ROOT / "PatrickCompanion" / "PatrickCompanion.entitlements",
        errors,
    )
    widget_entitlements = load_plist(
        ROOT / "PatrickWidgets" / "PatrickWidgets.entitlements",
        errors,
    )
    privacy = load_plist(ROOT / "Resources" / "PrivacyInfo.xcprivacy", errors)
    watch = load_plist(WATCH_APP / "Info.plist", errors)
    watch_entitlements = load_plist(
        WATCH_APP / "PatrickFace.entitlements",
        errors,
    )
    complication_entitlements = load_plist(
        WATCH_EXTENSION / "PatrickFaceComplications.entitlements",
        errors,
    )
    watch_privacy = load_plist(WATCH_APP / "PrivacyInfo.xcprivacy", errors)

    if app.get("NSSupportsLiveActivities") is not True:
        fail(errors, "app Info.plist must enable NSSupportsLiveActivities")

    schemes = [
        scheme
        for item in app.get("CFBundleURLTypes", [])
        for scheme in item.get("CFBundleURLSchemes", [])
    ]
    if "patrickface" not in schemes:
        fail(errors, "app Info.plist is missing the patrickface URL scheme")

    extension = widget.get("NSExtension", {})
    if extension.get("NSExtensionPointIdentifier") != "com.apple.widgetkit-extension":
        fail(errors, "widget Info.plist has the wrong extension point")

    for name, entitlement in [
        ("app", app_entitlements),
        ("widget", widget_entitlements),
        ("watch app", watch_entitlements),
        ("watch complication", complication_entitlements),
    ]:
        groups = entitlement.get("com.apple.security.application-groups", [])
        if groups != [APP_GROUP]:
            fail(errors, f"{name} entitlements must contain only {APP_GROUP}")

    if watch.get("WKCompanionAppBundleIdentifier") != IOS_BUNDLE_ID:
        fail(errors, "watch Info.plist has the wrong companion bundle identifier")
    if watch.get("WKWatchOnly") is not False:
        fail(errors, "watch Info.plist must set WKWatchOnly to false")
    if watch.get("WKRunsIndependentlyOfCompanionApp") is not True:
        fail(errors, "watch app must remain independent of iPhone installation")

    if "NFCReaderUsageDescription" in app:
        fail(
            errors,
            "Core NFC permission is unexpected; NFC is intentionally delegated to Shortcuts",
        )

    accessed_types = privacy.get("NSPrivacyAccessedAPITypes", [])
    user_defaults_reasons = [
        reason
        for item in accessed_types
        if item.get("NSPrivacyAccessedAPIType")
        == "NSPrivacyAccessedAPICategoryUserDefaults"
        for reason in item.get("NSPrivacyAccessedAPITypeReasons", [])
    ]
    if not {"1C8F.1", "CA92.1"}.issubset(user_defaults_reasons):
        fail(
            errors,
            "privacy manifest must cover App Group and fallback UserDefaults",
        )
    if privacy.get("NSPrivacyTracking") is not False:
        fail(errors, "privacy manifest must explicitly disable tracking")
    if privacy.get("NSPrivacyCollectedDataTypes") != []:
        fail(errors, "privacy manifest should declare no collected data")

    watch_accessed_types = watch_privacy.get("NSPrivacyAccessedAPITypes", [])
    watch_reasons = {
        reason
        for item in watch_accessed_types
        if item.get("NSPrivacyAccessedAPIType")
        == "NSPrivacyAccessedAPICategoryUserDefaults"
        for reason in item.get("NSPrivacyAccessedAPITypeReasons", [])
    }
    if not {"1C8F.1", "CA92.1"}.issubset(watch_reasons):
        fail(
            errors,
            "watch privacy manifest must cover App Group and local UserDefaults",
        )
    if (
        watch_privacy.get("NSPrivacyTracking") is not False
        or watch_privacy.get("NSPrivacyCollectedDataTypes") != []
    ):
        fail(errors, "watch privacy manifest must declare no tracking or collection")


def validate_project(errors: list[str]) -> None:
    if not PROJECT.is_file():
        return
    text = PROJECT.read_text(encoding="utf-8")
    for token in REQUIRED_PROJECT_TOKENS + REQUIRED_SOURCE_REFERENCES:
        if token not in text:
            fail(errors, f"project.pbxproj is missing: {token}")

    for opening, closing in [("{", "}"), ("(", ")")]:
        if text.count(opening) != text.count(closing):
            fail(errors, f"project.pbxproj has unbalanced {opening}{closing}")

    definitions = re.findall(
        r"^\t\t([A-F0-9]{24})(?: /\*.*?\*/)? = \{",
        text,
        flags=re.MULTILINE,
    )
    duplicates = sorted({value for value in definitions if definitions.count(value) > 1})
    if duplicates:
        fail(errors, f"duplicate PBX object IDs: {', '.join(duplicates)}")

    references = set(re.findall(r"\b[A-F0-9]{24}\b", text))
    remote_references = set(
        re.findall(r"remoteGlobalIDString = ([A-F0-9]{24});", text)
    )
    undefined = sorted(references - set(definitions) - remote_references)
    if undefined:
        fail(errors, f"undefined PBX object IDs: {', '.join(undefined)}")

    if "CODE_SIGNING_ALLOWED = NO;" in text:
        fail(errors, "project disables code signing instead of leaving it for the Mac")
    if text.count("/* PrivacyInfo.xcprivacy in Resources */,") != 2:
        fail(errors, "privacy manifest must be copied into both app and widget bundles")

    if text.count(f"PRODUCT_BUNDLE_IDENTIFIER = {IOS_BUNDLE_ID};") != 2:
        fail(errors, "iPhone bundle identifier drifted")
    if text.count(f"PRODUCT_BUNDLE_IDENTIFIER = {WIDGET_BUNDLE_ID};") != 2:
        fail(errors, "widget bundle identifier drifted")
    if (
        "PatrickWatchReceiver.swift in Sources" in text
        or "PatrickWatchWire.swift in Sources" in text
    ):
        fail(errors, "watch-only integration files leaked into an iOS target")

    if not WATCH_PROJECT.is_file():
        return
    watch_text = WATCH_PROJECT.read_text(encoding="utf-8")
    if watch_text.count(f"PRODUCT_BUNDLE_IDENTIFIER = {WATCH_BUNDLE_ID};") != 2:
        fail(errors, "watch app bundle identifier drifted")
    if (
        watch_text.count(
            f"PRODUCT_BUNDLE_IDENTIFIER = {WATCH_EXTENSION_BUNDLE_ID};"
        )
        != 2
    ):
        fail(errors, "watch complication bundle identifier drifted")
    if watch_text.count("PatrickWatchReceiver.swift in Sources") != 2:
        fail(errors, "PatrickWatchReceiver.swift is not in the watch app target")
    if watch_text.count("PatrickWatchWire.swift in Sources") != 2:
        fail(errors, "PatrickWatchWire.swift is not in the watch app target")
    if "PatrickModels.swift in Sources" in watch_text:
        fail(errors, "collision-prone iPhone PatrickModels.swift is in the watch target")
    if watch_text.count("/* PrivacyInfo.xcprivacy in Resources */,") != 2:
        fail(errors, "watch privacy manifest must be in app and complication bundles")
    if watch_text.count("SKIP_INSTALL = YES;") != 4:
        fail(errors, "embedded watch targets must not become archive roots")
    for opening, closing in [("{", "}"), ("(", ")")]:
        if watch_text.count(opening) != watch_text.count(closing):
            fail(errors, f"watch project has unbalanced {opening}{closing}")


def validate_xml(errors: list[str]) -> None:
    xml_files = [
        ROOT
        / "PatrickCompanion.xcodeproj"
        / "project.xcworkspace"
        / "contents.xcworkspacedata",
        ROOT / "PatrickFaceSuite.xcworkspace" / "contents.xcworkspacedata",
        ROOT
        / "PatrickCompanion.xcodeproj"
        / "xcshareddata"
        / "xcschemes"
        / "PatrickCompanion.xcscheme",
        ROOT
        / "PatrickCompanion.xcodeproj"
        / "xcshareddata"
        / "xcschemes"
        / "PatrickCompanion-Demo.xcscheme",
    ]
    for path in xml_files:
        try:
            ET.parse(path)
        except Exception as error:  # noqa: BLE001
            fail(errors, f"cannot parse {path.relative_to(ROOT)}: {error}")

    workspace = ROOT / "PatrickFaceSuite.xcworkspace" / "contents.xcworkspacedata"
    try:
        locations = {
            node.attrib.get("location")
            for node in ET.parse(workspace).getroot().findall(".//FileRef")
        }
        expected = {
            "group:PatrickCompanion.xcodeproj",
            "group:../PatrickFace.xcodeproj",
        }
        if not expected.issubset(locations):
            fail(errors, "workspace must reference both companion and watch projects")
    except Exception:
        pass  # The parse failure above already reports the actionable error.


def validate_assets(errors: list[str]) -> None:
    catalog = ROOT / "Resources" / "Assets.xcassets"
    for contents in catalog.rglob("Contents.json"):
        try:
            json.loads(contents.read_text(encoding="utf-8"))
        except Exception as error:  # noqa: BLE001
            fail(errors, f"invalid asset JSON {contents.relative_to(ROOT)}: {error}")

    pngs = list(catalog.rglob("*.png"))
    if len(pngs) != 6:
        fail(errors, f"expected 6 approved PNGs, found {len(pngs)}")
    for path in pngs:
        try:
            width, height = png_dimensions(path)
            is_pointer = "arm" in path.name.lower()
            if is_pointer:
                if width < 180 or height < 800:
                    fail(errors, f"pointer asset has unexpected size: {path.relative_to(ROOT)}")
            elif width < 300 or height < 300:
                fail(errors, f"asset is unexpectedly small: {path.relative_to(ROOT)}")
        except Exception as error:  # noqa: BLE001
            fail(errors, f"invalid PNG {path.relative_to(ROOT)}: {error}")

    icon = catalog / "AppIcon.appiconset" / "AppIcon.png"
    if icon.is_file() and png_dimensions(icon) != (1024, 1024):
        fail(errors, "AppIcon.png must be 1024x1024")

    if Image is not None:
        artwork = [
            path
            for path in pngs
            if "AppIcon.appiconset" not in path.as_posix()
        ]
        for path in artwork:
            with Image.open(path) as image:
                alpha = image.convert("RGBA").getchannel("A")
                minimum, maximum = alpha.getextrema()
                if minimum != 0 or maximum != 255:
                    fail(
                        errors,
                        "artwork must contain both transparent and opaque pixels: "
                        f"{path.relative_to(ROOT)}",
                    )
        if icon.is_file():
            with Image.open(icon) as image:
                minimum, maximum = image.convert("RGBA").getchannel("A").getextrema()
                if minimum != 255 or maximum != 255:
                    fail(errors, "AppIcon.png must not contain transparent pixels")

    provenance = ROOT / "Resources" / "asset-provenance.json"
    try:
        payload = json.loads(provenance.read_text(encoding="utf-8"))
        if len(payload.get("files", {})) != 6:
            fail(errors, "asset provenance must describe all 6 approved PNGs")
    except Exception as error:  # noqa: BLE001
        fail(errors, f"cannot parse asset provenance: {error}")


def validate_swift_shape(errors: list[str]) -> None:
    for path in ROOT.rglob("*.swift"):
        text = path.read_text(encoding="utf-8")
        if re.search(r"^\s*\d+\|", text, flags=re.MULTILINE):
            fail(errors, f"editor line-number metadata leaked into {path.relative_to(ROOT)}")
        for opening, closing in [("{", "}"), ("(", ")"), ("[", "]")]:
            if text.count(opening) != text.count(closing):
                fail(
                    errors,
                    f"{path.relative_to(ROOT)} has unbalanced {opening}{closing}",
                )


def validate_protocol(errors: list[str]) -> None:
    iphone_schema = (ROOT / "Shared" / "PatrickMessageSchema.swift").read_text(
        encoding="utf-8"
    )
    iphone_models = (ROOT / "Shared" / "PatrickModels.swift").read_text(
        encoding="utf-8"
    )
    watch_wire = (ROOT / "WatchIntegration" / "PatrickWatchWire.swift").read_text(
        encoding="utf-8"
    )
    watch_receiver = (
        ROOT / "WatchIntegration" / "PatrickWatchReceiver.swift"
    ).read_text(encoding="utf-8")
    iphone_sync = (
        ROOT / "PatrickCompanion" / "WatchSyncService.swift"
    ).read_text(encoding="utf-8")
    watch_model = (WATCH_APP / "PatrickFaceApp.swift").read_text(encoding="utf-8")
    watch_view = (WATCH_APP / "PatrickFaceView.swift").read_text(encoding="utf-8")
    iphone_store = (ROOT / "Shared" / "PatrickSharedStore.swift").read_text(
        encoding="utf-8"
    )
    watch_shared = (WATCH_APP / "PatrickShared.swift").read_text(encoding="utf-8")

    if APP_GROUP not in iphone_store or APP_GROUP not in watch_shared:
        fail(errors, "iPhone/watch shared-store App Group constants drifted")

    version_token = f"static let currentProtocolVersion = {PROTOCOL_VERSION}"
    transport_token = f'static let transportKey = "{TRANSPORT_KEY}"'
    for name, source in [
        ("iPhone schema", iphone_schema),
        ("watch wire", watch_wire),
    ]:
        if version_token not in source:
            fail(errors, f"{name} protocol version drifted from {PROTOCOL_VERSION}")
        if transport_token not in source:
            fail(errors, f"{name} transport key drifted from {TRANSPORT_KEY}")
    if (
        f"static let schemaVersion = {PROTOCOL_VERSION}" not in iphone_models
        or f"static let settingsSchemaVersion = {PROTOCOL_VERSION}"
        not in watch_wire
    ):
        fail(errors, "iPhone and watch settings schema versions drifted")

    command_values = [
        "set-theme",
        "set-sleep-mode",
        "set-preview-state",
        "play-theme-sound",
        "open-watch-face",
        "start-timer",
        "stop-timer",
    ]
    for value in command_values:
        token = f'= "{value}"'
        if token not in iphone_schema or token not in watch_wire:
            fail(errors, f"protocol command raw value drifted: {value}")

    for theme in ["cel-1999", "faithful-3d"]:
        if f'= "{theme}"' not in iphone_models or f'= "{theme}"' not in watch_wire:
            fail(errors, f"protocol theme raw value drifted: {theme}")

    field_contracts = [
        (
            iphone_schema,
            "PatrickCommandPayload",
            watch_wire,
            "Command",
            {"name", "theme", "sleepMode", "previewState", "timer", "deepLink", "careAction", "automationEvent"},
        ),
        (
            iphone_models,
            "PatrickSettings",
            watch_wire,
            "Settings",
            {
                "version",
                "revision",
                "theme",
                "previewState",
                "sleepMode",
                "demoMode",
                "updatedAt",
                "experience",
            },
        ),
        (
            iphone_models,
            "PatrickTimerSnapshot",
            watch_wire,
            "TimerSnapshot",
            {
                "id",
                "status",
                "title",
                "startedAt",
                "endsAt",
                "remainingSeconds",
            },
        ),
        (
            iphone_schema,
            "PatrickAcknowledgement",
            watch_wire,
            "Acknowledgement",
            {"messageID", "accepted", "detail"},
        ),
        (
            iphone_schema,
            "PatrickMessageEnvelope",
            watch_wire,
            "Envelope",
            {
                "protocolVersion",
                "id",
                "sentAt",
                "kind",
                "command",
                "settings",
                "timer",
                "acknowledgement",
            },
        ),
    ]
    for (
        iphone_source,
        iphone_name,
        watch_source,
        watch_name,
        expected_fields,
    ) in field_contracts:
        iphone_fields = struct_fields(iphone_source, iphone_name)
        watch_fields = struct_fields(watch_source, watch_name)
        if iphone_fields != expected_fields or watch_fields != expected_fields:
            fail(
                errors,
                "protocol DTO field drift: "
                f"{iphone_name}={sorted(iphone_fields)}, "
                f"{watch_name}={sorted(watch_fields)}",
            )

    if (
        "enum PatrickWatchWire" not in watch_wire
        or "enum PatrickTheme:" in watch_wire
        or "struct PatrickSettings" in watch_wire
    ):
        fail(errors, "watch wire contract is not collision-free and namespaced")
    if not all(
        token in watch_wire
        for token in (
            "case .cel1999:",
            ".cel",
            "case .faithful3D:",
            ".clay",
        )
    ):
        fail(errors, "watch wire theme mapping is incomplete")

    for name, source in [
        ("iPhone sync service", iphone_sync),
        ("watch receiver", watch_receiver),
    ]:
        for token in (
            "sendMessageData",
            "transferUserInfo",
            "updateApplicationContext",
            "didReceiveUserInfo",
            "didReceiveApplicationContext",
        ):
            if token not in source:
                fail(errors, f"{name} is missing delivery path: {token}")
    for token in ("processedIDs", "acknowledgement", "sendAcknowledgement"):
        if token not in watch_receiver:
            fail(errors, f"watch receiver is missing protocol behavior: {token}")
    for token in ("markMessageProcessed", "acknowledgement", "sendAcknowledgement"):
        if token not in iphone_sync:
            fail(errors, f"iPhone receiver is missing protocol behavior: {token}")
    if (
        "companion.activate(" not in watch_model
        or "companion.sendSnapshot(theme:" not in watch_model
        or "model.sleepMode" not in watch_view
        or "model.previewState" not in watch_view
    ):
        fail(errors, "watch model/view are not wired to companion protocol state")


def main() -> int:
    errors: list[str] = []
    validate_files(errors)
    validate_plists(errors)
    validate_project(errors)
    validate_xml(errors)
    validate_assets(errors)
    validate_swift_shape(errors)
    validate_protocol(errors)

    if errors:
        for error in errors:
            print(f"FAIL: {error}")
        print(f"\n{len(errors)} structural validation failure(s).")
        return 1

    print("PASS: required source and documentation files are present")
    print("PASS: plists, privacy manifest, and App Group entitlements parse")
    print("PASS: Xcode project declares app, widget, and test targets")
    print("PASS: remote watch dependency and embed phase are declared")
    print("PASS: bundle hierarchy and protocol v1 stay aligned")
    print("PASS: shared schemes and workspace XML parse")
    print("PASS: asset catalogs, PNG headers, and provenance validate")
    print("PASS: basic Swift delimiter and metadata checks pass")
    print(
        "PENDING_MAC: run xcodebuild, Swift tests, actool, signing, "
        "simulator, and paired-device validation in Xcode."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
