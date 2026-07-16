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
  state without `BuildContext`.
- **Read model vs. truth:** drift (SQLite) is the fast read model the UI binds
  to; the filesystem + XMP sidecars are the durable source of truth. Sync on
  import and on manual refresh (⌘R re-scans the folder; sidecars resync on
  focus/refresh) — there is **no** filesystem watcher.
- **UI isolate is sacred:** decode/encode/hash/large I/O/XMP go through the
  isolate pool (built in Phase 2). The UI only ever receives results.
- **Two-tier disk cache:** grid thumbnails + screen-res loupe previews, keyed by
  `path + size + mtime` (+ tier/long-edge salt; no file content is read — see
  `core/cache/file_signature.dart`). Orientation is covered indirectly: a JPEG
  rotate rewrites EXIF (new mtime), a RAW rotate is a widget-layer turn.
  Decode-once, reuse.

## Deviations from BUILD_PLAN.md (keep this list honest)
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
