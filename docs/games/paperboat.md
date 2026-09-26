# PaperBoat

| | |
| --- | --- |
| Id | `paperboat` |
| Submodule | `games/PaperBoat` (libultraship fork `d472d6bc`, JeodC lus-converge; Torch fork `106f4e3`, JeodC/Torch-LH `pm64`) |
| Framework | `PaperBoat.framework` (CMake target `Paperboat`) |
| Data folder | `Documents/PaperBoat/`, config `paperboat.cfg.json` |
| ROM | US only, `.z64` SHA-1 `3837f44cda784b466c9a2d99df70d77c322b97a0` |
| Archives | `pm64.o2r` (extracted from the ROM), `paperboat.o2r` (the port's own, in the framework) |
| Menu key | Escape |

## Game patch (`patches/paperboat/paperboat.patch`)

- `CMakeLists.txt`:
  - The `if(IOS)` block skips `cmake/ios.toolchain.cmake` (leetal) and its `DEPLOYMENT_TARGET`
    check under `HARBOUR_ROOT`, and checks `CMAKE_OSX_DEPLOYMENT_TARGET >= 16.3` instead
    (`std::format` needs `std::to_chars`). It keeps the global `PLATFORM_IOS=1`/`__IOS__`
    defines, `BUNDLE_ID` and `SIGN_LIBRARY` (libultraship's iOS block reads them).
  - Includes `cmake/HarbourIOS.cmake` right before `add_subdirectory(external/libultraship)`.
  - Under `HARBOUR_ROOT` the game is a `SHARED` library passed to `harbour_add_game_framework`
    instead of the `MACOSX_BUNDLE` app.
  - The POST_BUILD copy of `config.yml`, `assets/` and `paperboat.o2r` into the bundle is left out
    under `HARBOUR_ROOT`; `bundle_game_data` does it.
- `src/port/Game.cpp`: `main` is `extern "C" int HarbourGame_Main` under `HARBOUR_IOS`.
- `src/port/Engine.cpp`:
  - The config path passed to `CreateUninitializedInstance` is plain `paperboat.cfg.json` under
    `HARBOUR_IOS`. The game prefixes it with the app directory and libultraship prefixes it again,
    which only works while the app directory is `.` (upstream bug; Android is affected too).
  - `CanRelaunch()` is false and `RelaunchIfRequested` never `execv`s on `__IOS__`. The mod menu
    then says "Apply" (takes effect next launch) instead of "Apply & Restart".
- `CreateFontWithSize` (`Engine.cpp`) rasterizes the game's fonts at the display's density on
  `__IOS__` (`RasterizerDensity`, as libultraship does for its default font), so menu text is crisp
  with ImGui in points (see below).
- `src/port/ui/TouchControls.cpp`: the engine's own touch pad (`gTouchControls.Enabled`) defaults
  to off under `HARBOUR_IOS`. iHarbour draws its own controller; players can still turn the
  engine's on under Settings > Controls.

## libultraship patch

The fork already has HiDPI, `SDL_GetRendererOutputSize` sizes, a pinned Metal drawable size, and
the macOS fullscreen/CoreAudio guards in `gfx_sdl2.cpp`/`Audio.cpp`. The patch adds:

- `Context::GetAppBundlePath()`: the framework's directory (`dladdr`) on iOS; the main bundle only
  if that fails.
- `Context::GetAppDirectoryPath()`: `SHIP_HOME` on iOS when set.
- `SetFullscreenImpl` is a no-op on iOS. The fork forces fullscreen on mobile (`gameMode`), which
  would call `SDL_SetWindowDisplayMode`/`SDL_SetWindowFullscreen` with the portrait display mode.
- `mInBackground`: pause between `SDL_APP_WILLENTERBACKGROUND` and `SDL_APP_DIDENTERFOREGROUND`,
  `IsFrameReady()` false meanwhile.
- `AudioPlayer.h` doesn't include `CoreAudioAudioPlayer.h` on iOS (cosmetic).
- ImGui in points on iOS (`Fast3dGui.cpp`). Upstream, the fork runs ImGui in drawable pixels on
  iOS (touches scaled up to match), so on a 3x screen every menu is a third of the size it has in
  the other games. With the patch, iOS takes the macOS path: `ImGui_ImplSDL2_NewFrame` sets `DisplaySize` in points and
  `DisplayFramebufferScale` from the renderer, touches go to ImGui unscaled (SDL reports points),
  `ComputeDpiScale()` returns pixels per point (renderer output / window size, used for
  `RasterizerDensity`), and the game's internal render size is scaled by it, so 100% internal
  resolution is still native pixels. The Metal screen framebuffer stays in pixels
  (`GfxRenderingAPIMetal::NewFrame`), which is what ImGui's draw data asks for.

The fork never calls `SDL_GL_GetDrawableSize` on iOS, so iHarbour's SDL patch (which makes it
return pixels for Metal windows) doesn't affect it.

## Port glue (`ports/paperboat/`)

- `GameVersion`: `major.minor.patch` from `src/port/build.c` (`1.0.1`).
- `IdentifyRom`: `GameExtractor::DetectVersion(rom, <framework>)`, the SHA-1 lookup in the bundled
  `config.yml`.
- `ExtractRom`: what the Android launcher does (`src/port/android/AndroidBridge.cpp`):
  `GameExtractor::RunStandalone` + `GenerateOTRTo(done, total, <framework>, <data folder>)`.
  Progress is the number of asset YAMLs processed out of `PAPERBOAT_ASSET_YAML_COUNT`. Once the ROM
  is accepted, and again at the end, it deletes `torch.hash.yml` (Torch's cache: with a leftover
  one, a re-extraction skips every YAML and writes an empty archive). Torch builds the archive in
  memory and writes it only at the end, so an existing `pm64.o2r` survives a failed run; success
  means a non-empty `pm64.o2r` that is new or has a new modification time.
- `IsArchiveOutdated`: false. `pm64.o2r` has a `portVersion`, but the game never checks it.
- `bundle_game_data` puts into the framework: `paperboat.o2r`, `config.yml`, `assets/` (2.5 MB;
  the game exits at startup if `assets/` is missing, even with `pm64.o2r` present).

`paperboat.o2r` is a plain zip of `port/`. The iOS build's own `GeneratePortO2R` target (a
dependency of `Paperboat`) writes it to the build directory, and `bundle_game_data` copies it from
there (the build directory `build-engine.sh` passes as its second argument), so there is no host
build and an unchanged build is a no-op.

