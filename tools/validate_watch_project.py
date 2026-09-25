"""Windows-safe source validation for the Patrick watch app and complication."""

from __future__ import annotations

import json
import plistlib
import re
import struct
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "PatrickFace"
EXTENSION = ROOT / "PatrickFaceComplications"
PROJECT = ROOT / "PatrickFace.xcodeproj" / "project.pbxproj"
IOS_ROOT = ROOT / "iOSCompanion"
IOS_PROJECT = IOS_ROOT / "PatrickCompanion.xcodeproj" / "project.pbxproj"
WIRE = IOS_ROOT / "WatchIntegration" / "PatrickWatchWire.swift"
RECEIVER = IOS_ROOT / "WatchIntegration" / "PatrickWatchReceiver.swift"
PRIVACY = APP / "PrivacyInfo.xcprivacy"
SCHEME = (
    ROOT
    / "PatrickFace.xcodeproj"
    / "xcshareddata"
    / "xcschemes"
    / "PatrickFace.xcscheme"
)

APP_GROUP = "group.com.chans.patrickface.shared"
IOS_BUNDLE_ID = "com.chans.patrickface.companion"
APP_BUNDLE_ID = f"{IOS_BUNDLE_ID}.watchkitapp"
EXTENSION_BUNDLE_ID = f"{APP_BUNDLE_ID}.complications"
WIDGET_BUNDLE_ID = f"{IOS_BUNDLE_ID}.widgets"
PROTOCOL_VERSION = 1
TRANSPORT_KEY = "patrick.envelope.v1"

errors: list[str] = []
checks = 0


def check(condition: bool, message: str) -> None:
    global checks
    checks += 1
    if not condition:
        errors.append(message)


def load_plist(path: Path) -> dict:
    try:
        with path.open("rb") as stream:
            return plistlib.load(stream)
    except (OSError, plistlib.InvalidFileException) as error:
        errors.append(f"{path.relative_to(ROOT)} is not a valid plist: {error}")
        return {}


def load_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        errors.append(f"{path.relative_to(ROOT)} is not valid JSON: {error}")
        return {}


required_paths = [
    APP / "PatrickFaceApp.swift",
    APP / "PatrickFaceView.swift",
    APP / "PatrickShared.swift",
    APP / "Info.plist",
    APP / "PatrickFace.entitlements",
    PRIVACY,
    EXTENSION / "PatrickFaceComplications.swift",
    EXTENSION / "Info.plist",
    EXTENSION / "PatrickFaceComplications.entitlements",
    WIRE,
    RECEIVER,
    PROJECT,
    IOS_PROJECT,
    SCHEME,
]
for path in required_paths:
    check(path.is_file(), f"missing required file: {path.relative_to(ROOT)}")

app_info = load_plist(APP / "Info.plist")
extension_info = load_plist(EXTENSION / "Info.plist")
app_entitlements = load_plist(APP / "PatrickFace.entitlements")
extension_entitlements = load_plist(
    EXTENSION / "PatrickFaceComplications.entitlements"
)
privacy = load_plist(PRIVACY)
ios_app_entitlements = load_plist(
    IOS_ROOT / "PatrickCompanion" / "PatrickCompanion.entitlements"
)
widget_entitlements = load_plist(
    IOS_ROOT / "PatrickWidgets" / "PatrickWidgets.entitlements"
)

check(app_info.get("WKApplication") is True, "app plist must declare WKApplication")
check(app_info.get("WKWatchOnly") is False, "paired watch app must not remain watch-only")
check(
    app_info.get("WKCompanionAppBundleIdentifier") == IOS_BUNDLE_ID,
    "watch app has the wrong companion bundle identifier",
)
check(
    app_info.get("WKRunsIndependentlyOfCompanionApp") is True,
    "watch app must keep independent operation enabled",
)
check(
    app_info.get("WKSupportsAlwaysOnDisplay") is True,
    "app plist must opt into Always On",
)
check(app_info.get("MinimumOSVersion") == "10.0", "app minimum must be watchOS 10")

