# Changelog

All notable user-facing changes to Cullimingo. The format loosely follows
[Keep a Changelog](https://keepachangelog.com/); dates are `YYYY-MM-DD`.

## 1.6.0 — 2026-10-09

### Added
- **Easier Linux updates (GitHub #13):** the AppImage now carries update
  info, so AppImageUpdate or Gear Lever can update it in place and download
  only what changed. A Flatpak manifest (`flatpak/`) is in the repo, ready for
  Flathub; inside the Flatpak, Move to Trash, card auto-mount, video posters,
  "Send to" editors and Show in File Manager reach the host system.

## 1.5.0 — 2026-10-06

### Added
- **Marks can follow RAW+JPEG pairs:** a new setting (Settings → RAW+JPEG
  pairs, also in the ⋮ menu when the folder has pairs) applies ratings,
  flags, colours and rotation to both files of a pair, so `DSCF8912.RAF` and
  `DSCF8912.JPG` can be culled as one photo. With auto-advance on, one
  keypress moves past the twin to the next shot. Off by default, so each file
  still keeps its own marks unless you turn it on (GitHub #12).
- **Unflagged and Unrated filter chips:** show only photos that are neither
  picked nor rejected, or only photos with no star rating (GitHub #12).
  Unrated and the star threshold switch each other off. Both are saved in
  filter presets.

### Fixed
- **Renaming no longer splits a RAW+JPEG pair:** renaming the RAW now also
  renames its JPEG twin in the same folder, even when *Hide JPEG* or
  another filter keeps the JPEG out of the grid. Before, the JPEG kept its
  old name and was no longer paired with the renamed RAW (GitHub #12).

## 1.4.0 — 2026-10-04

### Changed
- **Import date folders always follow the capture date in the photo's
  EXIF**, not only when `{camera}` is in the naming template. The file date
  is used only when a file has no valid capture date.
- **Reading capture dates is much faster**, for the import scan and for
  opening a folder: only the start of each file is read, in one go, where
  RAWs used to be read a few bytes at a time (a 24 MP NEF took ~0.2 s).
- **The import's backup copy is always verified.** The checksum checkbox now
  only governs the main destination; the backup is read back regardless,
  since a bad backup is otherwise found out on the day it's needed.

### Fixed
- **Mac metadata files on cards and drives are no longer listed as
  photos:** the hidden `._DSC1.ARW` files macOS writes beside every file on
  an exFAT or FAT card or drive, and photos inside a card's `.Trashes`, are
  skipped like any hidden file. Protected system folders such as
  `.Spotlight-V100` no longer count as part of the card that couldn't be
  read.
- **HEIC and Sony HIF photos open on Linux:** the AppImage shipped without an
  HEVC decoder, so these files showed only a placeholder in the grid and the
  loupe. It now bundles one, and a HEIF whose built-in thumbnail can't be
  decoded (Sony `.HIF` on some libheif versions) is decoded in full instead.
  Thanks to heinerjost-dev for the report and sample file.
  ([#10](https://github.com/nielsfranke/Cullimingo/issues/10))
- **A stuck thumbnail recovers in seconds again:** since 1.3.4 a preview that
  hung (e.g. a corrupt RAW) kept its cell spinning and a decode slot blocked
  for a full minute. Only a RAW that actually needs the slow full demosaic now
  gets the long allowance; everything else is reclaimed after 12 s.
  ([#5](https://github.com/nielsfranke/Cullimingo/issues/5))
- **RAWs without a usable embedded preview open faster in the loupe:** the
  grid and loupe sizes now share one demosaic instead of decoding the same
  file again for each size.
  ([#7](https://github.com/nielsfranke/Cullimingo/issues/7))
- **Import tells you when it couldn't read part of the card:** an unreadable
  folder (or a card reader that stalls) used to be skipped silently, and the
  summary still said "Import complete". The dialog now warns before
  importing, the summary lists what couldn't be read and reads "finished
  with issues", and both say not to format the card yet.
- **Refreshing (⌘R) a folder that's only partly readable no longer removes
  photos:** when part of the folder can't be read (a locked sub-folder, a
  stalling card reader), new files are still picked up but nothing is
  removed, and a warning says how many items couldn't be read.
  ([#9](https://github.com/nielsfranke/Cullimingo/issues/9))
- **An interrupted copy no longer leaves half a photo under its real name:**
  import and handoff write each copy to a hidden `.part` file, verify it
  there, and only then give it its name — never replacing a file that's
  already there. A crash or a dropped drive used to leave a truncated file
  that the next import called a conflict and kept, so that photo never
  arrived. A symlink at the destination can no longer redirect a copy
  elsewhere, and two handoffs into one folder can't truncate or delete each
  other's files.
- **Files still being written are held back:** a file changed in the last
  few seconds (a tether, a sync tool, a camera still writing over USB) is
  no longer copied while it's momentarily idle. The summary lists it as
  "still being written"; import again once it has settled.
- **A drive or network share that stops responding no longer freezes the
  import:** a copy that makes no progress for a minute is given up on and
  listed as failed, and Cancel ends the run within a few seconds even when
  a copy is stuck (that file is listed as "cancelled mid-copy").
- **An unplugged destination drive is no longer filled in from the system
  disk:** Cullimingo remembers which drive a destination folder lives on
  and refuses to import or hand off into it when that drive isn't mounted
  — including the empty mount-point folder an unplugged drive leaves
  behind on Linux. A destination folder that has vanished is never
  recreated. If a folder really moved, choose it again. Destinations chosen
  before this update are protected too: a folder on an external drive
  (under `/Volumes`, `/media` or `/run/media`) or on a drive listed in
  `/etc/fstab` is refused while that drive isn't mounted.
- **Leftovers from an interrupted copy are tidied up:** the hidden `.part`
  files a crash or a dropped drive can leave in a destination folder are
  removed on the next import or handoff into that folder.
- **Moving a photo no longer leaves its marks behind:** if its `.xmp`
  sidecar couldn't be copied, the photo used to be moved anyway and reported
  as done, with its rating and labels left in the old folder. The original
  now stays put next to its sidecar, and the result says why.
- **Not enough room? The import doesn't start:** free space is checked per
  drive before anything is copied (main and backup on one drive add up;
  files already there don't count), instead of failing part-way through.
  ([#9](https://github.com/nielsfranke/Cullimingo/issues/9))

## 1.3.5 — 2026-10-02

### Fixed
- **Import no longer hangs on a full or failing destination:** a write error
  (disk full, dropped mount) used to escape the copy, leave truncated files
  behind and keep the dialog on "Importing…" forever. The file now fails with
  its reason, partial copies are removed, and the run finishes.
- **Switching the source while it scans can't import the previous card:**
  Import stays disabled until the new source's scan has finished, and a
  failed scan no longer leaves the old plan importable.
- **Cancelling an import reports what actually happened:** copies already
  running finish and are counted, the summary reads "Import cancelled" with the
  files not copied — not "Import complete". The dialog can no longer be closed
  mid-import by Escape or a click outside it.
- **"Verified" only when it's true:** with checksum verification off, the
  summary says "Copied (not verified)", and the backup option no longer claims
  to be verified.
- **Refreshing (⌘R) an unplugged folder no longer removes its photos:** when
  the folder is gone or lists empty, nothing is removed and a warning says to
  check the card or drive.
- **A file that changes while it's being copied is no longer reported as
  copied:** the copy is discarded and the file listed as failed ("still being
  written?"). A handoff *move* used to delete such an original after keeping a
  stale copy; a move now also always verifies before deleting anything.
- **Copies keep the original's file date**, so re-importing or re-scanning a
  copied folder files photos under their capture day instead of today.
- Impossible EXIF dates (e.g. 31 February from a corrupt camera clock) are
  treated as unknown instead of rolling into the next month; a failed sidecar
  copy shows its reason in the import summary; skipped and failed files no
  longer inflate the import speed readout.

## 1.3.4 — 2026-10-02

### Fixed
- **RAW files without a usable embedded JPEG now render usable previews:** when
  cameras such as the Nikon Z6 III in HLG mode provide only a 160×120 JPEG — or
  no JPEG thumbnail at all — Cullimingo falls back to a LibRaw demosaic for the
  grid, loupe and exports instead of stretching the thumbnail or leaving the
  photo blank. Normal embedded previews remain on the original fast path.
  Previews of such RAWs cached by earlier versions are re-rendered once
  automatically. Files LibRaw can't decode (e.g. Nikon HE/HE\* "TicoRAW")
  keep showing their embedded thumbnail (or the placeholder) instead of a
  noise frame, and a failed decode isn't retried every time the photo scrolls
  back into view.

## 1.3.3 — 2026-10-01

### Fixed
- **"Apply marks to whole bracket" now works in the loupe** (GitHub #4).
  Rating, flagging or colouring a photo in the loupe only marked that frame,
  even with the setting on; it now carries to the whole bracket just like
  marking in the grid. (Compare view stays per-frame on purpose.)
- **RAW+JPEG pairs keep separate ratings, flags and colours** (GitHub #3).
  Both halves of a pair used to share one `DSC1.xmp`, so a re-sync or reopen
  copied the RAW's marks onto the JPEG (and trashing a rejected JPEG took the
  RAW's sidecar with it). The JPEG of a pair now gets its own `DSC1.JPG.xmp`
  (the darktable convention); the RAW keeps `DSC1.xmp` for Lightroom and
  Capture One. Rename, transfer, ingest and reject-delete carry the right
  sidecar along. JPEG marks that were previously written to the shared file
  aren't migrated — re-mark the JPEG once if it should differ from its RAW.

## 1.3.2 — 2026-10-01

### Fixed
- **Linux: opening a folder no longer crashes the app** (GitHub #2). On
  Debian 13 and other distros with a librsvg newer than the one bundled in the
  AppImage, the first GTK file chooser killed the app outright: GTK's SVG icon
  loader bound to our older bundled librsvg and aborted on a missing symbol.
  The AppImage now uses the host's librsvg whenever there is one and falls
  back to its own copy only when there isn't.

## 1.3.1 — 2026-08-19

### Fixed
- **Dragging a multi-selection out of the window keeps every photo:** pressing
  an already-selected thumbnail and dragging it to Finder (or just dragging to
  scroll) collapsed the selection to the pressed photo, so only that one file
  was dragged out. The deferred collapse now drops as soon as the press moves,
  and a press whose release never comes back (the native drag takes the
  pointer) can no longer be cashed in by a later click or right-click.
- **Culling with a filter on no longer loses your place:** un-picking (or
  otherwise marking) a photo so it drops out of the active filter used to
  snap the fullscreen viewer and the grid back to the first photo. Focus now
  moves to the photo that took its slot — the previous one when it was the
  last — so a filtered cull run carries on where it was.

## 1.3.0 — 2026-07-16

### Changed
- **Marking got much cheaper in big folders:** burst, RAW+JPEG and bracket
  grouping no longer recompute on every rating/flag/colour keystroke (they
  only depend on capture time, names and exposure data), and exports now run
  through a small pool of long-lived render workers that load LibRaw once
  instead of once per file — a 500-RAW export used to spawn 500 isolates.

### Fixed
- **Externally changed photos now refresh their previews:** a file
  overwritten in place (re-exported from an editor, re-copied from a card)
  kept showing its old RAM-cached thumbnail until restart. Folder refresh
  (⌘R and the background resync) now detects moved mtimes, updates the row's
  EXIF-derived data and drops the stale previews.
- **Import summary no longer claims "all ok" when a sidecar failed to copy:**
  a photo whose `.xmp`/`.thm` companion errored now counts as failed, so
  marks can't silently stay behind on the card.
- **IPTC Date Created no longer turns into an explicit value on round-trip:**
  the sidecar's capture-time fallback was read back as if the user had set
  it; syncing now clears the echo so "empty = follows capture time" sticks.
- **Keyboard navigation no longer clips the focused row at the bottom edge**
  (the scroll math missed the grid's padding).
- **A mark made while a folder was still syncing can no longer be lost:** the
  background sidecar resync ran from a snapshot, so rating a photo right
  after opening a folder with externally-changed sidecars could be silently
  overwritten by the disk state. The sync now only adopts a sidecar while the
  photo has no fresh local change; otherwise it surfaces as a conflict.
- **Import dialog: overlapping card scans could import the wrong files** — a
  slow scan finishing after you'd switched sources landed its files under the
  new source's name. Stale scans are now discarded.
- **Settings save is no longer all-or-nothing:** one failing write (e.g. a
  keychain error) used to silently skip every remaining setting, including a
  just-picked performance preset. Each write now proceeds independently and
  failures are logged.
- **Cameras with an unset clock no longer sort to year 0:** the EXIF
  placeholder date "0000:00:00" was parsed as a real (absurd) date, pushing
  those photos to the top of the grid and into rename tokens.
- Smaller fixes: a failed delivery connection no longer leaks a socket per
  retry; "Move to Trash" no longer miscounts already-trashed files as
  failures after a partial refusal; clearing the preview cache no longer
  races photos still being decoded; the serial captioning walk can't
  double-apply on a fast ⌘Enter, and a slow GPS lookup can't fill the wrong
  photo's location fields; multiline IPTC fields (Instructions, AI prompt
  info) survive the XMP round-trip; libvips' error buffer is cleared after
  failed decodes (slow native-memory growth on folders with corrupt files);
  full-resolution previews reach the UI without an extra 10–40 MB copy.
- **Marking a photo no longer wipes foreign XMP data:** writing the sidecar
  used to replace the whole file, so a single rating keystroke destroyed
  Lightroom develop settings, crops, GPS and hierarchical keywords that lived
  in the same `.xmp`. Sidecar writes now merge: only Cullimingo's own fields
  are replaced, everything else passes through untouched. Sidecar writes are
  also atomic now (temp file + rename).
- **Ratings/labels from exiftool- or digiKam-written sidecars were ignored:**
  the reader only understood the attribute form of `xmp:Rating`/`xmp:Label`/
  `tiff:Orientation`; the element form (and marks split across multiple
  `rdf:Description` blocks) now parses too.
- **A rotation made in Lightroom now shows up in Cullimingo:** the sidecar's
  `tiff:Orientation` was read but never adopted, so an external rotate was
  silently overwritten on the next mark. Sync now translates it into the
  photo's rotation (mirror-mismatched values are left alone).
- **Marks could land on the wrong photo after a filter change:** if the
  focused photo was hidden by a new filter, a mark key silently acted on the
  first visible photo while the actual target stayed hidden — and the keyword
  editor (K) died with an internal error. Both now refocus the first visible
  photo instead.
- **Preview pool no longer leaks workers on slow media:** a job timeout used
  to spawn a replacement but never kill the stuck worker, so every timeout on
  a slow NAS/SD grew the pool (and its native LibRaw/libvips memory) by one —
  permanently. The watchdog now kills the hung worker and drops its late
  answers.
- **Cold folder opens no longer decode every visible photo twice:** the
  viewport prefetch re-requested the cells already on screen, and nothing
  coalesced concurrent requests for the same preview — each visible RAW was
  extracted twice on first open. Requests now share one in-flight extraction
  and the prefetch warms only the ring around the viewport.
- **A failed move could lose culling marks:** when "Send to…" moved photos and
  the sidecar's copy failed verification, the original `.xmp` was deleted
  anyway — the ratings/keywords then existed nowhere. The source sidecar (and,
  on cancel, the photo) is now only removed after its copy verified.
- **Rotating a JPEG is now crash-safe:** the lossless EXIF patch used to
  rewrite the original in place, so a crash mid-write could destroy the photo.
  It now writes a temp file next to it and swaps it in atomically.
- **Corrupt thumbnails could stick forever:** a crash (or a concurrent read)
  during a preview-cache write could leave a torn cache file that kept being
  served across sessions until the cache was cleared manually. Cache writes
  are now atomic, and a vanished cache file re-extracts instead of erroring
  the cell.
- **Loupe filmstrip got cheaper:** each strip cell decoded the full ~1024 px
  thumbnail for an 84×60 frame; it now decodes at cell size. Marking photos in
  a long-lived library also got snappier — the photo query that refreshes the
  grid on every mark is now index-backed instead of scanning every import ever
  opened.

## 1.2.8 — 2026-07-15

### Changed
- **Import dialog redesigned:** the form now reads as three cards along the
  natural flow — Source, Destination, Naming — matching the export dialog.
  Days on the card are grouped by year (multi-year cards were ambiguous
  before), run newest-first, and gained a "Newest day" quick action; the
  chips themselves are calmer check-toggles instead of a wall of solid pink.
  The Job-name field moved up right under the naming preset, and the full
  pattern editor is tucked behind a "Customise…" disclosure. A new footer
  always shows the running total ("104 photos · 20 MB") and — when Import is
  greyed out — the reason ("Choose a destination to import"). The naming
  example now previews the first file that will actually be copied.

### Fixed
- **Inspector showed no EXIF for Fuji `.RAF`:** the metadata inspector's
  detail reader only understood JPEG/TIFF-style headers, so opaque RAW
  containers like RAF left Lens/Shutter/Aperture/ISO/Focal length/Exp. comp.
  all showing "—". It now falls back to reading the EXIF from the RAW's
  embedded preview via LibRaw, the same way the folder scanner already did.
- **Scroll jank when culling straight off a memory card:** the preview cache
  stat'ed the original file with blocking calls on the UI isolate for every
  grid cell — instant on an internal SSD, but a visible stutter on slow
  removable media. Those lookups are now asynchronous, so scrolling stays
  smooth regardless of how slow the source volume is.

## 1.2.7 — 2026-07-14

### Changed
- **Export button polished:** the status bar's Export button no longer looks
  cramped — it gained an export icon, a slightly larger hit target and
  roomier padding, while the bar itself stays slim.

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
