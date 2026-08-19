# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Cullimingo is a fast, keyboard-first photo-culling desktop app (Flutter, macOS + Linux). `BUILD_PLAN.md` is the master spec; `ARCHITECTURE.md` records what's actually built and any deviations — keep it honest when you deviate.

## Commands

```bash
flutter pub get
dart run build_runner watch --delete-conflicting-outputs   # keep running during dev
flutter run -d macos                                       # or: flutter run -d linux

flutter test                                               # all unit/widget tests
flutter test test/features/cull/some_test.dart             # single test file
flutter test --plain-name "name substring"                 # single test by name
flutter test integration_test/<file> -d macos              # integration tests need a device

dart format .
flutter analyze
```

Native deps for RAW/thumbnail decode: LibRaw and libvips (`brew install libraw vips`, or distro `-dev` packages). macOS also needs full Xcode + CocoaPods.

Release bundling: `flutter build macos --release` + `tool/bundle_macos.sh` + `tool/build_dmg.sh` (macOS), `tool/build_appimage.sh` (Linux). See `DISTRIBUTION.md`.

## Codegen

Riverpod (`@riverpod`), freezed, json_serializable and drift all use build_runner. After editing any annotated file, generated `*.g.dart` / `*.freezed.dart` files must be regenerated (`dart run build_runner build --delete-conflicting-outputs` if watch isn't running). Generated files are committed but excluded from analysis.

`lib/core/version/app_version.g.dart` is generated from pubspec's `version:` by `dart run tool/gen_version.dart` — lefthook regenerates it automatically when pubspec.yaml changes.

## Hooks & CI

- lefthook pre-commit: `dart format` on staged files, `flutter analyze`, version regen. Pre-push runs `flutter test` — red code can't reach the remote; main stays green.
- Primary CI is Forgejo Actions (`.forgejo/workflows/ci.yml`): format check, analyze, test with coverage, Linux + macOS release builds. GitHub is a squashed public mirror (`tool/publish_github.sh`); its only workflow is `release.yml`, fired by pushing a `v*` tag.
- Lint set is `very_good_analysis`. riverpod_lint/custom_lint are deliberately disabled (dependency conflict — see the note in `analysis_options.yaml`); don't try to re-add them without checking that note.
- `CHANGELOG.md` tracks user-facing changes manually (Keep-a-Changelog style).

## Architecture

Feature-first, layered Flutter desktop app. One window, no router.

- `lib/app/` — MaterialApp, dark theme, design tokens
- `lib/core/` — cross-cutting: isolate pool, two-tier cache, drift db, LibRaw/libvips FFI (`raw/`, `vips/`, `native/`), files, logging, settings, update check
- `lib/features/<name>/` — each feature owns `data/` (repositories), `domain/` (models, logic), `presentation/` (widgets, Riverpod providers). Features: cull, loupe, filter, inspector, metadata, ingest, export, handoff, delivery, library, naming, settings
- `lib/shared/` — reusable widgets + freezed models
- `packages/cullimingo_raw/` — placeholder for future FFI package

Key invariants (from `ARCHITECTURE.md`):

- **State:** Riverpod 3 with codegen. Repositories/isolates read state without `BuildContext`.
- **Read model vs. truth:** drift (SQLite) is the fast read model the UI binds to; the filesystem + XMP sidecars are the durable source of truth. Sync on import and on manual refresh (⌘R) — there is no filesystem watcher. XMP round-trips rating/colour/keywords with Capture One and Lightroom; pick/reject lives in a private `cullimingo:` namespace.
- **UI isolate is sacred:** decode/encode/hash/large I/O/XMP go through the isolate pool (`lib/core/isolates/preview_pool.dart`). The UI only ever receives results — never block the UI isolate.
- **Two-tier disk cache:** grid thumbnails + screen-res loupe previews, keyed by `path + size + mtime` (+ tier/long-edge salt; no file content is read). Decode once, reuse.
- libvips must be initialised once on the main isolate before worker isolates spawn (`Vips.warmUpProcess` in `main.dart`) — first-use races freeze the app.

Keyboard shortcuts live in `lib/features/cull/domain/cull_shortcuts.dart` and `lib/features/cull/presentation/cull_page.keyboard.dart`; the wiki's Keyboard page is the as-built source of truth for the keymap, not BUILD_PLAN §7.

Non-goals (v1): not a RAW developer, not a forever catalog, no AI culling, no in-app video playback.
