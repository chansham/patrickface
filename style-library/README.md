# Patrick style library — retired research

This directory preserves earlier procedural style and layer experiments. It was retired on 2026-09-27 when the animation direction changed to actual expression and pose frames. It is not the active animation library and is not ready for production integration.

All six families and 240 component PNGs are retained for provenance and research. Their current lifecycle is **retired-research**, with `currentApproval: false`. Earlier technical validation, old review labels, and descriptive names such as “animation model sheet” do not establish approval or animation readiness. Existing file hashes and the historical integrity report are preserved.

## Historical layer contract

- Every component is a transparent, full-registration canvas.
- Source masters: `1024 × 1024` RGBA PNG.
- watchOS tier: `256 × 256` optimized RGBA PNG.
- Both arm assets point to 12 o'clock and rotate around source pixel `[512, 500]`.
- Rotation: `minute × 6°`; `(hour mod 12) × 30° + minute × 0.5°`.
- Composite order: feet → body → clothing → face → arms → accessories → overlays.

## Structure

- `assets-src/` — high-quality source PNG masters.
- `assets-watchos/` — historical reduced-size exports; the folder name does not make them current runtime assets.
- `spec/rig-spec.json` — canvas, pivots, anchors, layer order, and morphology contract.
- `manifest.json` — every file, bounds, dimensions, byte size, SHA-256, provenance, and style notes.
- `previews/` — contact sheets, watch mockups, rig board, transparency proof, and library status board.
- `generate_library.py` — retired procedural redraw source. Its CLI refuses generation; `--status` reports retirement metadata without writing files.

## Current status

The new expression/pose work lives under `../animation/` and has its own review status. These old components must not be copied into it or relabeled as the new animation. The retained native app still uses its separate historical asset-catalog copies until an explicit native migration is implemented and tested.
