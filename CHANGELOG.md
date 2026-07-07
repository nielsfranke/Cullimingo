# Changelog

All notable user-facing changes to Cullimingo. The format loosely follows
[Keep a Changelog](https://keepachangelog.com/); dates are `YYYY-MM-DD`.

## 1.2.1 — 2026-07-07

### Added
- **Apply marks to bracket:** a right-click action that copies the focused
  frame's rating, flag and colour onto the rest of its exposure bracket — a
  one-shot alternative to the always-on "apply marks to the whole bracket"
  setting, shown only on a frame that belongs to a bracket.
- **Click empty grid space to clear the selection** — a left-click off any
  thumbnail (the padding, the gaps, or below the last row) now deselects.

### Changed
- **Tighter right-click menu:** shorter rows and thinner dividers so the full
  menu fits on screen without running off the top or bottom.

### Fixed
- **Dragging a multi-selection out keeps every photo:** starting a drag-out on
  a selected thumbnail no longer collapses the selection to just that one — all
  selected files are carried to Finder/Desktop. A plain click still selects a
  single photo.
- **Dragging a collapsed exposure bracket carries all its frames**, not just
  the visible reference — the collapsed cell stands in for the whole stack.
- **ContactSheet actions show reliably in the right-click menu** once a
  connection is configured; they could be missing from the first menu opened
  after launch.

## 1.2.0 — 2026-07-06

### Added
- **Filter import by capture date:** the import dialog now shows a day-per-chip
  breakdown when a card holds more than one day's photos, so leftovers from an
  old shoot don't get swept in with today's — tap a day to exclude/re-include
  it, no re-scan needed.
- **Selection-aware Delete… in the right-click menu:** move the current
  selection to the Trash (with its `.xmp` sidecars) after a confirmation,
  without leaving the grid.

### Fixed
- **Right-click no longer collapses a multi-selection:** right-clicking a
  photo that's part of an existing selection keeps the whole selection instead
  of narrowing it down to just that photo before the context menu opens.
- **"Open in library" opens the actual imported folder:** after an import with
  a dated-shoot naming template, the completion screen now opens the
  sub-folder the photos landed in, not the whole destination root.
- **A failing SD card/reader no longer hangs the app:** card detection and
  folder scanning tolerate an unresponsive device — the app stays responsive
  and the scan skips the stuck file instead of hanging forever.

## 1.1.0 — 2026-07-05

### Added
- **Exposure-bracket workflow.** Cullimingo now understands bracketed shots:
  - **Automatic detection** of exposure brackets from EXIF, with a
    shutter-aware time gap that keeps long-exposure + NR frames together and
    splits back-to-back brackets. The scan now also reads exposure compensation
    and shutter speed (with a LibRaw fallback that recovers them from Fuji
    `.RAF` files the pure-Dart reader can't open).
  - **Collapse to one frame:** a **Stack brackets** filter chip (shown only when
    the folder has brackets) hides the ±EV siblings so the grid shows one cell
    per bracket — its reference (normal-exposure) frame, badged with the frame
    count.
  - **Expand selection to bracket (`G`):** after client picks come back (a
    ⌘F paste-list or a ContactSheet pull), grow the selection to every ±EV
    sibling before export. Optional settings auto-propagate ratings/flags/
    colours to the whole bracket and auto-expand pulled-in client picks.
  - **Manual corrections:** **Stack as bracket** / **Remove from bracket** in
    the right-click menu override detection, persist, and round-trip through the
    XMP sidecar so they survive re-import.
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
