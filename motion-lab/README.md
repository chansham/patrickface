# Patrick Motion Lab

An isolated motion prototype under `PatrickFace/motion-lab`. It does not write to `comparison-season1-3d` or `style-library`.

## Run the browser lab

From this folder:

```powershell
python -m http.server 4173
```

Open `http://127.0.0.1:4173/`. No package install or network dependency is required.

Run deterministic motion checks:

```powershell
npm test
```

The browser also exposes `window.__patrickMotionLab` for inspection. The **Run return test** button checks three fixed clock cases, then plays the visible gesture and verifies its zero-error endpoint.

## Run the watchOS app

On a Mac with Xcode 16 or later:

1. Open `watchOS/PatrickMotionLab.xcodeproj`.
2. Select the shared `PatrickMotionLab` scheme.
3. Choose a watchOS 10+ simulator and Run.

Watch controls:

- Tap the character: bounce plus `WKInterfaceDevice` click haptic.
- Rotate the Digital Crown: expression and shorts-color parameter.
- Long press: six-frame gesture clip.
- Bottom controls: arm gesture, awake/focus/sleep cycle, normal/low-battery/charging cycle, frame clip, rig overlay, and exact-return test.
- Automatic behavior: continuous breathing, attention motion, periodic blink, and a periodic zero-ended arm gesture.

The app uses `TimelineView` and its supplied date for clock calculations. In Always-On/inactive state it removes ambient motion and uses a static pose; Low Power Mode is observed through `ProcessInfo`.

## State and blending contract

Timekeeping has absolute priority. Each frame starts from freshly calculated hour/minute angles. Motion is then composed in this order:

1. Time targets — authoritative.
2. Platform safety — Always-On and low-power cadence/pose reductions.
3. Direct interaction — tap and crown.
4. Mode — focus, sleep, low battery, charging.
5. Idle/frame clips.
6. Ambient breathing, blink, and attention.

The idle arm gesture is an additive offset multiplied by a squared-sine envelope. The envelope is exactly zero at and after 1.8 seconds; no gesture state can become the new timekeeping base.

## Anchor-manifest integration

The browser tries `../style-library/patrick-anchor-manifest.json` first, then `patrick-anchor-manifest.fallback.json`. The watch target bundles its local copy because a watch app cannot read a sibling development folder at runtime.

When the shared master exists, run:

```powershell
.\sync-shared-anchors.ps1
```

The script validates required anchor names before copying into this folder only. Required anchors are `characterRoot`, `hourArmPivot`, `minuteArmPivot`, and `faceRoot`.

## Implemented now

- Real continuous hour and minute calculations, including seconds.
- Breathing mesh deformation.
- Blink and moving eye attention.
- Periodic/manual arm gesture with exact return.
- Tap bounce and browser/native haptic hooks.
- Crown-driven expression and outfit parameter.
- Smooth awake/focus/sleep transition.
- Low-battery slump and charging pulse.
- Six-frame browser sprite atlas and Swift frame-loop slot.
- Ten-point custom body mesh plus named layer/bone rig.
- Active, Always-On, and low-power performance tiers.
- Deterministic browser tests and in-app hand-return verification.
- Local anchor manifest with shared-manifest integration contract.

## Deferred until final art

- Replacing procedural vector placeholders with approved separated body, eye, lid, mouth, shorts, and arm masters.
- Artist-authored mesh weights around the face/shorts seams.
- Final sprite atlas for a complex character gesture; the current atlas is motion FX that proves playback and lifecycle.
- Device profiling, final haptic tuning, signed build, app icon, complication/WidgetKit target, and App Store submission assets.
- A real shared manifest in `style-library`; that folder was intentionally left untouched.

See `TECHNICAL-NOTES.md` for current platform evidence and the Live2D conclusion. The in-browser feasibility matrix is the concise visual comparison.
