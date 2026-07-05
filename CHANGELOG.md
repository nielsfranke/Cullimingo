# Changelog

All notable user-facing changes to Cullimingo. The format loosely follows
[Keep a Changelog](https://keepachangelog.com/); dates are `YYYY-MM-DD`.

## 1.1.0 — 2026-07-05

### Added
- **Export beside the originals:** the export dialog can now write each photo
  into a subfolder next to its own source file (default `Exports`), alongside
  the existing "choose one folder" mode. Blank subfolder writes straight
  alongside.
- **ContactSheet from the right-click menu:** when ContactSheet is set up, the
  thumbnail (and loupe) context menu offers **Send to ContactSheet…** and
  **Pull marks from ContactSheet…**, opening the dialog straight into the right
  mode.

### Changed
- **Calmer first launch:** the welcome dialog now shows just the essential keys
  to get culling — move, rate, pick/reject, colour, select, loupe — with a note
  to press `?` any time for the full list, instead of dumping the whole keymap.

### Fixed
- **Export naming beside originals:** identically-named files in different
  source folders no longer pick up a needless `_2` suffix — they land in
  separate destinations and never actually collide.

## 1.0.2 — 2026-07-04

### Fixed
- **Window size on dual-monitor macOS:** the remembered window height was
  clamped to the shorter display when reopening. The window now restores at its
  full saved size on the correct monitor.

## 1.0.1 — 2026-07-04

### Changed
- **Smoother grid zoom:** the thumbnail-size slider now resizes the grid live
  around the photo you're looking at, without the flicker, jumping, or
  on-release jump the first release had.

## 1.0.0 — 2026-07-04

- Initial public release: fast, keyboard-driven photo culling for macOS and
  Linux — ingest, cull (rate / flag / colour), filter, export and hand-off,
  with IPTC captioning and XMP round-trip to Lightroom / Capture One.
