# Patrick Face theme pack — retired static delivery

Historical static outputs built from earlier Season-1 2D and Toon-3D layers. This delivery was retired on 2026-09-27 when the animation direction changed to actual expression and pose frames. It is retained for provenance and is not the new animation package. Its lifecycle is `retired-static-delivery`, with `currentApproval: false`.

## Historical package reference

1. Read `SETUP-GUIDE.md`.
2. Use `MANIFEST.json` or `MANIFEST.csv` to select an exact device size.
3. Use `contact-sheets/` to inspect the old static outputs.
4. `reports/asset-cleanup-validation.txt` records the earlier file, image, and audio checks. The original `validation-report.*` files are historical evidence. These reports do not validate or approve the new animation.

## Package layout

- `wallpapers/iphone/`: native-resolution Lock and Home Screen PNGs for all four iPhone 16 display classes.
- `wallpapers/standby/`: native landscape photo sources for those displays.
- `watch/photo-faces/`: Series 10/11 and Ultra-class Photos-face fallbacks with top/bottom time-safe variants.
- `shortcuts-icons/1024/`: 20 square Home Screen icon sources plus `icon-index.json`.
- `widgets/`: iPhone WidgetKit/photo-widget, Lock Screen accessory, Apple Watch Smart Stack, and complication artwork.
- `sounds/wav/`: 48 kHz stereo PCM masters.
- `sounds/m4a/`: AAC-LC delivery copies for Shortcuts.
- `qr/`: official Shortcuts URL-scheme launchers and payload text.
- `source-layers/`: retained historical source layers and static 10:10 composites. Three arm references were refreshed during cleanup; the existing compositions were not regenerated. Source snapshots and derived outputs therefore describe different historical revisions.
- `contact-sheets/`: visual QA overviews.
- `tools/`: retired build source and historical-package validation scripts.
- `reports/`: machine-readable and human-readable validation output.

## Important boundaries

- StandBy landscape files are Photos/widget sources, not a hidden StandBy wallpaper format.
- Watch Photos-face files are static. Widget/complication images need a signed WidgetKit app.
- Shortcuts personal automations must be created on each iPhone and do not sync to other devices.
- The sounds are original, non-vocal synthesis and do not imitate any voice.
- A passive NFC tag can trigger software. It cannot power case LEDs; powered lighting is a separate hardware project.
- A tag permanently inside the same phone’s fitted case is not a reliable self-trigger. Use an external tag for the supported workflow.

## Rebuild policy

`tools/build_theme_pack.py` is disabled before image dependencies or filesystem setup. It refuses every generation request, including `--overwrite` and custom output arguments; `--status` reports retirement metadata without writing files. Rebuilding this package cannot produce the new expression/pose animation. The `approved` suffix in retained legacy filenames is historical naming only and must not be interpreted as current approval.

The retained native app has its own asset-catalog copies. This retirement does not replace or remove those files. Any native adoption of the new animation needs a separate implementation and device validation.

The project-wide audit and removal evidence are in `../../docs/ASSET-AUDIT.md` and `../../docs/asset-audit.json`.
