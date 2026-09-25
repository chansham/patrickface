# Patrick iPhone Companion

Production-oriented iOS 17 SwiftUI companion project for the existing Patrick
watch app. The apps remain separate projects, but the iPhone project now holds
an explicit reference, dependency, and Embed Watch Content phase for the watch
product. No existing file was deleted.

This is not a system-wide theme replacement and it does not install a custom
Apple Watch system face. “Watch face” in this project always means the
full-screen Patrick experience inside the Patrick app.

## Project targets

- `PatrickCompanion`: iPhone SwiftUI app, theme control center, local sound cue,
  App Intents, WatchConnectivity transport, deep links, and Live Activity
  lifecycle.
- `PatrickWidgets`: WidgetKit Home Screen and Lock Screen widgets, StandBy-ready
  small widget, plus the ActivityKit Lock Screen/StandBy and Dynamic Island
  presentations.
- `PatrickCompanionTests`: contract, deep-link, persistence, and message
  deduplication tests.

The deployment target is iOS 17.0. Xcode 16 or newer is recommended.
`PatrickFaceSuite.xcworkspace` opens the paired projects;
`PatrickCompanion.xcodeproj` also resolves the referenced watch project when
opened by itself.

## Included behavior

The control center selects **1999 CEL** or **Faithful 3D** and previews normal,
sleeping, low-battery, and charging states on a true black background. Sleep mode
supports automatic, explicit on, and explicit off behavior.

Watch synchronization uses a versioned Codable envelope with UUID
deduplication. Reachable commands use `sendMessageData`; unavailable peers use
queued user-info delivery; the newest state also uses application context. The
watch app remains authoritative for watch-only signals such as battery, Focus,
and frontmost state.

Four App Intents are exposed as App Shortcuts:

- Set Patrick Theme
- Set Patrick Sleep Mode
- Play Patrick Theme Sound
- Open Patrick Watch Face

An NFC tag can trigger any of these by using a user-created **Shortcuts Personal
Automation → NFC → Run App Shortcut**. The app intentionally does not request
Core NFC permission: it does not passively scan, intercept, or silently act on
arbitrary tags.

`patrickface://` deep links use the same route names as watch commands:

- `patrickface://control-center`
- `patrickface://set-theme?value=cel-1999`
- `patrickface://set-theme?value=faithful-3d`
- `patrickface://set-sleep-mode?value=automatic`
- `patrickface://play-theme-sound`
- `patrickface://open-watch-face`
- `patrickface://timer`

The Patrick timer starts a local Live Activity. Its widget extension supplies a
Lock Screen presentation, all Dynamic Island regions, and a layout that scales
for StandBy.

## Mock and demo mode

Run the shared `PatrickCompanion-Demo` scheme to set `PATRICK_DEMO=1`, or enable
**Demo watch** on the Status tab. Commands then follow the real envelope path and
receive a delayed local acknowledgement without requiring an iPhone/Watch pair.
SwiftUI previews also use the same production views and approved assets.

Demo mode proves UI and local command flow only. It does not prove
WatchConnectivity scheduling, entitlements, ActivityKit authorization, widget
refresh policy, Dynamic Island hardware behavior, or signing.

## Privacy and persistence

The App Group `group.com.chans.patrickface.shared` stores only theme, visual
state, sleep preference, demo preference, timer state, pending foreground
actions, revisions, and recent message IDs. There is no account, cloud sync,
analytics SDK, advertising SDK, location, contacts, microphone recording, or
health-data access. The generated theme cue is synthesized locally and records
nothing.

Both the app and widget use the same App Group entitlement. The standard
defaults fallback exists only so previews and unsigned development runs remain
inspectable; signed production builds must provision the App Group.
`Resources/PrivacyInfo.xcprivacy` declares the App Group (`1C8F.1`) and
development fallback (`CA92.1`) UserDefaults required reasons, no tracking, and
no collected data for both bundles.

## Artwork

