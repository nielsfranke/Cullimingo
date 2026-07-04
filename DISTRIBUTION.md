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

## Releases (automated)

`.github/workflows/release.yml` builds both artifacts and attaches them to a
GitHub Release on every `v*` tag push: the AppImage on `ubuntu-24.04` and the
`.dmg` on `macos-14` (arm64), each running the same `tool/` scripts above. The
Release notes carry the install steps (chmod for Linux; drag + `xattr -cr` for
macOS). Run it without cutting a tag via the **workflow_dispatch** trigger — it
builds both and leaves them as downloadable run artifacts (no Release). The
published Release is what the in-app update check reads.