url_schemes = {
    scheme
    for item in app_info.get("CFBundleURLTypes", [])
    for scheme in item.get("CFBundleURLSchemes", [])
}
check("patrickface" in url_schemes, "patrickface deep-link scheme is not registered")
check(
    extension_info.get("NSExtension", {}).get("NSExtensionPointIdentifier")
    == "com.apple.widgetkit-extension",
    "extension plist must use the WidgetKit extension point",
)
check(
    extension_info.get("CFBundlePackageType") == "XPC!",
    "extension plist must use the XPC! package type",
)

app_groups = app_entitlements.get("com.apple.security.application-groups", [])
extension_groups = extension_entitlements.get(
    "com.apple.security.application-groups", []
)
check(app_groups == [APP_GROUP], "app entitlement has the wrong App Group")
check(
    extension_groups == [APP_GROUP],
    "extension entitlement has the wrong App Group",
)

privacy_reasons = {
    reason
    for item in privacy.get("NSPrivacyAccessedAPITypes", [])
    if item.get("NSPrivacyAccessedAPIType")
    == "NSPrivacyAccessedAPICategoryUserDefaults"
    for reason in item.get("NSPrivacyAccessedAPITypeReasons", [])
}
check(
    {"1C8F.1", "CA92.1"}.issubset(privacy_reasons),
    "watch privacy manifest must cover App Group and app-local UserDefaults",
)
check(
    privacy.get("NSPrivacyTracking") is False
    and privacy.get("NSPrivacyCollectedDataTypes") == [],
    "watch privacy manifest must declare no tracking or collected data",
)
check(
    ios_app_entitlements.get("com.apple.security.application-groups") == [APP_GROUP]
    and widget_entitlements.get("com.apple.security.application-groups")
    == [APP_GROUP],
    "iPhone app and widget must use the same App Group as watch targets",
)

project = PROJECT.read_text(encoding="utf-8")
check(
    'productType = "com.apple.product-type.app-extension";' in project,
    "WidgetKit app-extension target is missing",
)
check(
    "PatrickFaceComplications.appex in Embed App Extensions" in project
    and "dstSubfolderSpec = 13;" in project,
    "complication extension is not embedded by the watch app",
)
check(
    project.count("PatrickShared.swift in Sources") >= 4,
    "PatrickShared.swift must be a source of both targets",
)
check(
    project.count("PatrickWatchReceiver.swift in Sources") == 2
    and project.count("PatrickWatchWire.swift in Sources") == 2,
    "watch receiver and namespaced wire DTOs must belong to the watch app target",
)
check(
    "PatrickModels.swift in Sources" not in project,
    "iPhone PatrickModels.swift must not be compiled into the watch project",
)
check(
    project.count("PrivacyInfo.xcprivacy in Resources") == 4,
    "watch privacy manifest must be copied into app and complication bundles",
)
check(
    project.count(f"PRODUCT_BUNDLE_IDENTIFIER = {APP_BUNDLE_ID};") == 2,
    "watch app bundle identifier is inconsistent",
)
check(
    project.count(f"PRODUCT_BUNDLE_IDENTIFIER = {EXTENSION_BUNDLE_ID};") == 2,
    "extension bundle identifier is inconsistent",
)
check(
    "PRODUCT_BUNDLE_IDENTIFIER = com.chans.patrickface;"
    not in project
    and "PRODUCT_BUNDLE_IDENTIFIER = com.chans.patrickface.complications;"
    not in project,
    "legacy standalone bundle identifiers remain in watch build settings",
)
check(
    "CODE_SIGN_ENTITLEMENTS = PatrickFace/PatrickFace.entitlements;" in project,
    "watch app entitlement is not assigned",
)
check(
    "CODE_SIGN_ENTITLEMENTS = "
    "PatrickFaceComplications/PatrickFaceComplications.entitlements;" in project,
    "extension entitlement is not assigned",
)
check(
    "CODE_SIGNING_ALLOWED = NO" not in project
    and "CODE_SIGNING_REQUIRED = NO" not in project,
    "project still disables signing",
)
check(
    project.count("WATCHOS_DEPLOYMENT_TARGET = 10.0;") == 4,
    "both targets must use watchOS 10 in Debug and Release",
)
check(
    project.count("SKIP_INSTALL = YES;") == 4,
    "embedded watch app and complication must be skipped as archive roots",
)
check(project.count("{") == project.count("}"), "project braces are unbalanced")
check(project.count("(") == project.count(")"), "project parentheses are unbalanced")

