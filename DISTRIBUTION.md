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
`build/macos/Build/Products/Release/Cullimingo.app`. Package it as a
drag-to-install `.dmg` (what the GitHub Release ships):

```sh
tool/build_dmg.sh               # → build/macos/Cullimingo-arm64.dmg
```

Or just zip the `.app` to share it directly:

```sh
ditto -c -k --keepParent \
  build/macos/Build/Products/Release/Cullimingo.app Cullimingo.zip
```

### Opening it on another Mac (Apple Silicon)

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

- **Apple Silicon only** for now (the bundled dylibs are arm64).
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

`flatpak/io.github.nielsfranke.Cullimingo.yml` repackages the bundled Linux
build — the same one the AppImage wraps — on the GNOME runtime, with the
desktop file, metainfo and icons from `flatpak/` and `assets/branding/`.

The Flatpak app ID (`io.github.nielsfranke.Cullimingo`) differs from the
compiled-in GTK application ID (`cc.nielsbox.cullimingo`, `linux/CMakeLists.txt`).
The runner (`linux/runner/my_application.cc`) takes the ID from `FLATPAK_ID`
when it's set, so inside the sandbox the Wayland app_id, the desktop file and
the icon all match. Outside Flatpak the compiled-in ID stays, because
`path_provider` names the settings + database folder after it — changing it
would strand existing AppImage users' data.

### Build and run locally

```sh
flutter build linux --release
tool/bundle_linux.sh
flatpak install flathub org.gnome.Platform//51 org.gnome.Sdk//51
flatpak-builder --user --install --force-clean flatpak/build-dir \
  flatpak/io.github.nielsfranke.Cullimingo.yml
flatpak run io.github.nielsfranke.Cullimingo
```

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
  Flatpak (`runningInFlatpak`); Flathub delivers updates.
- **Data** lives in `~/.var/app/io.github.nielsfranke.Cullimingo/`, so a
  Flatpak install starts with fresh settings and cache, separate from an
  AppImage install.

### Flathub

Not submitted yet. Flathub requires source-available apps to be built
**entirely from source** inside flatpak-builder (no network during the build),
so this manifest — which repackages the prebuilt bundle — would be rejected.
A Flathub manifest needs:

- the Flutter SDK and every pub package as offline sources (the
  `flatpak-flutter` generator handles this for other Flutter apps on
  Flathub);
- LibRaw, libvips and libheif (with its HEVC decoder and AVIF encoder) as
  source-built modules, unless the runtime already ships them;
- a case for the static permissions: Flathub wants portals wherever one fits,
  so expect questions about `--filesystem=home` and especially
  `--talk-name=org.freedesktop.Flatpak`.

The `io.github.nielsfranke.Cullimingo` ID is verified through the GitHub
account that owns the repo — no website file needed.

## Releases (automated)

`.github/workflows/release.yml` builds both artifacts and attaches them to a
GitHub Release on every `v*` tag push: the AppImage on `ubuntu-24.04` and the
`.dmg` on `macos-14` (arm64), each running the same `tool/` scripts above. The
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