`tools/sync_approved_assets.py --write` copied six PNGs byte-for-byte from the
approved watch asset catalog:

- the 1999 body, hour arm, and minute arm
- the faithful 3D body and arm
- the approved Patrick app icon, reused as the iOS marketing icon

Hashes and source paths are in `Resources/asset-provenance.json`. Charging glow,
sleep “Z”, battery/bolt badges, and all black presentation surfaces are clearly
derived at runtime in SwiftUI; no replacement character art is embedded. The
hour and minute arm images share one exact central hub and differ only in
length/angle; no theme-specific shoulder pivots or bent-arm poses are used.

## Official platform limits

- Public Apple APIs do not let this app replace the iOS appearance, install or
  select a third-party system watch face, bypass watchOS frontmost/Always-On
  policy, or guarantee launching an arbitrary watch app from iPhone.
- “Open Patrick Watch Face” opens the custom iPhone face and sends a best-effort
  route request to the paired Patrick watch app. The watch may process it only
  when watchOS allows.
- WatchConnectivity is opportunistic. Immediate delivery requires reachability;
  queued context has no user-visible delivery deadline.
- The source/project bundle hierarchy and embed dependency are configured, but
  official pairing still depends on matching Developer Portal registrations,
  provisioning profiles, signing, and a physical paired-device test.
- Independent watch apps may use companion synchronization, but must not depend
  on the iPhone as their primary data source.
- Widget timelines, StandBy placement, Live Activity visibility, and Dynamic
  Island presentation are controlled by the user and the system.
- Dynamic Island requires supported hardware. StandBy also depends on system
  configuration, charging, and orientation.
- App Intents are available to Shortcuts, Siri, Spotlight, and supported system
  surfaces. NFC Personal Automations remain subject to the user's Shortcuts
  settings and any confirmation the OS requires.
- iOS can restrict or silence foreground/background audio. The sound intent
  opens the app before playing its short local cue.

## Windows structural validation

From this directory:

```powershell
python tools/sync_approved_assets.py
python tools/validate_structure.py
python ../tools/validate_watch_project.py
python -m compileall -q tools
```

These checks parse plists, entitlements, schemes, workspace XML, asset JSON,
PNG headers, provenance, PBX target declarations, source memberships, and basic
Swift delimiter shape. Windows cannot run Apple's Swift SDK, `xcodebuild`,
`actool`, simulator tests, provisioning, or code signing.

## Remaining Mac-only steps

1. Open `PatrickFaceSuite.xcworkspace` in Xcode 16 or newer (or open
   `PatrickCompanion.xcodeproj` for iPhone-only work) and accept only intentional
   project-format updates.
2. Select one Apple Developer team for the iPhone app, widget, watch app,
   complication, and tests.
3. Register these bundle IDs and the shared App Group in the developer portal,
   then refresh provisioning profiles:
   - `com.chans.patrickface.companion`
   - `com.chans.patrickface.companion.widgets`
   - `com.chans.patrickface.companion.watchkitapp`
   - `com.chans.patrickface.companion.watchkitapp.complications`
   - `group.com.chans.patrickface.shared`
4. Build for an iOS 17+ simulator, run `PatrickCompanionTests`, and inspect all
   Swift concurrency and App Intent metadata diagnostics.
5. Run the app and widget previews, then add every supported widget family and
   start/end a Live Activity. Check Lock Screen, StandBy, and each Dynamic Island
   state on suitable devices.
6. Run `bash tools/verify_companion_on_mac.sh`; it builds both schemes, verifies
   the embedded watch/complication/widget products, and runs contract tests.
7. Test reachable, queued, and application-context messages in both directions
   on a physical paired iPhone/Apple Watch,
   then test all four App Shortcuts and an NFC Personal Automation.
8. Archive, validate, review privacy labels/capabilities, and sign for TestFlight
   or App Store distribution.

Compilation, Apple SDK validation, provisioning, signing, paired-device
delivery, and distribution are pending until those Mac steps are completed.