object_ids = re.findall(
    r"^\t\t([A-F0-9]{24})(?: /\*.*?\*/)? = \{",
    project,
    re.MULTILINE,
)
check(
    len(object_ids) == len(set(object_ids)),
    "project contains duplicate object declarations",
)
object_references = set(re.findall(r"\b[A-F0-9]{24}\b", project))
remote_references = set(
    re.findall(r"remoteGlobalIDString = ([A-F0-9]{24});", project)
)
check(
    not (object_references - set(object_ids) - remote_references),
    "watch project contains undefined PBX object references",
)

ios_project = IOS_PROJECT.read_text(encoding="utf-8")
for token in (
    "path = ../PatrickFace.xcodeproj;",
    "remoteGlobalIDString = B20000000000000000000002;",
    "remoteGlobalIDString = B20000000000000000000006;",
    "isa = PBXReferenceProxy;",
    "PatrickFace.app in Embed Watch Content",
    'name = "Embed Watch Content";',
    'dstPath = "$(CONTENTS_FOLDER_PATH)/Watch";',
    "dstSubfolderSpec = 16;",
    "name = PatrickFace;",
):
    check(token in ios_project, f"companion project is missing cross-project token: {token}")
check(
    ios_project.count(
        f"PRODUCT_BUNDLE_IDENTIFIER = {IOS_BUNDLE_ID};"
    )
    == 2,
    "iPhone bundle identifier drifted",
)
check(
    ios_project.count(
        f"PRODUCT_BUNDLE_IDENTIFIER = {WIDGET_BUNDLE_ID};"
    )
    == 2,
    "widget bundle identifier drifted",
)

scheme_root = ET.parse(SCHEME).getroot()
scheme_blueprints = {
    node.attrib.get("BlueprintName")
    for node in scheme_root.findall(".//BuildableReference")
}
check("PatrickFace" in scheme_blueprints, "shared scheme does not build PatrickFace")
check(
    "PatrickFaceComplications" in scheme_blueprints,
    "shared scheme does not build the complication extension",
)

shared_source = (APP / "PatrickShared.swift").read_text(encoding="utf-8")
app_source = (APP / "PatrickFaceApp.swift").read_text(encoding="utf-8")
face_source = (APP / "PatrickFaceView.swift").read_text(encoding="utf-8")
complication_source = (
    EXTENSION / "PatrickFaceComplications.swift"
).read_text(encoding="utf-8")
wire_source = WIRE.read_text(encoding="utf-8")
receiver_source = RECEIVER.read_text(encoding="utf-8")
ios_schema_source = (
    IOS_ROOT / "Shared" / "PatrickMessageSchema.swift"
).read_text(encoding="utf-8")
ios_models_source = (
    IOS_ROOT / "Shared" / "PatrickModels.swift"
).read_text(encoding="utf-8")
ios_artwork_source = (
    IOS_ROOT / "Shared" / "PatrickArtworkView.swift"
).read_text(encoding="utf-8")
ios_sync_source = (
    IOS_ROOT / "PatrickCompanion" / "WatchSyncService.swift"
).read_text(encoding="utf-8")

