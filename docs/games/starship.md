# Starship

| | |
| --- | --- |
| Id | `starship` |
| Submodule | `games/Starship` (libultraship `eaaf9d0f`, old `src/` layout; Torch `cd92cc0`) |
| Framework | `Starship.framework` (CMake target `Starship`) |
| Data folder | `Documents/Starship/`, config `starship.cfg.json` |
| ROMs | US 1.0 and 1.1 (compressed or not) make `sf64.o2r`. JP, EU (and the Spanish EU hack) and CN make voice packs in `mods/`; the EU and Spanish EU ROMs both write `mods/sf64eu.o2r` |
| Archives | `sf64.o2r` (extracted), `mods/sf64jp.o2r`, `mods/sf64eu.o2r`, `mods/sf64cn.o2r` (optional voice packs, listed on the game's page), `starship.o2r` (the port's own, in the framework) |
| Menu key | F1 (the menu bar; Starship has no Escape menu) |

## Game patch (`patches/starship/starship.patch`)

- `CMakeLists.txt`:
  - The `if(IOS)` block (leetal toolchain, Xcode team) is skipped under `HARBOUR_ROOT`; instead
    it defines `PLATFORM_IOS=1` and includes `cmake/HarbourIOS.cmake`, before libultraship and the
    Ogg/Vorbis lookups.
  - Under `HARBOUR_ROOT` the game is a `SHARED` library passed to `harbour_add_game_framework`
    instead of the `MACOSX_BUNDLE` app (whose resources in `libultraship/ios` don't exist), with
    `__IOS__` added for the target.
  - libultraship's binary directory is `${CMAKE_BINARY_DIR}/libultraship` instead of the source
    tree, and `properties.h` is configured into the build directory, so simulator and device
    builds don't share generated files.
  - libzip's own build directory goes first in its include path. The game's directory-wide
    include directories reach libultraship's dependencies, and `libultraship/src/config/Config.h`
    shadows libzip's `config.h` (case-insensitive file system). Desktop builds take libzip from
    the system.
  - Ogg/Vorbis link as the `Ogg::`/`Vorbis::` targets `HarbourIOS.cmake` provides, without
    `find_package`.
  - Left out under `HARBOUR_ROOT`: the POST_BUILD copy of `config.yml`/`assets/`, and the whole
    host block (TorchExternal, ExtractAssets, GeneratePortO2R, the `gamecontrollerdb.txt`
    download, macOS icons and bundling).
- `src/port/Game.cpp`: `main` is `extern "C" int HarbourGame_Main` under `HARBOUR_IOS`. If
  `sf64.o2r` is missing it shows a message box and returns 1 instead of letting the game ask for a
  ROM it can't pick on iOS and then `exit(1)` the whole app.
- `src/port/Engine.cpp`: default gamepad mappings under `HARBOUR_IOS` (see below).
- `src/port/ui/ImguiUI.cpp`: Settings > Language's "Install JP/EU Audio" button (which reads a
  fixed `baserom.us.rev1.z64` on iOS and then closes the game) is replaced by a note to add the ROM
  in the launcher.

### Controller defaults

Starship's own defaults (`Engine.cpp`) suit desktop pads (B on X, C-down on B, Z/R on the
shoulders, boost/brake on the triggers) but not iHarbour's on-screen controller, which sends
libultraship's default layout: its B would be C-down, Z and R would be C-down and C-left, and
C-left/C-down on the right stick would do nothing. Under `HARBOUR_IOS` every gamepad gets
libultraship's defaults instead: A, B, L (LB), Start and the D-pad on buttons, Z and R on the
triggers, the C buttons on the right stick. Game controllers additionally get C-left (boost) on
Y, C-down (brake) on X, and R on RB. Saved mappings in `starship.cfg.json` still win; the
defaults only apply to pads without one.

## libultraship patch

`eaaf9d0f` has the old layout (`src/Context.cpp`, `src/graphic/Fast3D/backends/gfx_sdl2.cpp`),
so it's its own adaptation of `patches/soh/libultraship.patch`:

