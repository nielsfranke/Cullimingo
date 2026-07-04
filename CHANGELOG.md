# Changelog

All notable user-facing changes to Cullimingo. The format loosely follows
[Keep a Changelog](https://keepachangelog.com/); dates are `YYYY-MM-DD`.

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
