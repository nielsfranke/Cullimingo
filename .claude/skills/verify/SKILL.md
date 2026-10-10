---
name: verify
description: How to verify Cullimingo changes end-to-end by launching the real app window on the desktop and driving it with real key events (Linux).
---

# Verifying Cullimingo end-to-end (Linux)

The surface is a Flutter desktop GUI. No xdotool/ydotool on this machine
(Wayland), so the working handle is Flutter's `integration_test` harness: it
launches the **real app window on the real display** and pumps real key
events through the engine.

## Recipe

1. `integration_test` (SDK-bundled) must be in dev_dependencies:
   ```yaml
   integration_test:
     sdk: flutter
   ```
2. Write the drive under `integration_test/<flow>_test.dart` —
   `integration_test/delete_rejects_e2e_test.dart` is the template. Key moves:
   - Pump `ProviderScope(overrides: [appDatabaseProvider.overrideWithValue(
     AppDatabase(NativeDatabase.memory()))], child: CullimingoApp())` — real
     app, real providers, scratch DB. Call `Vips.warmUpProcess()` first, as
     `main()` does.
   - Open a folder programmatically (the native picker can't be driven):
     `libraryRepository.findOrCreateImport` + `workspace.openImport` +
     `populateImport` — the same calls `_importFolder` makes.
   - The grid Focus has `autofocus: true`; tap a `PhotoCell` first so focus +
     selection are set, then `tester.sendKeyEvent` for cull keys and
     sendKeyDown/Up sequences for ⌘/Ctrl combos (`HardwareKeyboard` state
     follows simulated events).
   - Assert on the notice-bar texts — they're the app's own outcome reports.
   - Screenshots: shell out to `spectacle -abno <path>` (KDE). Pump a frame
     *and give it ~300ms* first, or the grab lands one frame early (a dialog
     asserted present can still be missing from the PNG).
3. Run: `flutter test integration_test/<file>.dart -d linux` (~40s incl.
   debug build; needs the desktop session, not headless).

## Gotchas learned 2026-07-03

- **The test shares the real app's state dir** (`~/.local/share/
  cc.nielsbox.cullimingo/`): the workspace listener persists `lastFolders`
  into the real `settings.json`. Back it up first, restore after.
- **`gio trash` refuses tmpfs** ("Trashing on system internal mounts is not
  supported") — put scratch shoots under `$HOME` (e.g. `~/.cache`), never
  `/tmp`, or every trash op fails (the app then correctly keeps the files
  and notices "N failed").
- **No gvfs daemon on this box**: `gio trash --list/--restore` don't work.
  Verify trash contents by reading `~/.local/share/Trash/{files,info}`
  directly; match `.trashinfo` `Path=` entries against your scratch dir so
  pre-existing user trash never collides. Clean up: rename files back +
  delete the matching `.trashinfo`.
- The pool's libvips worker threads can keep the process alive at exit in
  plain `flutter test`; the integration runner kills the app binary itself,
  so full-real vips is fine here.

## From the Mac: Docker + Xvfb (verified 2026-10-10)

No Linux desktop needed: run the same `integration_test` drive in the
`cullimingo-build` image (Flutter SDK in the `cullimingo-sdk` volume) under
Xvfb. `integration_test/trash_fallback_e2e_test.dart` is the template; it
reads `SHOOT_ROOT` / `SHOTS_DIR` and screenshots with ImageMagick `import`.

```bash
docker run --rm --tmpfs /shoots:exec,size=200m \
  -v "$PWD":/work -v cullimingo-sdk:/sdk -v cullimingo-pub-cache:/root/.pub-cache \
  -w /work -e PATH="/sdk/flutter/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  -e SHOOT_ROOT=/shoots -e SHOTS_DIR=/work/build/e2e-shots -e LIBGL_ALWAYS_SOFTWARE=1 \
  cullimingo-build bash -c "
    git config --global --add safe.directory '*'
    apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
      xvfb imagemagick libglib2.0-bin dbus-x11 >/dev/null
    Xvfb :99 -screen 0 1600x1000x24 & export DISPLAY=:99; sleep 1
    flutter pub get >/dev/null
    dbus-run-session -- flutter test integration_test/<file>.dart -d linux"
```

- ~4 min incl. apt + debug build; the container's settings are fresh, so
  dismiss the first-run welcome (`Got it`) before driving the grid.
- A `--tmpfs` shoot makes `gio trash` refuse, like an SMB share via gvfs —
  that's how the "Trash not available" fallback (GitHub #14) is reached. Put
  the shoot on the container's overlay fs instead to exercise the real trash.
- Screenshots land in `build/e2e-shots/` on the Mac; a dialog may be caught
  mid fade-in.
