# watchOS feasibility notes

Verified 2026-09-23 against vendor documentation. This prototype is deliberately a watchOS app experience, not a claim that third-party code can install a new system watch face.

## Hard platform boundaries

- Third-party developers cannot replace Apple’s native watch-face renderer with an arbitrary app. The supported route to the system face is a WidgetKit complication and, where useful, a shared configuration of an Apple-provided face. The full-screen source in this folder is therefore an interactive watch app/prototype.
- SwiftUI `Canvas` is available on watchOS. `TimelineView` is the appropriate time-based driver: use the timeline context’s date, because Always On can request future entries, and inspect cadence / `isLuminanceReduced` instead of assuming foreground frame rates.
- Apple advises stopping subsecond animation and showing a static/final pose when inactive or in Always On. The prototype’s active tier targets 30 fps, Always-On removes ambient motion and updates at minute cadence in Swift, and low power falls back to a five-second foreground schedule with a static character.
- `ProcessInfo.processInfo.isLowPowerModeEnabled` plus `NSProcessInfoPowerStateDidChange` is the public low-power hook used by the Swift source.
- Digital Crown input is public through SwiftUI’s `digitalCrownRotation`; haptics are public through `WKInterfaceDevice.play`. Haptics do nothing in normal background/inactive state and should not be fired rapidly.
- SpriteKit is supported on watchOS through `WKInterfaceSKScene`. `SKView` is for other Apple platforms, and `SKRenderer` is unavailable on watchOS.

## Live2D / Lottie conclusion

Live2D’s official Cubism platform table lists iOS, macOS, Android, Windows, Linux, Web, and selected consoles, but does **not** list watchOS. Cubism’s native C++ code could theoretically be ported by an experienced engine team, but that would be an unsupported platform port with renderer/toolchain, binary-size, energy, maintenance, licensing, and review risk. This lab does not link or claim official Cubism support.

The native substitute implemented here is intentionally small:

1. Named layer anchors come from a JSON manifest.
2. Arms are bones whose base rotations are recalculated from time every frame.
3. Body control points form a tiny deformable path mesh.
4. Eyes, face, and shorts are child layers driven by parameters.
5. Clips add bounded offsets whose envelopes are exactly zero at both endpoints.
6. A six-frame clip path demonstrates where a short pre-rendered atlas can handle an art-heavy gesture.

Airbnb’s official Lottie Apple package lists iOS, macOS, tvOS, and visionOS, not watchOS. A rasterized third-party workaround is possible, but it loses much of Lottie’s vector/parameter advantage. Treat it like a frame renderer and evaluate memory and licensing accordingly.

## Method decisions

- **SwiftUI Canvas + layer rig — primary.** Native, interactive, small binary, deterministic timekeeping, and easiest to degrade for Always On.
- **SpriteKit / spritesheet — secondary.** Native via `WKInterfaceSKScene`; a good fit for brief complex gestures. Pause when not visible and keep decoded frames watch-sized.
- **Custom path mesh — selective.** Native and highly parameterized. Keep vertex count and redraw cadence low; this prototype uses ten body control points.
- **Live2D Cubism — do not ship directly without a dedicated port investigation.** No official watchOS target.
- **Video, GIF, Lottie, pre-rendered 3D — brief fallback only.** Easy visual fidelity, weak interaction and blending, potentially higher memory/energy. Pre-rendered 3D is viable as a small atlas, not as evidence of a live 3D rig.

## Sources

- Apple, “Updating watchOS apps with timelines”: https://developer.apple.com/documentation/watchos-apps/updating-watchos-apps-with-timelines
- Apple, “Designing your app for the Always On state”: https://developer.apple.com/documentation/watchos-apps/designing-your-app-for-the-always-on-state
- Apple, `isLuminanceReduced`: https://developer.apple.com/documentation/swiftui/environmentvalues/isluminancereduced
- Apple, `WKInterfaceDevice.play(_:)`: https://developer.apple.com/documentation/watchkit/wkinterfacedevice/play(_:)
- Apple, “Choosing a SpriteKit Scene Renderer”: https://developer.apple.com/documentation/spritekit/choosing-a-spritekit-scene-renderer
- Apple, “Watch faces” HIG: https://developer.apple.com/design/human-interface-guidelines/watch-faces
- Apple, “watchOS apps”: https://developer.apple.com/documentation/watchos-apps
- Live2D, “Platform support status”: https://docs.live2d.com/en/cubism-sdk-manual/platform/
- Airbnb Lottie, supported platforms: https://github.com/airbnb/lottie/blob/master/ios.md
