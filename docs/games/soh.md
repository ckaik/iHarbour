# Ship of Harkinian

The reference port: the other games follow its pattern.

- Submodule: `games/Shipwright` (HarbourMasters/Shipwright, `develop`), pinned at `eccbc72cb`.
- libultraship `62e973ae`, Torch `2ab12fe` (the same as Lighthouse's).
- Framework: `ShipOfHarkinian.framework`, CMake target `soh`.
- Data: `Documents/Ship of Harkinian/`, config `shipofharkinian.json`.

## Game patch (`patches/soh/shipwright.patch`)

- `CMakeLists.txt`: includes `cmake/HarbourIOS.cmake` (under `HARBOUR_ROOT`) right before Torch
  and libultraship are added.
- `soh/CMakeLists.txt`:
  - `Darwin` branches become `Darwin|iOS` (Objective-C++ with ARC, the macOS speech synthesizer,
    compiler warnings, no install rule).
  - Under `HARBOUR_ROOT` the target is `add_library(soh SHARED ...)` plus
    `harbour_add_game_framework(soh)`.
  - An iOS compile-definition block: the Clang one minus `ENABLE_OPENGL`, plus `__IOS__`.
  - iOS links libultraship and Torch; `harbour_add_game_framework` adds SDL and the codecs.
  - No POST_BUILD copy of the asset specs on iOS; `port.sh` puts them into the framework.
- `soh/src/code/main.c`: `main` is `HarbourGame_Main` on iOS.

## libultraship patch (`patches/soh/libultraship.patch`)

The full set described in [PORTING.md](../PORTING.md#the-libultraship-patch):

- `Context::GetAppBundlePath()` → the framework's folder (`dladdr`) on iOS.
- `Context::GetAppDirectoryPath()` → `SHIP_HOME` on iOS.
- `SetFullscreenImpl` does nothing on iOS; the window asks for `SDL_WINDOW_ALLOW_HIGHDPI`; the
  macOS native-fullscreen calls are compiled out.
- The game pauses between `SDL_APP_WILLENTERBACKGROUND` and `SDL_APP_DIDENTERFOREGROUND`.
- The CoreAudio (HAL output unit) player is compiled out; iOS uses SDL audio.

Lighthouse and 2 Ship 2 Harkinian use identical copies of this patch. SpaghettiKart's has the
same hunks against its older libultraship.

## Port glue (`ports/soh/`)

- `port.sh`: a macOS tools-only build (`-DSOH_TOOLS_ONLY=ON`, target `GenerateSohOtr`) packs
  `soh.o2r` from `soh/assets/custom`; `bundle_game_data` copies it and `soh/assets/yml` (as
  `assets/`) into the framework.
- `SoHPort.mm`:
  - `IdentifyRom` / `ExtractRom`: the game's `Extractor` (`RunFileStandalone`, `CallTorch`), the
    steps `OTRGlobals::RunExtract` takes for a ROM on the command line, without its ImGui prompts.
    Writes `oot.o2r` or `oot-mq.o2r` with progress.
  - `IsArchiveOutdated`: reads `portVersion` from the archive (an endianness byte, then major,
    minor, patch as 16-bit integers) and compares the major version with `gBuildVersionMajor`, as
    the game does; an archive that doesn't open is outdated too. The game deletes outdated
    archives at start, so the launcher refuses to start it with one.
  - Menu: Escape; `IsMenuOpen` asks libultraship's GUI.

## Tested

On the iOS 27 simulator: a PAL GC debug ROM added through the launcher is recognized by checksum
and extracted to `oot.o2r` with progress, and the game plays its intro in landscape at native
resolution. The framework builds, signs and installs for an iPhone; playing on a device is
untested.

## Updating

See [MAINTENANCE.md](../MAINTENANCE.md#updating-a-game). The Shipwright patch touches only CMake
files and `main.c`, so it rarely conflicts. The libultraship patch is the one to watch when the
submodule's libultraship moves.

## Known issues

- The randomizer, network features (Crowd Control, Sail, Anchor) and speech are built but untested
  on iOS.
- The game's own extraction flow still exists inside the game; its file dialog does nothing on
  iOS. The launcher never starts the game without its archive, so it isn't reached.