check(APP_GROUP in shared_source, "shared source has a mismatched App Group")
check(
    f"static let currentProtocolVersion = {PROTOCOL_VERSION}" in wire_source
    and f"static let currentProtocolVersion = {PROTOCOL_VERSION}"
    in ios_schema_source,
    "iPhone and watch protocol versions drifted",
)
check(
    f'static let transportKey = "{TRANSPORT_KEY}"' in wire_source
    and f'static let transportKey = "{TRANSPORT_KEY}"' in ios_schema_source,
    "iPhone and watch transport keys drifted",
)
check(
    f"static let settingsSchemaVersion = {PROTOCOL_VERSION}" in wire_source
    and f"static let schemaVersion = {PROTOCOL_VERSION}" in ios_models_source,
    "iPhone and watch settings schema versions drifted",
)
for command_value in (
    "set-theme",
    "set-sleep-mode",
    "set-preview-state",
    "play-theme-sound",
    "open-watch-face",
    "start-timer",
    "stop-timer",
):
    token = f'= "{command_value}"'
    check(
        token in wire_source and token in ios_schema_source,
        f"iPhone and watch command value drifted: {command_value}",
    )
check(
    'case cel1999 = "cel-1999"' in wire_source
    and 'case faithful3D = "faithful-3d"' in wire_source
    and 'case cel1999 = "cel-1999"' in ios_models_source
    and 'case faithful3D = "faithful-3d"' in ios_models_source
    and "case .cel1999:" in wire_source
    and "case .faithful3D:" in wire_source,
    "watch wire theme mapping is incomplete",
)
check(
    "enum PatrickWatchWire" in wire_source
    and "enum PatrickTheme:" not in wire_source
    and "struct PatrickSettings" not in wire_source,
    "watch wire DTOs are not collision-free",
)
check(
    "didReceiveUserInfo" in receiver_source
    and "didReceiveApplicationContext" in receiver_source
    and "sendAcknowledgement" in receiver_source
    and "processedIDs" in receiver_source,
    "watch receiver lost queued delivery, context, acknowledgement, or deduplication",
)
check(
    "sendAcknowledgement" in ios_sync_source
    and "markMessageProcessed" in ios_sync_source,
    "iPhone receiver lost queued acknowledgements or deduplication",
)
check(
    "companion.activate(" in app_source
    and "companion.sendSnapshot(theme:" in app_source
    and "model.sleepMode" in face_source
    and "model.previewState" in face_source,
    "watch model/view are not wired to companion controls and snapshots",
)
check(
    'static let scheme = "patrickface"' in shared_source,
    "shared deep-link parser has a mismatched scheme",
)
check(
    ".onOpenURL" in app_source and "PatrickDeepLink.parse" in app_source,
    "watch app does not route incoming deep links",
)
check(
    "WidgetCenter.shared.reloadTimelines" in app_source,
    "app does not refresh complications after shared-state changes",
)
check(
    all(
        family in complication_source
        for family in (
            ".accessoryCircular",
            ".accessoryRectangular",
            ".accessoryInline",
        )
    ),
    "one or more required accessory families are missing",
)
check(
    "for offset in 1...60" in complication_source
    and "policy: .atEnd" in complication_source,
    "minute-entry refresh policy is missing",
)
check(
    ".widgetURL(entry.deepLinkURL)" in complication_source,
    "complication does not deep-link into the app",
)
check(
    "Color.black" in complication_source
    and "for index in 0..<12" in complication_source,
    "complication lost its pure-black background or subtle edge markers",
)
check(
    "PatrickClockAngles.make" in face_source
    and "PatrickClockAngles.make" in complication_source,
    "app and complication must share real hour/minute calculations",
)
check(
    "drawTicks(context:" in face_source
    and "Text(String(format: \"%02d:%02d\"" in face_source,
    "full-screen digital time or edge markers were removed",
)

