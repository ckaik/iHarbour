# Ghostship

| | |
| --- | --- |
| Id | `ghostship` |
| Submodule | `games/Ghostship` (libultraship `93a1a417`, the newer `ship/`+`fast/` layout; Torch `106621f`) |
| Framework | `Ghostship.framework` (CMake target `Ghostship`) |
| Data folder | `Documents/Ghostship/`, config `ghostship.cfg.json` |
| ROMs | US and JP (`.z64`); both make `sm64.o2r` |
| Archives | `sm64.o2r` (extracted), `ghostship.o2r` (the port's own, in the framework) |
| Menu key | Escape |

## Game patch (`patches/ghostship/ghostship.patch`)

- `CMakeLists.txt`:
  - `cmake_policy(SET CMP0126 NEW)` under `HARBOUR_ROOT`. The CVar names in
    `cmake/lus-cvars.cmake` are normal variables that libultraship's `cvars.cmake` then declares as
    cache entries; with the policy OLD (the project asks for CMake 3.20) the first configure gets
    libultraship's defaults (`gInternalResolution`) and every later one the game's
    (`gSettings.InternalResolution`). NEW makes it always the game's.
  - The `if(IOS)` block keeps `PLATFORM_IOS=1`/`__IOS__` but skips the in-tree leetal toolchain
    under `HARBOUR_ROOT`. `cmake/HarbourIOS.cmake` is included right after it.
  - Under `HARBOUR_ROOT` the game is a `SHARED` library passed to `harbour_add_game_framework`
    instead of the `MACOSX_BUNDLE` app, without `ENABLE_EXPORTS`.
  - Left out under `HARBOUR_ROOT`: the POST_BUILD copy of `config.yml`/`assets/`, and the whole
    host block (TorchExternal, ExtractAssets, GeneratePortO2R, the `gamecontrollerdb.txt`
    download, macOS icons and bundling).
- `src/port/Game.cpp`: `main` is `extern "C" int HarbourGame_Main` under `HARBOUR_IOS`.
- `src/port/ui/TouchControls.cpp`: the game's own on-screen controller (with its own menu
  button) defaults to off under `HARBOUR_IOS`; Settings > Controls can still turn it on.
- `src/port/Engine.cpp`: under `HARBOUR_IOS` `ScaleImGui` multiplies the menu scale by the
  screen's pixels per point, and `CreateFontWithSize` bakes fonts at that density instead of
  twice it; see below.

## libultraship patch

`93a1a417` already has iOS work: HiDPI window, Metal sizes from
`SDL_GetRendererOutputSize`, pixel-space ImGui with touch coordinates scaled to pixels, no macOS
fullscreen calls on iOS, CoreAudio left out of `Audio.cpp`. The patch adds:

- `Context::GetAppBundlePath()`: the framework's directory (`dladdr`) on iOS; the main bundle only
  if that fails.
- `Context::GetAppDirectoryPath()`: `SHIP_HOME` on iOS when set.
- `SetFullscreenImpl` is a no-op on iOS (`Fast3dWindow` starts mobile games fullscreen).
- `mInBackground` in `GfxWindowBackendSDL2`: pause between `SDL_APP_WILLENTERBACKGROUND` and
  `SDL_APP_DIDENTERFOREGROUND`, `IsFrameReady()` false meanwhile.
- `CoreAudioAudioPlayer` compiled out on iOS (`CoreAudioAudioPlayer.h`/`.cpp`, and its include in
  `AudioPlayer.h`): it uses the macOS-only HAL output unit and doesn't compile against the iOS
  SDK.
- `Fast3dGui::ComputeDpiScale()` returns the screen's pixels per point on iOS instead of 1.

### Menu size

