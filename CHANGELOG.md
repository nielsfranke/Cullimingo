# Changelog

All notable user-facing changes to Cullimingo. The format loosely follows
[Keep a Changelog](https://keepachangelog.com/); dates are `YYYY-MM-DD`.

## 1.2.6 — 2026-07-14

### Fixed
- **Loupe analysis overlays broken since 1.2.4:** the histogram, clipping
  warning and focus peaking silently showed nothing — the sped-up native
  decode disposed a buffer the engine had already disposed, and the resulting
  error killed the analysis unseen. Decode failures are now logged and fall
  back to the (slower) Dart decoder instead of breaking the overlays.

## 1.2.5 — 2026-07-14

### Changed
- **Slim status bar instead of the big export button:** the full-width
  "Export N Photos" bar is now a compact status bar — photo, filter and
  selection counts on the left ("12 of 165 photos · 2 selected"), a small
  Export button on the right ("Export 2 selected" / "Export 165 photos",
  still ⌘/Ctrl-S). Roughly half the height, and the grid gets the room.

## 1.2.4 — 2026-07-14

### Added
- **Auto-open Import on card insert:** inserting a memory card now opens the
  Import dialog directly, preselected on the card (previously it only showed a
  "card detected" notice). Opt out in Settings → General → Ingest.

### Changed
- **Sticky loupe overlays:** the histogram, clipping warning and focus peaking
  now stay on across photos, loupe sessions and app restarts until you turn
  them off — like the filmstrip.

### Fixed
- **Loupe overlays appear much faster:** the histogram / clipping / focus
  peaking analysis now decodes natively at a bounded size instead of running a
  pure-Dart decode over the full preview (which took seconds on big files, and
  far longer once zoomed into the full-resolution source). Toggling another
  overlay on the same photo reuses the already-decoded pixels.

## 1.2.3 — 2026-07-08

### Added
- **RAW-only filename selection:** the *Find photos by filename* (⌘F) and
  *Import selection list* dialogs now offer an **"Only RAWs (skip JPEG twins)"**
  option. When a pasted or imported name matches both a RAW and its JPEG
  sibling, only the RAW is selected; a JPEG with no RAW twin is still selected.
  The option starts checked when the grid is already filtered to RAW-only or
  hiding JPEG pairs, so a RAW+JPEG card selects just the RAWs from a file list.

## 1.2.2 — 2026-07-07

### Added
- **Live filename search:** a search box in the filter bar that filters the
  grid as you type — by any part of the filename (extension included, so
  `DSC_004` and `jpg` both match).
- **RAW / JPEG file-type filter:** show all files, only RAW, or only JPEG —
  offered when a folder mixes both.
- **RAW-only import:** an "Include JPEGs" toggle in the Import dialog, so a
  RAW+JPEG card can be brought in as RAW only.
- **Nested ContactSheet sub-galleries:** name a new gallery inline in the
  picker, and use each row's "+" to nest another level — a whole chain (e.g.
  *Shoot › Day 1 › Selects*) is created when you Send, with the upload landing
  in the deepest one.
- **Apply-marks-to-bracket toggle** is now a checkable entry in the ⋮ menu, so
  it's reachable without opening Settings.
- **Import date bulk actions:** "Select all" / "Clear" for the per-day chips,
  which also label today and yesterday (e.g. *Today · Jul 7 · 24*).

### Changed
- **Tidier filter bar:** the situational filters (keyworded, needs-caption,
  bursts, hide-JPEG, stack-brackets, file-type) now live in two grouped
  dropdowns — *Metadata* and *Grouping* — so the core cull filters stay inline
  and easy to scan.
- **Instant "Include videos" toggle** in Import — it re-filters the cached scan
  instead of re-scanning the whole card.
- **The Import Job-name field** only appears when the naming pattern actually
  uses it, and sits below the name builder so it reads in context.

### Fixed
- **Import no longer hangs on "Scanning…"** for a card with a macOS-protected
  `.Trashes` (seen on a DJI microSD): the scan skips unreadable entries and
  finishes over the real media files.
- **The ⋮ overflow menu can be clicked again to close it** (its button stayed
  put but ignored the second click before).

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
