# Patrick Face delivery theme pack

Production-ready static theme assets built from the corrected clean Season-1 2D layers and smooth cel-derived Toon-3D layers in the PatrickFace project.

## Start here

1. Read `SETUP-GUIDE.md`.
2. Use `MANIFEST.json` or `MANIFEST.csv` to select an exact device size.
3. Review `contact-sheets/` before transferring files.
4. Read `reports/validation-report.txt` for the final file, image, and audio checks.

## Package layout

- `wallpapers/iphone/`: native-resolution Lock and Home Screen PNGs for all four iPhone 16 display classes.
- `wallpapers/standby/`: native landscape photo sources for those displays.
- `watch/photo-faces/`: Series 10/11 and Ultra-class Photos-face fallbacks with top/bottom time-safe variants.
- `shortcuts-icons/1024/`: 20 square Home Screen icon sources plus `icon-index.json`.
- `widgets/`: iPhone WidgetKit/photo-widget, Lock Screen accessory, Apple Watch Smart Stack, and complication artwork.
- `sounds/wav/`: 48 kHz stereo PCM masters.
- `sounds/m4a/`: AAC-LC delivery copies for Shortcuts.
- `qr/`: official Shortcuts URL-scheme launchers and payload text.
- `source-layers/`: preserved approved layers and reusable transparent 10:10 composites.
- `contact-sheets/`: visual QA overviews.
- `tools/`: reproducible build and validation scripts.
- `reports/`: machine-readable and human-readable validation output.

## Important boundaries

- StandBy landscape files are Photos/widget sources, not a hidden StandBy wallpaper format.
- Watch Photos-face files are static. Widget/complication images need a signed WidgetKit app.
- Shortcuts personal automations must be created on each iPhone and do not sync to other devices.
- The sounds are original, non-vocal synthesis and do not imitate any voice.
- A passive NFC tag can trigger software. It cannot power case LEDs; powered lighting is a separate hardware project.
- A tag permanently inside the same phone’s fitted case is not a reliable self-trigger. Use an external tag for the supported workflow.

## Rebuild policy

`tools/build_theme_pack.py` refuses to replace existing media outputs. It creates files but never deletes package or source files.
