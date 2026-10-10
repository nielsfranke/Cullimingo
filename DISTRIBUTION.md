# Distributing Cullimingo

## macOS (unsigned)

Cullimingo is **not** signed with an Apple Developer ID or notarized (we don't
pay for the Apple Developer Program yet). The app is self-contained — the native
`libvips`/`libraw` dylibs are bundled — so it does **not** need Homebrew, but
macOS Gatekeeper will warn because it can't verify the developer.

### Build a distributable .app

```sh
flutter build macos --release
tool/bundle_macos.sh            # bundles the native dylibs into the .app
```

This produces a self-contained but **ad-hoc-signed (unsigned)**
`build/macos/Build/Products/Release/Cullimingo.app`, thinned to this Mac's
architecture. Package it as a drag-to-install `.dmg` (what the GitHub Release
ships):

```sh
tool/build_dmg.sh               # → build/macos/Cullimingo-arm64.dmg
```

#### Intel (x86_64) build

Homebrew no longer ships Intel bottles, so the Intel build bundles a native
stack cross-compiled from source on Apple Silicon (`brew install meson ninja
nasm cmake pkg-config dylibbundler`; Rosetta runs glib's build helpers):

```sh
tool/build_macos_deps.sh x86_64   # → build/macos-deps/x86_64/prefix (~20 min once)
flutter build macos --release
CULLIMINGO_MACOS_ARCH=x86_64 \
CULLIMINGO_DEPS_LIB=$PWD/build/macos-deps/x86_64/prefix/lib \
  tool/bundle_macos.sh
tool/build_dmg.sh                 # → build/macos/Cullimingo-x86_64.dmg
```

`build_macos_deps.sh` builds LibRaw, libvips and their tree (glib, libjpeg-turbo,
libpng, lcms2, libexif, libwebp, libheif + libde265/dav1d/aom) with the same
feature set as the Flatpak, for macOS 12+. The result runs on Apple Silicon
too, under Rosetta — handy for checking the Intel build without an Intel Mac.

Why thin at all: Flutter builds a universal app, and a universal app with
arm64-only dylibs *starts* on an Intel Mac but can't load LibRaw — every RAW
stays a grey placeholder while JPEGs (decoded in Dart) look fine. Thinned, a
Mac refuses the wrong build up front.

Or just zip the `.app` to share it directly:

```sh
ditto -c -k --keepParent \
  build/macos/Build/Products/Release/Cullimingo.app Cullimingo.zip
```

### Opening it on another Mac

Because the app isn't notarized, a freshly downloaded copy is quarantined and
Gatekeeper blocks it. Pick **one**:

**A. Right-click → Open (simplest, no Terminal)**
1. Move `Cullimingo.app` to `/Applications`.
2. Right-click (or Control-click) it → **Open** → **Open** in the dialog.
   (Plain double-click won't offer this; the right-click menu does.)
3. If macOS still refuses, open **System Settings → Privacy & Security**, scroll
   down, and click **Open Anyway**, then reopen.

**B. Clear the quarantine flag (Terminal, most reliable)**
```sh
xattr -dr com.apple.quarantine /Applications/Cullimingo.app
open /Applications/Cullimingo.app
```

If you ever see *"Cullimingo is damaged and can't be opened"*, that's the
quarantine flag on an un-notarized app — option **B** clears it.

### Notes

- Two builds: `Cullimingo-arm64.dmg` (Apple Silicon) and
  `Cullimingo-x86_64.dmg` (Intel, macOS 12+). Each is single-architecture.
- The first launch may still prompt for access to network/removable volumes —
  that's the normal macOS file-access prompt, click **Allow**.
- A proper signed + notarized build (no warnings) needs the paid Apple Developer
  Program; deferred. See `BUILD_PLAN.md` §6.1.

## Linux (AppImage)

Like the macOS build, the AppImage is self-contained: LibRaw, libvips and
their non-system dependencies (incl. the WebP/AVIF runtime modules) are
bundled, so the app runs with **no distro packages installed**.

### Build an AppImage

```sh
flutter build linux --release
tool/bundle_linux.sh            # bundles the native .so's into the app bundle
tool/build_appimage.sh          # wraps the bundle into an AppImage
```

This produces `build/linux/Cullimingo-x86_64.AppImage` (~48 MB) — the file the
GitHub Release ships.
`build_appimage.sh` fetches `appimagetool` itself if it isn't already on your
machine, and builds with `--appimage-extract-and-run`, so packaging doesn't
need FUSE installed.

### Running it

```sh
chmod +x Cullimingo-x86_64.AppImage
./Cullimingo-x86_64.AppImage
```

### Notes

- **x86_64 only** for now.
- **glibc is forward-compatible only**: an AppImage built on a given distro
  runs on that glibc version *or newer*, not older. Build on the oldest distro
  you need to support (this project currently builds on Ubuntu 24.04).
- `libsecret-1` (delivery-server passwords) is a **host runtime dependency**,
  not bundled — install it via your distro's package manager
  (`libsecret-1-0` on Debian/Ubuntu) if it isn't already present.
- **Host-preferred libs** (`<bundle>/lib/fallback/`, currently `librsvg`):
  libvips depends on them, but so does the host's GTK stack — gdk-pixbuf's SVG
  loader dlopens librsvg the first time GTK draws an SVG icon (the file
  chooser). The loader dedupes by soname, so a bundled copy already in the
  process would be what the host's plugin binds to; if ours is older, the
  plugin dies on a missing symbol and GTK aborts the app (GitHub #2). So they
  sit outside `RUNPATH`, and the app dlopens the host's copy before libvips,
  taking ours only when the host has none (`core/native/bundled_libs.dart`).

### In-place updates

`build_appimage.sh` embeds update info
(`gh-releases-zsync|nielsfranke|Cullimingo|latest|Cullimingo-x86_64.AppImage.zsync`)
and writes `Cullimingo-x86_64.AppImage.zsync` next to the AppImage; the
Release publishes both. AppImageUpdate, Gear Lever and AppImageLauncher read
the embedded info and fetch only the changed blocks of the newest
non-prerelease. Check a build with
`./Cullimingo-x86_64.AppImage --appimage-updateinformation`.

## Linux (Flatpak)

Cullimingo ships its Flatpak from its **own signed repository on GitHub
Pages** (<https://nielsfranke.github.io/Cullimingo/>), not Flathub (see
"Flathub" below). Installed copies update through `flatpak update` or the
software centre, and every Release also carries `.flatpak` bundles.

The Flatpak is built **entirely from source**, offline inside
flatpak-builder's sandbox. `flatpak/flatpak-flutter.yml` is the input; the
[flatpak-flutter](https://github.com/TheAppgineer/flatpak-flutter)
pre-processor turns it into the real manifest
(`io.github.nielsfranke.Cullimingo.yml`) plus `generated/` modules and
sources: the Flutter SDK, every pub package, and the Rust toolchain + crates
for `super_native_extensions`. Those are regenerated on every build and not
kept in the repo.

What the manifest builds, on the GNOME 51 runtime:

- **LibRaw 0.22**, **libvips** (HEIF linked in, no modules) and our own
  **libheif** with **libde265** (HEIC/HIF), plus the runtime's aom (AVIF
  export) and dav1d. The runtime already has JPEG, PNG, WebP, TIFF, lcms2,
  libexif and librsvg.
- **SQLite** from the amalgamation, via the `sqlite3` package's `source`
  hook mode (`flatpak/foreign.json` + a `user_defines` block the manifest
  appends to `pubspec.yaml`), instead of the package's default prebuilt
  download.
- **jsoncpp**, build-time only (flutter_secure_storage_linux's CMake).
- **The app**, from the git tag. The Flutter bundle goes straight into
  `/app`, so its `lib/` is `/app/lib`, where the modules above install — the
  bundled-lib lookup (`core/native/bundled_libs.dart`) finds libvips and
  LibRaw there unchanged. glib/gobject resolve by soname
  (`core/cache/vips.dart`), which also covers aarch64.

The Flatpak app ID (`io.github.nielsfranke.Cullimingo`) differs from the
compiled-in GTK application ID (`cc.nielsbox.cullimingo`, `linux/CMakeLists.txt`).
The runner (`linux/runner/my_application.cc`) takes the ID from `FLATPAK_ID`
when it's set, so inside the sandbox the Wayland app_id, the desktop file and
the icon all match. Outside Flatpak the compiled-in ID stays, because
`path_provider` names the settings + database folder after it — changing it
would strand existing AppImage users' data.

### Build locally

```sh
tool/build_flatpak.sh "$(git rev-parse HEAD)"   # commit must be on GitHub
flatpak install --user build/flatpak/Cullimingo-$(flatpak --default-arch).flatpak
flatpak run io.github.nielsfranke.Cullimingo
```

`build_flatpak.sh` fetches flatpak-flutter at a pinned commit, pins the
manifest's app source to the given commit, generates, installs the GNOME 51
runtime/SDK + llvm22 if missing, builds with `flatpak-builder --sandbox`, and
exports `build/flatpak/repo` plus a bundle. It needs network (generator +
runtime downloads) and a Linux host with flatpak-builder — or privileged
Docker: `ghcr.io/flathub-infra/flatpak-github-actions:gnome-51` is what CI
uses. The app source is fetched from GitHub, so the commit must be pushed.

### Releases and the repo

`release.yml` runs it on every `v*` tag:

1. `build-flatpak` builds natively on `ubuntu-24.04` (x86_64) and
   `ubuntu-24.04-arm` (aarch64) in the image above, signing each exported
   commit.
2. `release` attaches `Cullimingo-x86_64.flatpak` and
   `Cullimingo-aarch64.flatpak` to the GitHub Release. A bundle install also
   adds the Pages repo as the app's origin, so it updates like a repo install.
3. `publish-flatpak` (stable tags only — not `-rc` pre-releases) runs
   `tool/publish_flatpak_repo.sh`: a fresh repo holding just the new app +
   Locale commits for both arches (no history, no Debug extension, so Pages
   stays small; clients update from any older commit), a signed summary, the
   `cullimingo.flatpakrepo` / `.flatpakref` files and an install page. It's
   deployed with `actions/deploy-pages`; the `github-pages` environment allows
   `v*` tags.

**Signing key:** RSA 4096, "Cullimingo Flatpak repository", fingerprint
`430D C906 4406 D37A DED9  A827 627F BB55 9766 1E4E`. The public key is
`flatpak/cullimingo-repo.gpg` (embedded in the `.flatpakrepo`, `.flatpakref`
and bundles); the private key is the `FLATPAK_GPG_PRIVATE_KEY` Actions secret,
with no passphrase so CI can use it. **Keep an offline backup** of the private
key: installed copies trust exactly this key, so losing it means every user
has to re-add the repo.

### Sandbox

- **Files:** `--filesystem=home` plus `/media`, `/run/media` and `/mnt`.
  Cullimingo works on photos in place and writes XMP sidecars next to them,
  which the per-file document portal can't grant.
- **Host tools:** `--talk-name=org.freedesktop.Flatpak`, so
  `core/files/host_command.dart` can run `gio trash` (the sandbox's own trash
  would be app-private), `lsblk`/`udisksctl` (card auto-mount), `ffmpeg` /
  `ffmpegthumbnailer` (video posters, via a temp dir under the app's cache
  dir, since the sandbox `/tmp` is private), the user's "Send to" editors and
  the FileManager1 reveal via `flatpak-spawn --host`. `xdg-open` stays in the
  sandbox and goes through the OpenURI portal.
- **Updates:** the in-app update check and its setting are hidden under
  Flatpak (`runningInFlatpak`); `flatpak update` delivers updates.
- **Data** lives in `~/.var/app/io.github.nielsfranke.Cullimingo/`, so a
  Flatpak install starts with fresh settings and cache, separate from an
  AppImage install.

### Flathub

**Not submitted, and this manifest can't be submitted as is.** Flathub's
[generative AI policy](https://docs.flathub.org/docs/for-app-authors/requirements#generative-ai-policy)
says manifests "must not contain AI-generated or AI-assisted content", and
disclosure doesn't exempt them. The manifest in `flatpak/` was written with an
AI agent. The policy also forbids AI tools from opening the submission PR or
writing its description, commits or review replies, and it requires
disclosing AI-generated material in the app itself. Reviewers decide case by
case whether that material is acceptable.

A Flathub submission therefore needs a manifest written by a human. The
findings recorded above are facts about the build: what the GNOME 51 runtime
already ships, the sqlite3 `source` hook mode, the `/app` layout, and the
soname fallback. The submitter opens the PR personally against `new-pr` and
fills in the template, including a demo video and the AI disclosure. Expect
review questions about `--filesystem=home` and
`--talk-name=org.freedesktop.Flatpak` (see Sandbox for why each is needed).

The `io.github.nielsfranke.Cullimingo` ID is verified through the GitHub
account that owns the repo — no website file needed.

## Releases (automated)

`.github/workflows/release.yml` builds both artifacts and attaches them to a
GitHub Release on every `v*` tag push: the AppImage on `ubuntu-24.04` and both
`.dmg`s on `macos-14` (arm64 — the x86_64 one cross-compiled, its native stack
cached per `build_macos_deps.sh` revision), each running the same `tool/`
scripts above. The
Release notes carry the install steps (chmod for Linux; drag + `xattr -cr` for
macOS). Run it without cutting a tag via the **workflow_dispatch** trigger — it
builds both and leaves them as downloadable run artifacts (no Release). The
published Release is what the in-app update check reads.

### Before tagging

1. Run the real-sample check (`test/core/raw/raw_samples_test.dart`) against
   the samples folder, on the same LibRaw the release links — Homebrew's for
   the `.dmg` (`CULLIMINGO_LIBRAW=$(brew --prefix libraw)/lib/libraw.dylib`):

   ```sh
   CULLIMINGO_SAMPLES=~/.cache/cullimingo/samples \
     flutter test test/core/raw/raw_samples_test.dart
   ```

   Real camera files (HLG/HE* NEFs, an SDR NEF, a Sony HIF, …) never go into
   the repo; the test is skipped without `CULLIMINGO_SAMPLES`. Its doc comment
   lists the `expectations.json` values. Do the same **before any LibRaw
   upgrade** (a `brew upgrade` changes what the next `.dmg` bundles): a new
   LibRaw can pick a different embedded thumbnail or decode what it used to
   refuse, and only real files show it.
2. Date the `## Unreleased` section of `CHANGELOG.md` with the version — the
   Release notes are extracted from `## <version>`.
3. Bump `version:` in `pubspec.yaml`, run `dart run tool/gen_version.dart`,
   commit `chore(release): X.Y.Z`, push `main`, then push the single `vX.Y.Z`
   tag (never several tags in one push: GitHub drops the events and no
   release runs).
