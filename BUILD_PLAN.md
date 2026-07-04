# Cullimingo — Build Plan

> **Cullimingo** — "cull" + flamingo, nature's filter feeder. Dart package id `cullimingo`, bundle id `cc.nielsbox.cullimingo`. (Originally scaffolded under the working title *Kestrel*.)
> A fast, open-source, cross-platform photo **culling** tool for professional workflows, with a dense, keyboard-driven dark UI. macOS-first, Linux as a true co-equal target, Windows later.
>
> **This document is the master spec.** It is written in English on purpose: it is consumed by Claude Code and every library/API/commit-message convention here is English anyway. Feed it to Claude Code phase by phase, not all at once.

---

## 0. How to drive this with Claude Code

Treat Claude Code like a strong junior who needs tight guardrails. The professional workflow below *is* your safety net as a vibecoder — typing, codegen, lint, and tests catch the mistakes you can't yet see by eye.

**Rules of engagement (give these to Claude Code up front — they're also in `CLAUDE.md`):**

1. **One phase at a time.** Do not let it scaffold Phase 5 while Phase 1 is unproven. Each phase has a *Definition of Done*; do not advance until it's green.
2. **Red → Green → Commit.** Write the test (or at least the acceptance check), make it pass, commit. Small commits with [Conventional Commits](https://www.conventionalcommits.org/) messages (`feat:`, `fix:`, `refactor:`, `test:`, `chore:`).
3. **Codegen is not optional.** After touching any `@riverpod`, `freezed`, drift table, or JSON model, run `dart run build_runner build --delete-conflicting-outputs` (or keep `watch` running). Never hand-edit `*.g.dart` / `*.freezed.dart`.
4. **CI is the referee.** A phase isn't done until `flutter analyze` is clean, tests pass, and the macOS + Linux build artifacts compile in CI.
5. **No silent scope creep.** If Claude Code wants to add a dependency or a feature not in this plan, it must say so and why, in one line, before doing it.
6. **Heavy work never runs on the UI isolate.** Decode, encode, hash, and file I/O go through the isolate pool (Phase 2). This is the single most important performance rule in the whole project.

**Suggested first prompt to Claude Code:**

> "Read `BUILD_PLAN.md` and `CLAUDE.md`. We are doing **Phase 0 only**. Scaffold the project exactly as specified: package name `cullimingo`, the directory structure in §3, the locked dependency versions in §2, lint + format + git hooks + CI as in §4. Do not implement any product features yet. At the end, show me `flutter analyze` output and the CI workflow file, then stop."

---

## 1. Product definition

### The core loop
Cullimingo does exactly one job extremely well: get a photographer from "card full of RAWs" to "selects handed off" as fast as possible.

```
INGEST ─▶ CULL ─▶ FILTER ─▶ EXPORT ─▶ HAND-OFF
(copy)   (rate/   (rating/   (JPEG at   (drag-out /
         flag/    flag/      chosen     send-to PS,
         color)   color/     size+qual) C1, LR, …)
                  CSV)
```

### Who it's for
A working pro photographer (you) who currently pays for commercial culling software and wants something native-feeling on macOS that *also* respects Linux. The benchmark is subjective speed: **scroll and rate 2,000+ RAWs without lag**, and export a few hundred selects in the background while you keep working.

### Non-goals (protect these fiercely)
- **Not a RAW developer.** No demosaic editing, no curves, no local adjustments. That's Capture One / Lightroom / Darktable. We extract embedded previews for culling and render to JPEG for proofs/handoff — nothing more.
- **Not a forever-catalog DAM.** No multi-year library, no cloud sync, no face database. The unit of work is an *import / shoot folder*, not a lifetime archive.
- **Not an AI culling engine** (this release). Blur/closed-eyes/face/duplicate ML detection is a real moat for AI-culling tools and a separate research project. We copy the *look* of a dense, dark culling UI, not that brain. See §6.6 for an optional, clearly-fenced future track.
- **Not a video player.** Video is culled by its poster frame; playback hands off to the system player ("open in system player" from the loupe). No in-app playback — we deliberately don't take the `media_kit` dependency (decided 2026-07-04).

### Success criteria (acceptance for v1.0)
- Open a folder of 2,000 Sony ARW files; first thumbnails visible < 2 s; full grid scrollable at 60 fps on the M4 Pro.
- Keyboard-only cull: arrow + rate + flag + color with zero perceptible input lag.
- Ratings/labels/keywords round-trip to Capture One and Lightroom via XMP sidecars (with documented exceptions — see §6.3).
- Export 300 selects to 2048px / Q85 JPEG in the background without freezing the UI.
- Drag a thumbnail into Photoshop and into a Finder folder. "Send to Capture One" works on macOS.
- One codebase builds and runs on macOS (Apple Silicon) and Linux.

---

## 2. Locked tech stack (researched, mid-2026)

Versions verified current as of June 2026. Run `flutter upgrade` first; pin in `pubspec.yaml` and let Renovate/Dependabot bump later.

| Layer | Choice | Version | Why |
|---|---|---|---|
| Framework | **Flutter** (stable channel) | 3.44.x | Impeller is now the default renderer → the consistent, GPU-driven scrolling that makes Linux look identical to macOS. Self-rendering = no degraded Linux port. |
| Language | **Dart** | 3.12+ | Ships with Flutter 3.44. Sound null safety, records, patterns, `dot-shorthands`. |
| State mgmt | **Riverpod** (+ codegen) | flutter_riverpod ^3.3 | 2026 default for new apps. Compile-time safe, no `BuildContext` for reads (repositories/isolates can read state), `AsyncValue` for loading/error. **Bonus for us:** Riverpod 3's auto-pause of off-screen listeners is a free win for a huge thumbnail grid. |
| | riverpod_annotation / riverpod_generator / riverpod_lint / custom_lint | latest | `@riverpod` codegen + static analysis. |
| Local DB | **drift** (typed SQLite) | ^2.x | Relational, typed, reactive queries, runs on all desktop targets via `sqlite3_flutter_libs`. This is the **fast source of truth** for the UI. |
| RAW decode | **flutter_libraw** (LibRaw via Dart FFI) | latest | Extracts the **embedded full-res JPEG preview** + metadata (CFA, WB, black level…) and can do a full demosaic for export. ⚠️ Early-stage package — budget a fallback of hand-rolled `ffigen` bindings straight to LibRaw if it's missing a call you need (§6.1). **No Rust here — this is C/C++ FFI.** |
| Image encode/resize | **image** (pure Dart) for MVP → **libvips via FFI** for scale | image ^4.x | `image` needs zero native setup → ship the MVP fast, run it in isolates. When batch export of hundreds of files feels slow, drop in libvips (hand-rolled ffigen bindings) as the fast path. Keep the encode behind an interface so the swap is local. |
| Drag-OUT | **super_drag_and_drop** (+ super_clipboard) | latest | The cross-platform drag-out option (files + *virtual files* generated at drop time = export-on-drag). Uses Rust **internally** but ships precompiled binaries → **you never write or install Rust.** ⚠️ Known gesture-vs-scroll conflict on macOS → native fallback planned in §6.2. |
| Drag-IN (drops) | **desktop_drop** | latest | Lightweight; for dropping CSV/file-lists and folders *into* Cullimingo. (super_* can also do this, but desktop_drop is simpler for in-only.) |
| Folder/file pick | **file_selector** | latest | Native pickers for "choose import folder" / "choose destination". |
| Desktop window | **window_manager** | latest | Window size/position persistence, custom title bar, min-size — desktop polish. |
| FS watching | **watcher** | latest | Detect new files during ingest / folder changes. |
| Hashing | **crypto** (+ stream) | latest | xxHash-style content hashing for ingest verification + cache keys (use a fast non-crypto hash if perf demands; see §3 caching). |
| Models | **freezed** + **json_serializable** | latest | Immutable data classes, unions, copyWith, JSON. |
| Logging | **talker** (or `logging`) | latest | Structured logs + in-app log viewer for debugging the isolate pipeline. |
| Lint | **very_good_analysis** | latest | Strict, opinionated rule set (stricter than `flutter_lints`). Combine with `riverpod_lint` + `custom_lint`. |
| Git hooks | **lefthook** | latest | Pre-commit: `dart format` + `flutter analyze` on staged files. Fast, language-agnostic. |
| Routing | **go_router** (optional/light) | latest | A single-window desktop app barely needs it; use only if/when you add real multi-screen nav. Don't over-engineer. |

**Deliberately NOT chosen:** Tauri (Rust backend = your pain point; WebKitGTK = the weakest Linux scrolling), Electron (you ruled it out; worst image perf), GetX (maintenance risk in 2026), Hive/Isar (drift's relational model fits a photo library better).

---

## 3. Architecture

### Principles
- **Feature-first, layered.** Each feature owns its `data` / `domain` / `presentation`. Shared primitives live in `core/`.
- **The UI isolate is sacred.** Anything that can take >1 frame (decode, encode, hash, large file I/O, XMP parse) runs in a background isolate. The UI only ever touches *results*.
- **SQLite is the read model; the filesystem + XMP is the durable truth.** The grid reads from drift (instant). Ratings/labels are mirrored to XMP sidecars for interop. On import / external change, sync FS↔DB.
- **Two-tier disk cache.** (a) tiny grid thumbnails (~256–512px) and (b) screen-res "loupe" previews, both on disk, keyed by `contentHash + mtime + orientation`. Decode-once, reuse forever.

### Directory structure

```
cullimingo/
├─ pubspec.yaml
├─ analysis_options.yaml
├─ lefthook.yml
├─ CLAUDE.md                      # project memory for Claude Code (see separate file)
├─ ARCHITECTURE.md                # short, living; link back to this plan
├─ .github/workflows/ci.yml       # (or .forgejo/workflows/ci.yml — see §4)
├─ packages/
│  └─ cullimingo_raw/                # OPTIONAL split: LibRaw/libvips FFI isolated as its own package
│     ├─ lib/                     #   keeps native build pain out of the app package
│     └─ src/                     #   (start in-app; extract here once it stabilises)
└─ lib/
   ├─ main.dart
   ├─ app/
   │  ├─ app.dart                 # MaterialApp, theme, window setup
   │  └─ theme/                   # design tokens (see §7)
   ├─ core/
   │  ├─ isolates/                # isolate pool, job queue, worker entrypoints
   │  ├─ cache/                   # two-tier disk cache, hashing
   │  ├─ db/                      # drift database, DAOs, migrations
   │  ├─ raw/                     # RAW facade: embedded-preview + full-render interfaces
   │  ├─ files/                   # path utils, watchers, safe copy
   │  └─ logging/
   ├─ features/
   │  ├─ ingest/                  # SD import, rename templates, verify
   │  ├─ library/                 # folders/imports, photo entities, scanning
   │  ├─ cull/                    # the grid, keyboard nav, rate/flag/color   ← the heart
   │  ├─ loupe/                   # fullscreen / compare view
   │  ├─ filter/                  # rating/flag/color filters + CSV/Picdrop selects
   │  ├─ metadata/               # XMP sidecar read/write, DB↔XMP sync
   │  ├─ export/                  # JPEG export pipeline, presets, batch
   │  └─ handoff/                 # drag-out + send-to integrations
   └─ shared/
      ├─ widgets/                 # reusable UI (rating stars, color dot, badges)
      └─ models/                  # freezed models shared across features
```

### Threading / pipeline model (Phase 2 makes this real)
```
UI isolate ──(job: "give me preview for photo X at size S")──▶ Job Queue
                                                                  │
                          Isolate Pool (N = cores-1) ◀───────────┘
                          ├─ worker: extract embedded JPEG (LibRaw)
                          ├─ worker: decode + downscale to thumb/loupe
                          ├─ worker: hash file for cache key
                          └─ worker: encode JPEG for export
                                                                  │
UI isolate ◀──(result: ui.Image / bytes / done)──────────────────┘
```
Use `Isolate.run` for one-offs and a **persistent pool** (long-lived isolates + `SendPort` job channel) for the hot path so you're not paying spawn cost per thumbnail. Prioritise jobs for **visible + neighbouring** cells; cancel jobs for cells scrolled far off-screen.

### Data model (drift tables — minimum viable)
- `imports` (id, source_path, dest_path, created_at, card_label)
- `photos` (id, import_id, raw_path, content_hash, mtime, captured_at, camera, lens, width, height, orientation, rating, flag, color_label, has_xmp, preview_cached)
- `keywords` (id, name) + `photo_keywords` (photo_id, keyword_id)
- `selections` (id, name, source) + `selection_photos` (selection_id, photo_id)  ← Picdrop/CSV lists land here
- `settings` (key, value)  ← or shared_preferences; pick one and be consistent

### As-built notes (updated 2026-07-01)
The sections above are the original plan; these record where the shipped code
deliberately differs or has been refined. Keep them in sync as the architecture
evolves.

- **UI-isolate rule holds in both directions.** FS↔XMP work runs off the UI
  isolate via `compute()` on *both* legs: reading external marks on import
  (`readMarksForPaths`) **and** re-reading sidecars from disk on sync
  (`readSidecarSyncStates` in `metadata_repository.syncSidecarsFromDisk`). Only
  the DB reconciliation stays on the UI isolate.
- **Preview pool is FIFO + cancel, not a reordering priority queue.** The
  "visible + neighbouring first" goal (see threading model) is achieved by
  *cancelling* off-screen jobs — the auto-disposed `thumbnailProvider` /
  `loupePreviewProvider` trip their `CancelToken`, so the queue drains to the
  visible cells fast — rather than by re-sorting a priority queue. A true
  priority queue remains a possible refinement.
- **Two-tier cache key, as-built.** The cache key is
  `path + size + mtime + salt(tier + longEdge)` (`core/cache/file_signature.dart`),
  a deliberate speed trade vs. the planned `contentHash + mtime + orientation`:
  no file content is read (contentHash → size), and EXIF orientation is folded
  into the *cached result* (libvips auto-rotates on thumbnail) rather than the
  key. Trade-off: a pure EXIF-orientation rewrite that leaves size+mtime
  unchanged can leave a stale cache entry.
- **State management: Riverpod, including background-job progress.** All state is
  Riverpod; classic providers are used only where a provider must expose the
  drift-generated `Photo` type (codegen can't convert it — see the CLAUDE.md
  provider note). The floating export / ContactSheet / find-similar progress
  cards are driven by a `BackgroundJobs` `@riverpod` notifier
  (`features/cull/presentation/background_jobs.dart`) with pure, unit-tested
  transitions; cancellation stays a plain token so a running loop can still poll
  it after the page is disposed.
- **`cull/` presentation is decomposed, not one file.** The heart-of-the-app
  `CullPage` is split for readability (target <500 lines/file): the `State` class
  is a linear chain of `part`-file mixins
  (`_CullNotices → _CullGrid → _CullWorkspace → _CullSelections → _CullJobs →
  _CullKeyboard`, each in `cull_page.<area>.dart`); self-contained widgets live
  in `features/cull/presentation/widgets/` (`grid_cell`, `cull_top_bar`,
  `cull_tab_bar`, `empty_states`, `notice_bar`, `export_bar`, `photo_cell`,
  `loupe_view`, `compare_view`, …); pure key/action maps live in
  `features/cull/domain/cull_key_mappings.dart`. Note: `loupe/` and `library/`
  from the idealised tree above are folded into `cull/` in the shipped code.

---

## 4. Professional workflow setup — **Phase 0**

This is the foundation. Don't skip a single line; it's what lets you move fast later without breaking things.

### Version control
- `git init`, trunk-based: `main` is always green; short-lived `feat/*` branches, squash-merge.
- Conventional Commits enforced by hook. Tag releases `v0.x` per milestone.
- **CI runs on your private Forgejo** via Forgejo Actions — it's GitHub-Actions-compatible, so the workflow file is portable. Mirror to GitHub later if you want public contributors.

### `analysis_options.yaml`
```yaml
include: package:very_good_analysis/analysis_options.yaml
analyzer:
  plugins:
    - custom_lint            # enables riverpod_lint
  errors:
    invalid_annotation_target: ignore   # common with riverpod codegen
  exclude:
    - "**/*.g.dart"
    - "**/*.freezed.dart"
```

### `lefthook.yml`
```yaml
pre-commit:
  parallel: true
  commands:
    format:
      glob: "*.dart"
      run: dart format {staged_files} && git add {staged_files}
    analyze:
      run: flutter analyze
```

### Testing strategy (build the habit from commit #1)
- **Unit** — pure logic: rename-template parser, XMP read/write, filter predicates, cache-key derivation, export-size math. Fast, no Flutter.
- **Widget** — rating stars, color dot, a single grid cell, the filter bar.
- **Golden** — the cull grid cell and the theme, so UI regressions are caught visually (run goldens on Linux CI for determinism).
- **Integration** — the core flow: open folder → previews appear → rate via keyboard → filter → export. One real end-to-end test beats ten mocked ones.
- Target ~70% coverage on `core/` and `features/*/domain`; don't chase 100% on widgets.

### CI (`.forgejo/workflows/ci.yml` / `.github/workflows/ci.yml`)
Jobs: (1) `analyze` → `flutter analyze` + `dart format --set-exit-if-changed`; (2) `test` → `flutter test --coverage`; (3) `build-macos` and (4) `build-linux` → compile the desktop bundles so native/FFI breakage is caught early. Cache pub + build artifacts.

### Definition of Done — Phase 0
✅ `flutter create` with macOS + Linux desktop enabled, package `cullimingo`.
✅ Directory structure from §3 exists (empty stubs OK).
✅ All §2 deps added at pinned versions; `flutter pub get` clean.
✅ `build_runner` runs clean (even with empty generators wired up).
✅ Lint + format + lefthook + CI all green on an empty app that shows a dark window with the app title.
✅ `README`, `ARCHITECTURE.md`, `CLAUDE.md` committed.

---

## 5. Phased delivery

Each phase below is a self-contained chunk you hand to Claude Code. Ship, prove the DoD, commit, tag, then move on.

### Phase 1 — The cull core ⭐ *(the heart; build this first, it proves the whole concept)*
**Goal:** Point at a folder, see a fast grid of embedded-JPEG thumbnails, navigate and rate by keyboard. If this feels good, the project is viable; if it doesn't, no other feature matters.

**Tasks**
- Folder picker → recursive scan for RAW + JPEG; insert rows into drift `photos`.
- RAW facade `extractEmbeddedPreview(path) → bytes`: via flutter_libraw `unpack_thumb`. Confirm Sony ARW returns full-res embedded JPEG (it does). Fallback to native JPEG decode for non-RAW.
- **Virtualized grid** (`GridView.builder` / `SliverGrid` with lazy cells) — never build off-screen cells. Dense grid cell (§7): image, rating stars, color dot, flag badge, filename, selection border.
- Keyboard model (de-facto culling standard, configurable — see §7 keymap): arrows navigate selection, `1–5` rate, `0` clear, `P`/`X` pick/reject, `6–9`+`0` color labels, `Space` toggle select.
- Persist rating/flag/color to drift immediately; reflect in UI optimistically.
- *(follow-up, added 2026-06-29)* **Include-subfolders as a live toggle:** the
  toolbar `account_tree` toggle re-scans the open folder immediately (shows /
  hides nested files in the grid live), not just on the next "Open folder".
- *(follow-up, added 2026-06-29)* **Drag a folder into the window → open it** in
  the grid (drops-in via `desktop_drop`; dropping image files opens their parent
  / imports them). Pairs with the Phase 7 drag-**out**.

**Acceptance / DoD**
✅ 2,000-file folder: first thumbs < 2 s, smooth scroll.
✅ Keyboard-only cull works with no visible lag.
✅ Quit & reopen → ratings/flags/colors persist (from drift).
✅ Golden test on the grid cell; integration test for "open folder → rate → persisted".

### Phase 2 — Performance hardening *(make it feel instant, even at scale)*
**Goal:** Turn "works" into "buttery, even at 5,000 files."

**Tasks**
- Persistent **isolate pool** + prioritized job queue (visible & neighbour cells first; cancel far-off jobs).
- **Two-tier disk cache** (thumb + loupe), keyed by `hash+mtime+orientation`; decode-once.
- **Neighbour preloading** so arrow-key paging shows the next loupe instantly.
- Memory budget: cap in-RAM decoded images; evict LRU; dispose `ui.Image` handles deterministically.
- Throttle/debounce scroll-driven job dispatch.

**DoD** ✅ 5,000-file folder scrolls at 60 fps; memory stays bounded (watch with DevTools); cold vs warm cache measurably different; no leaked `ui.Image` (DevTools memory view flat after scrolling).

### Phase 3 — Ingest *(SD card → disk, done right)*
**Tasks**
- Detect removable volumes; choose source + destination root.
- **Rename templates** with tokens: `{YYYY}`, `{MM}`, `{DD}`, `{HHmmss}`, `{camera}`, `{seq}`, `{origname}` (driven by EXIF `DateTimeOriginal`). Live preview of resulting paths.
- Folder-structure presets (`{YYYY}/{YYYY-MM-DD}_{shoot}`).
- **Verified copy:** hash source + dest, confirm match (verified ingest integrity). Optional **dual-destination** backup copy in one pass.
- Resume/skip-existing; never overwrite silently.

**DoD** ✅ Import a real card to two destinations with verification; corrupt/incomplete copies are detected; rename preview matches output exactly.

### Phase 4 — Metadata & interop *(the part that makes it usable alongside C1/LR)*
**Tasks**
- XMP sidecar **read** on scan; **write** on rating/label/keyword change.
- Schema that C1 + LR actually read: `xmp:Rating` (0–5), `xmp:Label` (color string), `dc:subject` (keywords bag). Match the exact label strings the other apps expect.
- DB↔XMP **sync** policy (last-writer-wins by mtime; surface conflicts).
- ⚠️ Document the honest gap: **pick/reject flags have no universal XMP standard** — LR keeps flags in its catalog, not XMP. Store our flag in a private namespace (`cullimingo:flag`) and tell the user it won't appear as LR's flag. (Rating + color *do* round-trip.)

**DoD** ✅ Rate/label/keyword in Cullimingo → open same folder in Capture One and Lightroom → rating + color + keywords show up. Round-trip the other way too.

> The descriptive IPTC Core fields (Caption/Creator/Copyright/Credit/Location/Alt-Text) and templates/code-replacements build directly on this engine — see the draft **Phase 9** (post-v1.0).

### Phase 5 — Filtering & selections *(incl. Picdrop/CSV)*
**Tasks**
- Filter bar: by rating threshold, flag state, color label, "has keyword", combinations. Quick-filter chips (Selected / Highlights / All).
- **Import file-list** (Picdrop export, generic CSV/txt): parse → match by filename (robust to extension/case/path differences) → create a `selection` and mark/jump to those photos.
- Build this around a **generic "selection source" abstraction** (parse → match-by-filename → `selection`). Picdrop/CSV is the first source; **ContactSheet** (§7b) plugs in here as a second, API-backed source that also carries client ratings/flags.
- Saved selections; export-from-selection.

**DoD** ✅ Drop a Picdrop CSV → exactly the listed frames get selected, even when the CSV lists JPEG names and you have RAWs; filter chips update counts live like the screenshot.

### Phase 6 — Export *(RAW → JPEG, fast, in background)*
**Tasks**
- Two render paths behind one interface:
  - **Embedded-resize** (default, fast): downscale the embedded JPEG → in-camera look, ideal for proofs/web.
  - **Full-render** (LibRaw demosaic → RGB → encode): neutral look, slower, for when quality matters.
- Presets: long-edge px, quality, format (JPEG via the `image` package; **WebP/AVIF shipped 2026-07-02** via the bundled libvips — hand-written FFI over five calls in `core/vips/vips_encoder.dart`, offered in the dialog only when libvips loads; XMP rides along, IIM is JPEG-only), sharpening on downscale, optional sRGB convert, filename template, destination.
- **Batch in the isolate pool** with a progress UI; encode via `image` (MVP) → libvips swap (scale).
- ⚠️ Set expectations: this is **not** Capture One's or Lightroom's render *look* — matching their color science needs their engines and is out of scope.

**DoD** ✅ Export 300 selects @2048px/Q85 in background, UI stays at 60 fps, progress accurate, output opens correctly and carries basic EXIF.

### Phase 7 — Hand-off *(drag-out + send-to — the genuinely hard, Mac-centric part)*
**Tasks**
- **Drag-out** via super_drag_and_drop using **virtual files**: generate the export (or hand the original) *at drop time*. Drop into Finder and into Photoshop.
  - *(clarified 2026-06-29)* Drag the selected photo(s) **out of the window**; the file lands wherever it's dropped — a Finder folder or the Desktop copies it there. Reuses the Phase 6 export pipeline to produce the bytes at drop time (or hands over the original, per a setting).
- ⚠️ **macOS gesture conflict mitigation** (see §6.2): if super_* fights the grid's scroll/selection, fall back to a thin native `NSFilePromiseProvider` / `NSDraggingSource` platform channel for the drag-out surface specifically. Plan for this; don't be surprised by it.
- **Copy / move to a folder** *(added 2026-07-01)* — the non-drag counterpart to drag-out, for when the target isn't another app but the filesystem. Right-click a thumbnail → **Copy to folder…** / **Move to folder…** acts on the current selection (`markTargets`), carries the RAW original + `.xmp` sidecar, and de-dupes name clashes like ingest. Reuses the Phase 3 `verifiedCopy` (SHA-256) off the UI isolate; **move deletes each source only after its copy verifies** (a conflict or dest==source keeps the original). Runs non-modally with the shared floating progress card (`features/handoff/data/transfer_service.dart`).
- **Send-to**:
  - ✅ *(done 2026-07-01)* **Generic "open with"** — a user-configured editor list (Settings → *Send to editors*), each launched with the selected RAW originals via `open -a` (macOS `.app` bundles) or the executable (Linux/Windows). Surfaced as `Open in <editor>` in the right-click menu and ⌘E for the first editor. Covers Capture One / Lightroom / Photoshop / GIMP / Darktable / RawTherapee as "open the files in this app" (`features/handoff/domain/external_editor.dart`, `core/files/open_external.dart#openInApp`).
  - **Deliberately deferred** (per §6.5): app-specific *scripting* (Capture One AppleScript, Photoshop scripting) and the Lightroom **watched-folder** import workaround. These are macOS-only, brittle, and version-dependent, and LR's real need is already met by copy/move-to-folder — revisit only on demand.
  - Linux: targets differ by design — Darktable / RawTherapee / GIMP via "open with"; no AppleScript equivalent. Send-to is a per-platform capability list, not a promise of symmetry.

**DoD** ✅ Drag a thumbnail into Photoshop and into a Finder folder; "Send to Capture One" works on macOS; Linux "open in Darktable" works; the macOS drag surface coexists with smooth grid scrolling.

### Phase 7b — ContactSheet integration *(send-to + client selection round-trip)*
> **ContactSheet** is Niels' own self-hosted client-delivery app (FastAPI + Next.js; repo `nielsfranke/contactsheet`). It's the natural hand-off + Picdrop-style target: push a shoot's selects to a client gallery, then pull back what the client picked. Cross-platform (plain HTTPS) — unlike the Mac-only send-to above. **Depends on Phase 6 (export pipeline produces the JPEGs) and reuses the Phase 5 selection-source abstraction for the pull.**

**Auth:** scoped personal access token, `Authorization: Bearer cs_pat_…`. Token + base URL live in settings (Phase 8 settings screen). Scopes that exist today: `galleries:read`, `galleries:write`, `images:write`.

**Tasks**
- **`ContactSheetClient`** under `features/handoff/` behind a `RemoteDestination` interface (so other delivery targets can follow). Add an HTTP client dependency (`dio` or `http`) — *flag the dep before adding*.
- **Push — works against today's API, no server changes:**
  - Create album: `POST /api/galleries` (scope `galleries:write`).
  - Export + upload selects: `POST /api/galleries/{gallery_id}/images`, multipart `files[]` (scope `images:write`). Feed it from the Phase 6 export pipeline (long-edge/quality preset → JPEG → upload), batched in the isolate pool with progress.
- **Pull — client ratings/flags/likes/collections back into Cullimingo marks** (which then round-trip to XMP via Phase 4). The review data exists but isn't behind an API-token read scope yet. Two paths:
  1. *Quick, no server change:* read via the gallery's **`share_token`** public endpoints (`GET /g/{share_token}/images`, `/likes`, `/collections`).
  2. *Clean (recommended):* add a `galleries:read`-scoped endpoint on ContactSheet (Niels' own app) returning per-image review state, then consume that. Match by filename via the Phase 5 selection-source matcher.
- Conflict policy when pulling marks that already exist locally: last-writer-wins by timestamp, same as the DB↔XMP sync (§4); surface conflicts.

**DoD** ✅ From a selection, create a ContactSheet album and upload JPEG proofs with a progress UI; the gallery appears in ContactSheet. After a client rates/flags/likes in the gallery, pull those back so the matching Cullimingo photos show the client's marks (and they land in XMP). Works on macOS **and** Linux.

### Phase 8 — Polish & the dark culling look
**Tasks**
- Full theme pass to the §7 tokens; loupe/fullscreen; **compare view** (2-up / n-up); optional **duplicate grouping** via *heuristic* (capture-time bursts or perceptual hash — **no ML**); settings screen; in-app log viewer; about/licenses.
- *(added 2026-06-29)* **Metadata inspector panel:** a toggle that slides open a right-hand side panel showing the focused photo's metadata (EXIF — camera/lens/exposure/capture time/dimensions — plus rating, colour, flag and keywords from Phase 4). Read-only display; built with the shared dialog/panel style kit. Collapsible like the §7 filter panel.

**DoD** ✅ It looks like the screenshot, feels fast and native, and a stranger can cull a shoot without a manual.

### Phase 9 — IPTC captioning for journalists *(post-v1.0; extends Phase 4)* — **✅ SHIPPED (2026-07-02)**
> **Why this exists.** For photojournalists/sports shooters, the real moat isn't the field list — it's *"template + variables + code replacements applied at ingest,"* so a full card of captioned, credited frames reaches the wire in seconds. Phase 4 already gives us the durable-truth sidecar sync engine (write-through, mtime conflict handling, isolate parsing); this phase reuses it and only widens the payload. **Deliberately scoped to captioning, not a DAM** (§1 non-goals stand): the unit of work is still one shoot folder.
>
> **Where commercial tools are weak → our edge:** one metadata panel for single *and* batch (the incumbents split this into two inconsistent dialogs); code-replacement table editable *in-app* with live expansion preview (elsewhere this hides in external tab-separated files); variable insertion via autocomplete chips, not raw `%`/`{}` codes; **Alt-Text + AI-label fields first-class from day one** (IPTC 2025.1 — added late elsewhere). Sources gathered 2026-07-01: iptc.org/standards/photo-metadata, camerabits Metadata (IPTC) Template + Code Replacements docs, carlseibert.com.

**Layer 1 — IPTC Core fields + editor. ✅ SHIPPED as Phase 4b (2026-07-01).**
Delivered: `IptcCore` value object + `photos.iptc` JSON column (schema v4);
`xmp_codec` writes/reads the Core set with correct namespaces and round-trips
through the Phase 4 sidecar sync engine; the `IptcEditorDialog` (`M`) edits one
photo or a batch from a single surface with "only changed fields written"
semantics; the inspector's IPTC section is inline-editable since 2026-07-02 (click a value; '+ Add field' menu; Enter/blur commits, Esc cancels) with the Edit button still opening the full M editor.
Original scope was:
  - `dc:description` (Caption), `photoshop:Headline`, `dc:creator` (Creator) + `photoshop:AuthorsPosition`, `dc:rights` (Copyright Notice), `photoshop:Credit`, `photoshop:Source`, `photoshop:Instructions`, `Iptc4xmpCore:Location` + `photoshop:City`/`State`/`Country` + `Iptc4xmpCore:CountryCode`, `Iptc4xmpCore:AltTextAccessibility` (2025.1).
  - Editable in the inspector panel (Phase 8) — single photo *and* batch — not read-only. Keep the isolate write-through path; add fields to the drift `photos` table.
**Layer 2 — Metadata template + apply-on-ingest. ✅ SHIPPED as Phase 4b (2026-07-01).**
Delivered: pure `IptcTemplate` + `applyTemplate` (per-field write, caption
Replace/Prefix/Append, keyword Replace/Add with de-dupe); persisted in
`AppSettings` (`metadataTemplate` + `applyTemplateOnIngest`); `IptcTemplateDialog`
(per-field checkbox that auto-ticks on typing, mode pickers) reached from
Settings; **⋮ → Apply metadata template** stamps the saved template onto the
selection; and the ingest flow (`_ingest` only, never open-folder) auto-stamps
the whole import when the toggle is on. Live-verified end-to-end (editor→DB→XMP,
batch "only touched fields", apply-to-selection). Named **snapshots** (multiple
templates, switchable per customer) shipped 2026-07-02 — see the backlog entry.
*Still open:* per-app `.xmp` sharing.
**Layer 3 — Variables + code replacements. ✅ SHIPPED as Phase 4b (2026-07-01).**
Delivered: readable `{token}` variables (year/month/day/date/time, filename/
name/ext, camera/lens, seq — date falls back to today; `template_variables.dart`)
and `=code=` replacements with `#n` alternates + configurable delimiter
(`code_replacements.dart`, incl. a `fromTabText` importer for tab-separated
code files); `expandTemplate` runs codes then variables per photo inside both
apply paths; an **in-app `CodeTableDialog`** with a live preview (kept in-app
instead of external tab files);
both persisted in settings and reachable from the Metadata-template section.
Live-verified: `"Shot by =ff=, {date}"` → `"Shot by staff, 2026-07-01"`,
`"© {year} Jane Doe"` → `"© 2026 Jane Doe"`. *Not done:* GPS→city/country
(needs reverse geocoding — deferred) and expansion inside the interactive
per-photo editor (templates only for now).

**DoD** ✅ Ingest a card with a template that sets Caption (with a `=name=` code replacement and a `© %Y` variable), Creator, Credit and Alt-Text → every frame carries the expanded metadata → open the folder in Photoshop/Bridge and the IPTC Core fields read back correctly; batch-edit Caption with Append on a multi-selection round-trips to C1/LR.

**Delivered beyond the original three layers ✅ (2026-07-01, from the IPTC-guide gap review):**
- **Export embeds IPTC** as XMP (APP1) *and* the legacy IPTC IIM (APP13 `8BIM`/`0x0404`) block — end-to-end verified with ExifTool reading both from a real exported JPEG. Closes the guide's §12 "naked JPEG" blocker.
- **Rights / wire / contact fields:** Title (Object Name), Rights Usage Terms, Web Statement of Rights, Copyright Status (`xmpRights:Marked`), Creator work email + website (`CreatorContactInfo`), Job Identifier / Transmission Reference — the guide's minimum-plus + muster-template set.
- **AI provenance (IPTC 2025.1, §13):** Digital Source Type (friendly value → controlled-vocab URI) + AI System Used / Version / Prompt Information / Prompt Writer Name (`Iptc4xmpExt:*`).

**Backlog — remaining IPTC-guide items (nice-to-have, not delivery blockers):**
- **FTP / Wire delivery (guide §11)** — ✅ **SHIPPED (2026-07-02).** Push captioned JPEGs straight to an agency/wire endpoint, first-class (decided over the delegate/post-export-hook alternatives). Design decisions (all Niels-approved):
  - **Protocols: FTP + explicit FTPS + SFTP.** FTP/FTPS is an **own minimal client** on `dart:io` sockets (`features/delivery/data/ftp_client.dart` — login, `TYPE I`, `CWD`/`MKD`, passive `STOR` via EPSV→PASV fallback, `AUTH TLS`/`PBSZ`/`PROT P`); the pub FTP packages are stale (pure_ftp) or DMCA'd upstream (ftpconnect). SFTP wraps **dartssh2** (approved dep; password auth only in v1). Both sit behind the `DeliveryClient` interface.
  - **Credentials:** server config (`DeliveryServer`: id/name/protocol/host/port/user/remoteDir) lives under the `deliveryServers` settings key; **passwords go to the platform secret store** via **flutter_secure_storage** (approved dep; Keychain on macOS, libsecret on Linux — the Linux bundle needs `libsecret-1-0` at runtime), keyed `delivery.<serverId>.password` behind the `SecretStore` interface (in-memory double for tests).
  - **Settings UI:** Settings → Delivery servers (add/edit/remove + live "Test connection"); passwords stay dialog-local until Apply, Cancel is a full undo.
  - **Export integration:** the export dialog's Destination becomes a target dropdown (local folder or server). Server target renders to a temp dir (auto-cleaned) or, with "Also keep a local copy", to a real folder; button flips to "Export & upload N". The floating job card goes "Exporting" → "Uploading"; remote names are flattened to basenames (colliding ones keep their path with `/`→`_`).
  - **Retry/error UI:** `runDelivery` uploads over ONE connection (agencies dislike parallel logins), retries each file up to 3× on a fresh connection, and fails the rest fast when even reconnecting fails; the notice bar reports delivered/failed with the first server error verbatim. **Follow-ups shipped 2026-07-02:** a "Retry failed" action on the outcome notice (the rendered temp dir stays alive while a retry is pending), per-server **SFTP key auth** (`keyFilePath`, password becomes the passphrase) and a per-server **accept-self-signed-certificate** toggle for FTPS.
  - **Tests:** everything runs against an in-process `FakeFtpServer` (incl. real TLS upgrade round-trips over a committed self-signed localhost cert). SFTP itself has no fake-server test (needs a real sshd) — verify once against a real endpoint.
  - **Known trap** (doc'd on `FtpClient`): no TLS session reuse on FTPS data connections (`dart:io` limitation) — servers enforcing it (vsftpd `require_ssl_reuse=YES`) reject uploads; use SFTP there. S3/PhotoShelter remain out of scope (Kür).
- **Reverse geocoding** — ✅ **SHIPPED (2026-07-01).** GPS → City/State/Country, fully offline: EXIF GPS lands on `photos.latitude/longitude` (schema v5, backfilled on folder open), the bundled GeoNames gazetteer (`assets/geo/cities.tsv.gz`, ~2.3 MB / 160k places ≥1000 pop., regenerated by `tool/build_gazetteer.sh`, CC-BY 4.0 attribution in README) resolves the nearest *city* (districts/localities/historical places filtered), and a **"From GPS"** button in the M editor's Location section prefills city/state/country/ISO code. The `ReverseGeocoder` interface keeps an online provider pluggable. Batch geocode shipped too: **⋮ → Fill location from GPS** stamps the whole selection (same mark-target rule as Apply metadata template), with a notice reporting fills and skips.
- **Hot codes** — ✅ **SHIPPED (2026-07-01).** One code fills *several* fields at once: a hot code maps a name to a set of IPTC field values (venue block, customer credit block…), edited under Settings → Hot codes. Typing its `=code=` in any M-editor field strips the token and stamps every mapped field (the typed field keeps its remaining text). Values may hold `=text codes=` (expand immediately) and `{variables}` (expand per photo on save). Shares the code-replacement delimiter; stored under the `hotCodes` settings key.
- **Named snapshots** — ✅ **SHIPPED (2026-07-02).** More than one saved template, switchable per customer/assignment: `TemplateSnapshots` (ordered named `IptcTemplate`s + active name, `metadataTemplates` settings key; the legacy single-template key migrates as the active "Default" snapshot). The Settings → Metadata templates section gained a snapshot dropdown (switches the active template) plus New/Rename/Delete — New prompts for a name and opens the template editor. All apply paths (⋮ menu, `T`, apply-on-ingest) stamp the *active* snapshot.
- **Subject Code / IPTC Media Topics** — ✅ **SHIPPED (2026-07-02).** `IptcCore.subjectCodes` (comma-separated `medtop:` QCodes → `Iptc4xmpCore:SubjectCode` rdf:Bag) rides every generic IptcField path (M editor, templates, inspector). The M editor autocompetes over the official vocabulary, bundled like the gazetteer: `tool/build_media_topics.sh` → `assets/iptc/mediatopics.tsv.gz` (10 KB, 1084 active topics, CC-BY 4.0 — attribution in README).
- **Date Created** — ✅ **SHIPPED (2026-07-02).** `XmpData.dateCreated` (derived from EXIF capture time, never user-edited) writes `photoshop:DateCreated` + IIM 2:55/2:60 in sidecars and exports; deliberately excluded from the 'anything worth writing?' check so plain exports stay byte-clean.

**Open questions — resolved:** (a) pulled forward as **Phase 4b** and shipped. (b) Layer 3 shipped (in scope). (c) no new dependency needed (`xml` + existing EXIF; ExifTool used only for verification, not bundled).

---

## 6. The known-hard parts — *read before you start each relevant phase*

These are the things that bite. None are blockers; all are manageable if you expect them.

### 6.1 RAW library bundling (the main native hurdle)
LibRaw is a C/C++ lib that must be present per platform: `.dylib` (macOS, universal/arm64), `.so` (Linux). Decide early: **bundle prebuilt binaries** with the app (simplest UX) vs. depend on a system package (`brew install libraw` / `apt install libraw`). flutter_libraw may not expose every call (e.g. specific thumbnail or processing params) — if so, generate your own bindings with **`ffigen`** straight against `libraw.h`. Isolating all of this in the `packages/cullimingo_raw/` sub-package (per §3) keeps the native mess out of the app and makes the libvips addition later cleaner.

**Status (2026-07-01):** we bundle. `core/native/bundled_libs.dart` resolves a
copy shipped inside the packaged app before falling back to Homebrew/system
paths, on both macOS (`<app>/Contents/libs`, `../libs` from the executable) and
Linux (`<bundle>/lib`). **macOS bundling is done + verified end-to-end
(2026-07-02)**: `tool/bundle_macos.sh` copies + relinks libraw/libvips (and
the `vips-heif` AVIF runtime module, with a `Contents/vipshome/lib → ../libs`
symlink so `VIPSHOME` finds it) to `@executable_path/../libs` via
`dylibbundler`, then **collapses duplicate `LC_RPATH`s** (dylibbundler adds one
per rewritten edge — libvips had 31 — and macOS 15+ dyld rejects duplicates,
so without this pass the app wouldn't launch on a clean Mac). Verified by
running a compiled probe from `Contents/MacOS` (so `@executable_path` matches
the real app): the bundled libvips loads its whole tree and encodes a real
AVIF with no Homebrew present. **Linux bundling is done + verified end-to-end
on Ubuntu 24.04 (2026-07-02)**: `tool/bundle_linux.sh` copies libraw/libvips +
their non-system deps into `<bundle>/lib` (`RUNPATH=$ORIGIN` via `patchelf`),
puts the `vips-heif` module at `<bundle>/<arch>/vips-modules-<ver>/` (vips
searches the multiarch triple, not `lib/`) and bundles libheif's aom-encoder
plugin + libaom into `lib/libheif/plugins/`. A compiled FFI probe (setting the
exact env `VipsEncoder` sets, `LIBHEIF_PLUGIN_PATH` forced to the bundle with
no system fallback) loads libraw and encodes WebP **and AVIF** with zero system
libvips/libraw/libheif/libaom. Two Linux-only runtime-module gaps were found +
fixed here that the macOS path didn't have (see the fix commit). Still in-app
(not yet extracted to `packages/cullimingo_raw/`). **AppImage: done + payload
verified (2026-07-02)** — `tool/build_appimage.sh` wraps the bundle in an
`AppDir` (hand-written `AppRun`, `.desktop`, 256px icon) and seals it with
`appimagetool` (auto-fetched, `--appimage-extract-and-run` so building needs no
FUSE) → `build/linux/Cullimingo-x86_64.AppImage` (~48 MB). Verified by
extracting the AppImage and running the FFI probe against its payload: RAW +
WebP + AVIF all work with no system libs. Built on Ubuntu 24.04; **glibc is
forward-compatible only** — this AppImage runs on same-or-newer glibc (fine for
Niels' CachyOS, which is newer; for wide distribution build on an older base).
`libsecret-1` is a host runtime dep (delivery passwords), not bundled.

### 6.2 Drag-out vs. scroll on macOS
Documented in the wild (late-2025 write-ups): `super_drag_and_drop`'s gesture recognizers can conflict with Flutter's scrolling/selection on macOS, because macOS drag events bypass Flutter's pointer/hit-test system and query registered `NSView`s directly. **Mitigation:** keep super_* for the simple cases, but be ready to drop to a native Swift drag surface (`NSDraggingSource` + `NSFilePromiseProvider`) for the grid specifically, with `hitTest` returning nil on drop zones so scroll/pointer events still pass through to Flutter. Treat Phase 7 macOS drag as "expect one hard day."

### 6.3 Metadata round-trip gaps
Rating and color label round-trip to C1/LR via XMP. **Pick/reject flags do not** (no universal standard; LR keeps them in its catalog). Be explicit in the UI/docs. Keywords (`dc:subject`) round-trip well.

### 6.4 Export look ≠ C1/LR look
Embedded-resize = in-camera JPEG look. Full-render via LibRaw = neutral demosaic. Neither equals Capture One's or Lightroom's color science. That's fine for a culler's proofs/handoff — just don't market it as a developer.

### 6.5 Send-to is inherently asymmetric
AppleScript is macOS-only; Capture One scripting is macOS-only; Lightroom has no clean import API anywhere. On Linux the *targets themselves* differ (Darktable/RawTherapee/GIMP). Model send-to as a per-platform capability set from day one.

### 6.6 OPTIONAL future track — AI culling (explicitly fenced)
AI-culling panels (Blurred / Closed Eyes / Warnings / Key faces / Duplicates) are on-device ML and a **separate project** with its own risk. If you ever want it: run **ONNX Runtime / TFLite** models in the isolate pool — blur via variance-of-Laplacian (cheap, no ML) first, then small models for eyes/faces. Keep it behind a feature flag and a separate package. **Do not let this leak into v1.0 scope.**

---

## 7. UI / design spec — dense dark culling UI

Dark, dense, keyboard-driven. Copy the *chrome* and *density* from the screenshot; map the filters to your real features (not ML).

### Layout
- **Top toolbar:** breadcrumb (Library / Import), thumbnail-size slider, color-label filter dots, rating filter, sort, view toggles, user/menu.
- **Center:** the virtualized thumbnail grid (responsive columns).
- **Right panel (collapsible):** quick filters with live counts (Selected / Highlights / All), color & rating filters, imported **Selections** (Picdrop), saved filters. *(This is where AI-culling tools show ML panels — we show real filters instead.)*
- **Bottom bar:** full-width primary action — **Export N Photos** — exactly like the screenshot's blue button.

### Design tokens (starting palette — refine to taste)
```
bg/base          #0E0E10
surface          #1A1A1D
surface/elevated #26262B
border/divider   #2E2E34
text/primary     #F5F5F7
text/secondary   #A0A0A8
accent/primary   #2D6BFF   (primary buttons, focus ring)
selection        #22C55E   (selected-cell border, like the green frames)
rating/gold      #FACC15
color labels     red #EF4444  yellow #EAB308  green #22C55E  blue #3B82F6  purple #A855F7
```
Spacing scale 4/8/12/16/24; radius 8–10 on cells; subtle 1px borders, not heavy shadows (Impeller renders these crisply on both OSes).

### Thumbnail cell anatomy
`[ image fills cell ]` with overlays: rating stars (bottom-left), color dot (bottom-right), pick/reject + duplicate-count badge (top-left), filename (under image, truncated middle), and a 2px **selection border** (green = selected, accent = focused). Hover reveals quick prev/next arrows (optional).

### Keyboard map (default; make it configurable)
| Key | Action |
|---|---|
| ← → ↑ ↓ | move focus in grid |
| `1`–`5` | set star rating |
| `0` | clear rating |
| `P` / `X` | pick / reject flag |
| `6` `7` `8` `9` `0` | color labels (red/yellow/green/blue/purple) |
| `Space` | toggle select (adds to current selection) |
| `Enter` / `F` | open loupe / fullscreen |
| `[` `]` | prev / next in loupe |
| `E` | export selected |
| `/` | focus filter |

> "Variable-speed scroll" doesn't need a special feature here — a properly virtualized grid + warm two-tier cache *is* the smooth-at-any-speed experience. Get Phase 2 right and you've matched the feel without reverse-engineering the trick.

---

## 8. Milestone → release map

| Tag | Contains | "I can finally…" |
|---|---|---|
| v0.1 | Phase 0–1 | …open a folder and rate RAWs by keyboard |
| v0.2 | Phase 2 | …cull 5,000 files without lag |
| v0.3 | Phase 3 | …ingest my cards with verification |
| v0.4 | Phase 4–5 | …filter, import Picdrop lists, and round-trip to C1/LR |
| v0.5 | Phase 6 | …batch-export JPEG selects |
| v0.9 | Phase 7 | …drag into Photoshop / send to Capture One |
| v1.0 | Phase 8 | …hand it to another photographer |

Build in order. Resist jumping ahead — every phase de-risks the next.