cel_render_source = face_source[
    face_source.index("private func drawCel"):
    face_source.index("private func drawToon3D")
]
toon_render_source = face_source[
    face_source.index("private func drawToon3D"):
    face_source.index("private func drawClockHub")
]
check(
    cel_render_source.index('rig.draw(Image("season1-body-normal")')
    < cel_render_source.index("drawArm(")
    and cel_render_source.count("pivot: Self.clockHub") == 2
    and cel_render_source.rindex("drawClockHub(")
    > cel_render_source.rindex("drawArm("),
    "2D hands do not share one front-layer clock hub",
)
check(
    toon_render_source.index('rig.draw(Image("season1-3d-body")')
    < toon_render_source.index("drawArm(")
    and toon_render_source.count("pivot: Self.clockHub") == 2
    and toon_render_source.rindex("drawClockHub(")
    > toon_render_source.rindex("drawArm("),
    "Toon-3D hands do not share one front-layer clock hub",
)
check(
    'private static let clockHub = CGPoint(x: 360, y: 498)' in face_source
    and "private static let hourHandLength: CGFloat = 250" in face_source
    and "private static let minuteHandLength: CGFloat = 340" in face_source
    and not any(
        obsolete in face_source
        for obsolete in (
            "redrawShoulderCaps",
            "redrawFaceShield",
            "faceProtectionWeight",
            "handPivotY",
        )
    ),
    "watch renderer retained shoulder pivots or lost the common hub constants",
)
check(
    ios_artwork_source.count("bodyLayer(side: side)") == 1
    and ios_artwork_source.index("bodyLayer(side: side)")
    < ios_artwork_source.index("arm(")
    and "Self.hubYOffset - heightScale / 2" in ios_artwork_source
    and "xOffset" not in ios_artwork_source
    and "faceProtectionWeight" not in ios_artwork_source
    and "shoulder" not in ios_artwork_source.lower(),
    "iOS companion hands do not share one front-layer hub",
)

obsolete_runtime_images = ("dial", "body", "body-night", "arm")
for image_name in obsolete_runtime_images:
    pattern = re.compile(rf'Image\(\s*"{re.escape(image_name)}"\s*\)')
    check(
        not pattern.search(app_source + face_source + shared_source + complication_source),
        f'obsolete asset "{image_name}" is still referenced by runtime source',
    )
    legacy_png = APP / "Assets.xcassets" / f"{image_name}.imageset" / f"{image_name}.png"
    check(
        legacy_png.is_file(),
        f"legacy asset was deleted instead of merely retired: {legacy_png.relative_to(ROOT)}",
    )

approved_assets = (
    "season1-body-normal",
    "season1-hour-arm",
    "season1-minute-arm",
    "season1-3d-body",
    "season1-3d-arm",
)
for asset_name in approved_assets:
    image_set = APP / "Assets.xcassets" / f"{asset_name}.imageset"
    contents = load_json(image_set / "Contents.json")
    filenames = [
        image.get("filename")
        for image in contents.get("images", [])
        if image.get("filename")
    ]
    check(
        filenames == [f"{asset_name}.png"],
        f"{asset_name} asset catalog metadata is inconsistent",
    )
    png = image_set / f"{asset_name}.png"
    check(png.is_file(), f"approved layer is missing: {png.relative_to(ROOT)}")
    if png.is_file():
        data = png.read_bytes()
        check(data.startswith(b"\x89PNG\r\n\x1a\n"), f"{asset_name} is not a PNG")
        if len(data) >= 26:
            width, height = struct.unpack(">II", data[16:24])
            color_type = data[25]
            check(width > 0 and height > 0, f"{asset_name} has invalid dimensions")
            check(
                color_type in {4, 6} or b"tRNS" in data,
                f"{asset_name} does not expose transparency",
            )

if errors:
    print(f"FAIL: {len(errors)} of {checks} watch-surface checks failed.")
    for error in errors:
        print(f" - {error}")
    sys.exit(1)

print(
    f"PASS: {checks} watch-surface checks "
    "(pairing, protocol, privacy, project, targets, UI, assets)."
)
