# ARCHITECTURE.md — Cullimingo

Short, living architecture notes. The master spec is `BUILD_PLAN.md` (§3 for the
detail); this file records what's actually built and any deviations.

## Shape
Feature-first, layered Flutter desktop app. One window, no router yet.

```
lib/
  main.dart            # entrypoint: window_manager + ProviderScope
  app/                 # MaterialApp, dark theme, design tokens (§7)
  core/                # cross-cutting: isolates, cache, db, raw/vips/native
                       # (FFI), files, logging, settings, secrets, update
  features/<name>/     # each owns data / domain / presentation
  shared/              # reusable widgets + freezed models
packages/
  cullimingo_raw/      # (placeholder) future home of LibRaw/libvips FFI
```

## Key decisions
- **State:** Riverpod 3 with codegen (`@riverpod`). Repositories/isolates read
  state without `BuildContext`. Convention: providers that expose a
  drift-generated row type (`Photo`, `SavedSelection`) stay classic — the
  generator can't resolve part-file types (InvalidTypeException); everything
  else uses codegen.
- **Read model vs. truth:** drift (SQLite) is the fast read model the UI binds
  to; the filesystem + XMP sidecars are the durable source of truth. Sync on
  import and on manual refresh (⌘R re-scans the folder; sidecars resync on
  focus/refresh) — there is **no** filesystem watcher. A refresh only removes
  rows when the listing is complete: a missing/empty root, or a scan that
  couldn't read part of the folder (`FolderScan.unreadable`), adds and
  updates but never deletes. The ingest scan reports the same unreadable
  entries in the plan and the summary, and always reads EXIF for capture
  dates (mtime is only the fallback).
- **Sidecar naming** (`core/files/sidecar_path.dart`): RAW uses the LR/C1
  shared-stem `DSC1.xmp`. The non-RAW half of a RAW+JPEG pair uses a per-file
  `DSC1.JPG.xmp` (darktable style) so both keep independent marks; a lone
  JPEG keeps `DSC1.xmp` (or an orphaned `DSC1.JPG.xmp` once its RAW is gone).
  Resolved against the folder listing by `SidecarResolver` (GitHub #3).
- **UI isolate is sacred:** decode/encode/hash/large I/O/XMP go through the
  isolate pool (built in Phase 2). The UI only ever receives results.
- **Two-tier disk cache:** grid thumbnails + screen-res loupe previews, keyed by
  `path + size + mtime` (+ tier/long-edge salt; no file content is read — see
  `core/cache/file_signature.dart`). Orientation is covered indirectly: a JPEG
  rotate rewrites EXIF (new mtime), a RAW rotate is a widget-layer turn.
  Decode-once, reuse.

## Deviations from BUILD_PLAN.md (keep this list honest)
- **Missing/tiny-preview RAW fallback:** embedded JPEGs remain the normal fast
  path, including previews smaller than the current loupe tier. When a RAW has
  no JPEG preview or only an unusably small one (long edge below 512 px), the
  preview workers perform a neutral LibRaw demosaic and cache an sRGB JPEG.
  This is a culling fallback for files such as Nikon HLG NEFs, not a
  colour-managed RAW developer. `core/raw/raw_display_jpeg.dart` is the one
  entry point (preview pool, export, legacy extractor); the inspector and the
  folder scanner read the embedded JPEG directly because they only want its
  EXIF. Grid/loupe decodes use LibRaw's half-size mode whenever half the
  sensor still covers the tier (LibRaw has no C setter for it and the struct
  bindings are 0.21-only, so `setLibRawHalfSize` locates the field on the
  running library via two C setters; if it can't, a downscaled request fails
  over to the embedded JPEG rather than a full-sensor demosaic). LibRaw reports
  undecodable data (Nikon HE/HE\*) only through its data-error callback, which
  some decoders call from OpenMP threads, so it is a `NativeCallable.listener`
  and a reported error discards the render. The pool's watchdog is 12 s per
  job; a worker announces when it enters the demosaic, and only that job gets
  the 60 s budget (GitHub #5). Each worker keeps its last demosaic bitmap
  (`DemosaicCache`: one entry, ≤ 64 MB, 20 s TTL, keyed by path + size +
  mtime), and the pool routes other tiers of that file to that worker —
  holding them back while the decode is still running — so the grid and loupe
  tiers share one half-size decode (GitHub #7). A large sensor's full-size
  bitmap (45 MP ≈ 135 MB) is over the cap, so its full tier still decodes on
  its own. RAW cache keys carry a render version (`_rawRenderVersion` in
  `preview_cache.dart`) so pipeline changes re-extract stale previews.
- **Deliberate cull ↔ filter/inspector coupling** (July 2026): pure grouping
  domain (bursts, RAW+JPEG pairs, brackets) lives in `shared/grouping/` and
  orientation math in `core/raw/`, so features no longer reach into
  `cull/domain`. What remains is presentation-level and intentional: the
  session state (`workspaceProvider` → `currentImportProvider` →
  `photosProvider`) and the selection (`cullControllerProvider`) are owned by
  cull, and filter/inspector read them (e.g. the "selected only" chip); cull
  composes filter's widgets. Fully inverting that means extracting a session
  module — do it only with a concrete need, not for the diagram.
- **Naming:** package `cullimingo`; native package `packages/cullimingo_raw/`.
- **riverpod_lint + custom_lint deferred** (June 2026): riverpod_lint (dev) needs
  `analyzer_plugin ^0.14.0`; custom_lint only supports `<=0.13.0`. Not
  co-resolvable with riverpod 3.3 + drift_dev. `very_good_analysis` is the active
  linter. Re-add + uncomment the `custom_lint` plugin in `analysis_options.yaml`
  once custom_lint catches up.
- **freezed on prerelease** `^3.2.6-dev.1`, forced by `riverpod_generator 4.0.4`.
  Pin to stable freezed 3.x when possible.
- **Keymap grew past the §7 draft**: `M` (edit metadata), `T` (apply metadata
  template) and `,`/`.` (rotate) were added; `E` was repurposed from the
  draft's "export selected" to "send to primary editor" once export moved to
  `⌘/Ctrl-S` (`lib/features/cull/domain/cull_shortcuts.dart`,
  `lib/features/cull/presentation/cull_page.keyboard.dart`). The wiki's
  [Keyboard](https://github.com/nielsfranke/Cullimingo/wiki/Keyboard) page
  is the as-built source of truth, not §7.

## Build / CI
- CI on Forgejo Actions (`.forgejo/workflows/ci.yml`), GitHub-Actions-compatible.
  Jobs: `analyze`, `test`, `build-linux`, `build-macos`.
- Local dev: macOS needs full Xcode + CocoaPods; Linux needs the GTK dev libs
  listed in the CI workflow.
