# Patrick Apple Watch Modular Style Library

This directory is a self-contained, independently generated asset system. It does not modify the parallel clean Season-1 master workstream.

## Core contract

- Every component is a transparent, full-registration canvas.
- Source masters: `1024 × 1024` RGBA PNG.
- watchOS tier: `256 × 256` optimized RGBA PNG.
- Both arm assets point to 12 o'clock and rotate around source pixel `[512, 500]`.
- Rotation: `minute × 6°`; `(hour mod 12) × 30° + minute × 0.5°`.
- Composite order: feet → body → clothing → face → arms → accessories → overlays.

## Structure

- `assets-src/` — high-quality source PNG masters.
- `assets-watchos/` — size-conscious runtime PNGs.
- `spec/rig-spec.json` — canvas, pivots, anchors, layer order, and morphology contract.
- `manifest.json` — every file, bounds, dimensions, byte size, SHA-256, provenance, and style notes.
- `previews/` — contact sheets, watch mockups, rig board, transparency proof, and library status board.
- `generate_library.py` — deterministic procedural redraw source.

## Production note

The library is ready for visual selection and integration prototyping. Before shipping, reconcile the chosen family against the separate clean Season-1 master, tune shoulder occlusion, test OLED/Always-On behavior on device, and complete rights review.