## Updating

- Regenerate the game patch with `git -C games/PaperBoat diff --ignore-submodules=all`: libultraship
  is a submodule of the game, and while its patch is applied a plain `git diff` adds a
  `Subproject commit ...-dirty` hunk that doesn't apply.
- `config.yml` gains ROMs: add them to the catalog's `roms`.
- The game starts checking `portVersion`: implement `IsArchiveOutdated` (see `SoHPort.mm`).
- The `if(IOS)` block or the extractor API (`GenerateOTRTo`) changes upstream: regenerate the patch
  and revisit `ExtractRom`.

## Known issues

- Extraction runs Torch in-process with a high memory peak (the ROM, parse results and the whole
  archive, which miniz holds in memory until it writes it; Android runs Torch in a process of its
  own). Watch for jetsam on small-RAM iPhones.
- Torch changes spdlog's global pattern and level while it runs.
- `exit()` paths in `GameEngine::RunExtract` (missing `assets/` or `paperboat.o2r`, failed
  extraction) only trigger if the framework is incomplete or the launcher starts the game without
  `pm64.o2r`.
- libultraship's crash handler installs signal handlers only on Linux/Windows, so nothing stays
  behind in the launcher's process.
- `configure_file` writes `src/port/build.c` into the source tree (gitignored).
