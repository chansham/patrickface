# Watch companion integration

The source and project-level companion relationship is now represented in the
repository. It still requires Apple tooling, provisioning, and paired hardware
before it can be called device-verified.

## Represented in project files

The bundle hierarchy is:

- iPhone: `com.chans.patrickface.companion`
- iPhone widget: `com.chans.patrickface.companion.widgets`
- watch app: `com.chans.patrickface.companion.watchkitapp`
- watch complication:
  `com.chans.patrickface.companion.watchkitapp.complications`

All four signed bundles use
`group.com.chans.patrickface.shared`. The watch Info.plist declares:

- `WKCompanionAppBundleIdentifier = com.chans.patrickface.companion`
- `WKWatchOnly = false`
- `WKRunsIndependentlyOfCompanionApp = true`

That last value preserves the prototype's ability to work without an installed
or reachable iPhone app.

`PatrickCompanion.xcodeproj` now contains a real `PBXFileReference` to
`../PatrickFace.xcodeproj`, a remote target dependency, a remote product proxy,
and an `Embed Watch Content` copy phase. The workspace still opens both
projects. For the declared Xcode 16 project format, the generated-style embed
destination is `$(CONTENTS_FOLDER_PATH)/Watch` (`dstSubfolderSpec = 16`).

If a newer Xcode explicitly reports that the watch product must be embedded as
a Foundation extension under `PlugIns`, let that Xcode migrate the copy phase,
then update both validators and the built-product assertion in
`tools/verify_companion_on_mac.sh` together. Do not silently change the
destination without a successful install/archive check.

## Collision-free watch protocol

Only these integration files are members of the watch app target:

- `iOSCompanion/WatchIntegration/PatrickWatchWire.swift`
- `iOSCompanion/WatchIntegration/PatrickWatchReceiver.swift`

Do **not** add `Shared/PatrickModels.swift` to the watch target. Its
`PatrickTheme` would collide with `PatrickFace/PatrickShared.swift`.
`PatrickWatchWire` nests every protocol DTO and maps:

- `cel-1999` → watch `.cel`
- `faithful-3d` → watch `.clay`

The receiver decodes protocol version 1 at transport key
`patrick.envelope.v1`, keeps the newest 100 message IDs, ignores duplicate and
stale state, returns acknowledgement envelopes, and supports:

- reachable `sendMessageData`
- durable `transferUserInfo`
- latest-state `updateApplicationContext`

Queued and application-context commands receive a separately delivered
acknowledgement when possible. Watch snapshots preserve the latest sleep,
preview, timer, and revision state; a local watch theme change increments the
revision and sends the resulting snapshot to iPhone.

`PatrickAppModel` owns the receiver callbacks. `PatrickFaceView` applies
automatic/on/off sleep mode and normal/sleeping/low-battery/charging preview
overrides while retaining physical battery, Focus, and night behavior. The
`open-watch-face` command activates the existing in-app face; it does not and
cannot select an Apple system watch face.

The watch privacy manifest is:

`PatrickFace/PrivacyInfo.xcprivacy`

It is copied into both the watch app and complication bundles and declares the
App Group (`1C8F.1`) and app-local fallback (`CA92.1`) UserDefaults reasons.

## Deterministic Mac gate

From `iOSCompanion/` on a Mac with Xcode and simulator runtimes installed:

```bash
bash tools/verify_companion_on_mac.sh
```

The script runs both Python validators, lints all property lists, checks the
companion/independence keys and App Group, builds the standalone watch scheme,
builds the iPhone workspace with its remote watch dependency, inspects the
three embedded products and their built bundle IDs, selects an available
iPhone simulator (or uses `IOS_TEST_DEVICE_ID`), and runs
`PatrickCompanionTests`.

## Irreducible signed-device steps

1. Register the four bundle IDs above and
   `group.com.chans.patrickface.shared` in the Apple Developer portal.
2. Select the same Team for the iPhone app, widget, watch app, and complication;
   refresh profiles and confirm App Groups on every signed target.
3. Install the `PatrickCompanion` scheme on a paired physical iPhone/Watch and
   confirm the watch app is recognized and offered as its companion.
4. Test theme, sleep, preview, timer, and open-face commands while reachable.
5. Suspend/terminate each side and test user-info queue and application-context
   delivery in both directions; verify deduplication and acknowledgement text.
6. Remove or disconnect the iPhone app and confirm the watch UI, interactions,
   complication, and local theme selection remain useful.
7. Exercise every App Shortcut and an NFC Personal Automation.
8. Archive with signing, run Validate App, inspect embedded entitlements and
   privacy manifests in the archive, then perform a TestFlight install.