- `Context::GetAppBundlePath()`: the framework's directory (`dladdr`) on iOS.
- `Context::GetAppDirectoryPath()`: `SHIP_HOME` on iOS when set (upstream's `__IOS__` branch
  returns `$HOME/Documents` without checking `SHIP_HOME`).
- `SetFullscreenImpl` is a no-op on iOS (`Fast3dWindow` forces fullscreen on mobile).
- `SDL_WINDOW_ALLOW_HIGHDPI` on iOS.
- `isNativeMacOSFullscreenActive`/`toggleNativeMacOSFullscreen` are compiled out on iOS
  (`macUtils.mm` is macOS-only; the link fails otherwise).
- `mInBackground`: pause between `SDL_APP_WILLENTERBACKGROUND` and `SDL_APP_DIDENTERFOREGROUND`,
  `IsFrameReady()` false meanwhile.
- `Fast3dWindow` doesn't offer OpenGL on iOS, where it isn't compiled: picking it would leave no
  renderer. Metal is the only backend.

This libultraship has no CoreAudio player (SDL audio only). ImGui works in points with SDL's
drawable size as the framebuffer scale, the same as Ship of Harkinian, so iHarbour's SDL patch
(`SDL_GL_GetDrawableSize` in pixels for Metal windows) gives full-resolution menus.

## Port glue (`ports/starship/`)

- `GameVersion`: `VER_FILEVERSION_STR` from the configured `properties.h` (the CMake project
  version, `2.0.0`).
- `IdentifyRom`: SHA-1 (`Companion::CalculateHash`) against the game's own `mGameList`
  (`GameExtractor.cpp`). The description stays empty; the catalog names the dump.
- `ExtractRom`: what `GameExtractor::GenerateOTR` does, minus the prompts: Torch as a library,
  specs from the framework, output into the data folder. The archive it must produce is read from
  `config.yml` (following a compressed ROM's `preprocess` target), `mods/` is created first
  (Torch's zip writer fails silently without it), and `torch.hash.yml` is deleted before and after
  (with a leftover one a re-extraction skips every YAML and writes an empty archive). Success
  means that archive exists, isn't empty and is new. The `Companion` is freed afterwards. No
  progress (Torch has no hook).
- `IsArchiveOutdated`: false; Starship has no archive version check.
- `MenuScancode`: F1. `IsMenuOpen`: `Gui::GetMenuOrMenubarVisible()`.
- `port.sh`: `IOS_CMAKE_ARGS=-DCMAKE_POLICY_VERSION_MINIMUM=3.5` (nlohmann_json 3.11.3 and Torch's
  yaml-cpp still declare old minimums, which CMake 4 refuses).
- `port.cmake`: `FMT_CONSTEVAL=` for the game's directory (libultraship, spdlog, Torch, the game).
  The fmt bundled with libultraship's spdlog 1.14.1 doesn't compile its consteval format-string
  checks with Xcode 27's clang; empty, fmt falls back to constexpr checks with the same runtime
  behavior. Desktop macOS builds use Homebrew's spdlog and don't hit it.
- `bundle_game_data` puts into the framework: `starship.o2r`, `config.yml` (with
  `logging: ERROR`, so Torch doesn't log every asset) and `assets/` (the YAML specs, 1 MB).

`starship.o2r` holds the Metal shader (`shaders/metal/default.shader.metal`; the game aborts
without it) and a few HUD textures. It's a plain zip of `port/` (the desktop build runs `torch
pack port starship.o2r o2r`, which does the same), so there is no host build:
`bundle_game_data` zips it with `cmake -E tar` into `harbour-dist/`, only when `port/` changed.

## Updating

- `config.yml`/`mGameList` gain ROMs: add the ROM to the catalog.
- The game starts checking archive versions: implement `IsArchiveOutdated`.
- `GeneratePortO2R` stops being a plain `torch pack port`: revisit `bundle_game_data`.
- The desktop mapping in `Engine.cpp` changes: check the `HARBOUR_IOS` block still matches the
  on-screen controller.

## Known issues

- The ImGui menus aren't scaled for touch (Starship has no ImGui scale setting; its font is 13 pt).
- Torch leaks its zip writer and audio manager per extraction (no way to free them from outside).