This libultraship runs ImGui in pixels on iOS (`Fast3dGui::ImGuiWMNewFrame` sets `DisplaySize`
to the renderer's output size and scales touch coordinates to match). Nothing there depends on
`SDL_GL_GetDrawableSize`, so iHarbour's SDL patch doesn't affect it and touches aren't scaled
twice. At the game's scale 1 the menus would be a third of their size on a 3x iPhone, though.
With `ComputeDpiScale()` returning the screen's density, fonts are rasterized for it and
`ScaleImGui` makes `gSettings.ImGuiScale` count in points, like the other games: the launcher's
Menu Size gives menu scales 0.75, 1, 1.5 and 2 in points. The game bakes its fonts at twice the
density so the largest menu size stays sharp; on a 3x iPhone that 6x atlas (two families, three
sizes, Font Awesome merged into each) would be around 28 M pixels, over 100 MB as the RGBA
texture, so under `HARBOUR_IOS` it bakes at the screen's density only: Large and Extra Large are
slightly soft.

## Port glue (`ports/ghostship/`)

- `GameVersion`: `gBuildVersion` (`Nautilus Alfa (3.0.0)`).
- `IdentifyRom`: `GameExtractor::DetectVersion` (SHA-1 against the game's list). The description
  stays empty; the catalog names the dump.
- `ExtractRom`: `GameExtractor::GenerateOTRTo` written out (new `Companion` with specs from the
  framework, `WritePortVersion`, `Init(Binary)`), so that:
  - Torch writes into a fresh `Documents/Ghostship/.extract/`, then `sm64.o2r` is moved over the
    old one. A leftover `torch.hash.yml` in Torch's output folder makes it skip every spec it
    lists as extracted and write an almost empty archive, and a failed extraction keeps the old
    archive.
  - Progress counts spec files reaching Torch's export phase (`SetPhaseCallback`, phase 2) against
    the number of YAML files in the ROM's `assets/ymls/<us|jp>` (422/420). Torch's own counter
    restarts for each file.
  - Success means `sm64.o2r` exists and isn't empty; Torch returns silently on several errors.
  - The `Companion` is never deleted (`~Companion` double-frees, see `AndroidBridge.cpp`), so each
    extraction leaks the ROM and its decoded assets until the app quits.
  - The game's `regenerate_o2r` marker is removed after a successful extraction.
- `IsArchiveOutdated`: mirrors `RunExtract`: outdated if the `regenerate_o2r` marker exists, the
  zip doesn't open, `portVersion` (big-endian u16 major, minor, patch; no endianness byte) has
  another major/minor than `gBuildVersionMajor/Minor` (0.0.0 passes, as in the game), or `version`
  holds a ROM CRC that is neither US (`0xFF2B5A63`) nor JP (`0x0E3DAA4E`) in either byte order.
- `MenuScancode`: Escape. `IsMenuOpen`: `Gui::GetMenuOrMenubarVisible()` through
  `ShipCompat::GetWindow()`.
- `bundle_game_data` puts into the framework: `ghostship.o2r`, `config.yml` (with
  `logging: ERROR` for both ROMs, since Torch otherwise sets spdlog to debug and logs every asset)
  and `assets/` (the YAML specs; the game also refuses to start without `assets/` there).

`ghostship.o2r` holds fonts, textures and the shaders; the game needs it (it checks that it
exists, not its version). The desktop build copies libultraship's `src/fast/shaders` over
`port/shaders` and runs `torch pack port ghostship.o2r o2r -u 3.0.0`: a zip of `port/` plus
`portVersion`. `bundle_game_data` does the same with Python's `zipfile` (no host build of Torch),
into `build/ghostship/`, only when `port/`, the shaders, `CMakeLists.txt` (the version) or
`port.sh` changed.

## Settings (as compiled)

`gSettings.InternalResolution` (float), `gSettings.MSAAValue`, `gSettings.TextureFilter`,
`gSettings.InterpolationFPS` (default 30), `gSettings.MatchRefreshRate`, `gSettings.ImGuiScale`
(index 0-3), `gSettings.Volume.Master` (int 0-100). Check with
`grep -o 'CVAR_INTERNAL_RESOLUTION=[^ ]*' build/ghostship/*/build.ninja`.

## Updating

- The project version's major or minor changes: extracted archives become outdated (the launcher
  re-extracts); nothing to change here.
- `config.yml` gains ROMs: add them to the catalog. `IsArchiveOutdated` knows the CRCs from
  `include/sm64.h`; update `kGameVersionUS/JP` if the list there grows.
- `GeneratePortO2R` stops being a plain `torch pack port`: revisit `ghostship_pack_port_archive`.
- libultraship stops running ImGui in pixels on iOS: drop the `ComputeDpiScale`/`ScaleImGui`
  changes.

## Known issues

- Each extraction leaks Torch's `Companion` (ROM plus decoded assets, tens of MB) until the app
  quits.
- Menu sizing hasn't been checked on a device.
