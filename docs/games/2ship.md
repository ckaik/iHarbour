# 2 Ship 2 Harkinian

| | |
| --- | --- |
| Id | `2ship` |
| Submodule | `games/2ship2harkinian` (libultraship `7f9b86a5`, ZAPDTR `ee3397a3`, OTRExporter `32e088e2`) |
| Framework | `TwoShip2Harkinian.framework` (CMake target `2ship`; a framework name can't start with a digit) |
| Data folder | `Documents/2 Ship 2 Harkinian/`, config `2ship2harkinian.json` |
| ROMs | NTSC-U 1.0 (`d6133ace5afaa0882cf214cf88daba39e266c078`), NTSC-U GC (`9743aa026e9269b339eb0e3044cd5830a440c1fd`), `.z64` SHA-1 |
| Archives | `mm.o2r` (extracted from the ROM), `2ship.o2r` (the port's own, in the framework) |
| Menu key | Escape |

## Game patch (`patches/2ship/2ship2harkinian.patch`)

- `CMakeLists.txt`:
  - Includes `cmake/HarbourIOS.cmake` before `add_subdirectory(libultraship)`.
  - Under `HARBOUR_ROOT`, links `OTRExporter` to `tinyxml2::tinyxml2` and `libzip::zip`. It
    includes their headers without linking them; desktop builds find them in `/opt/homebrew/include`
    or `/usr/include`, the iOS build has them only through the FetchContent targets.
  - `HARBOUR_TOOLS_ONLY` (macOS host build): adds libultraship, ZAPD and OTRExporter but not the
    game, and a `Generate2ShipOtr` target that runs ZAPD's `botr --norom` on `mm/assets/custom`
    into `<build>/mm/2ship.o2r`. Upstream's target of that name always runs (a custom target
    through `extract_assets.py`); this one is a custom command with outputs and depends on ZAPD
    and every custom asset, so an unchanged build is a no-op. Same ZAPD arguments as the script.
- `mm/CMakeLists.txt`:
  - Under `HARBOUR_ROOT` the game is a `SHARED` library passed to `harbour_add_game_framework`.
  - iOS compile definitions: the Clang set minus `ENABLE_OPENGL`, plus `__IOS__`.
  - iOS takes the Darwin branches (`MATCHES "Darwin|iOS"`) for `OBJCXX` and the compile/link
    options; the generic branch has `-Wl,-export-dynamic`, which Apple ld rejects.
  - iOS links `libultraship` and `ZAPDLib` only; SDL and the codecs come from
    `harbour_add_game_framework`.
  - Left out on iOS: the POST_BUILD copy of `assets/` next to the binary (`bundle_game_data` does
    it), the `curl` download of `gamecontrollerdb.txt`, `INSTALL` rules.
- `mm/src/code/main.c`: `SDL_main`/`main` is `int HarbourGame_Main(int, char**)` under `__IOS__`
  (C file, so C linkage) and returns 0; upstream's falls off the end.

## ZAPDTR patch (`patches/2ship/zapdtr.patch`)

The game extracts ROMs in-process through `ZAPDLib`. Its link setup takes the Darwin branches on
iOS: `-force_load` of `OTRExporter` (the Linux branch uses `--whole-archive`) and no
`-Wl,-export-dynamic`. OTRExporter needs no changes.

## libultraship patch

A copy of `patches/soh/libultraship.patch`: the five files it touches are identical in SoH's
libultraship `62e973ae` and this one.

## Port glue (`ports/2ship/`)

- `port.cmake`:
  - libpng 1.6.47 (static, SDK zlib, no hardware optimizations) with `OVERRIDE_FIND_PACKAGE`, a
    `PNG::PNG` alias and `PNG_PNG_INCLUDE_DIR`, for ZAPD's `find_package(PNG REQUIRED)`.
  - Copies Opus's headers to `harbour-include/opus/`: `mixer.c` includes `<opus/opus.h>`.
- `TwoShipPort.mm`:
  - `IdentifyRom`: requires the `.z64` magic `80 37 12 40`, then `Extractor::RunFileStandalone`
    (size, whole-file CRC32C against the supported dumps). The magic check keeps the extractor's
    "File is Compressed" SDL message box from ever showing on the background thread. The version
    is the header CRC at `0x10`: `0x5354631C` US 1.0, `0xB443EB08` US GC.
  - `ExtractRom`: `Extractor::CallZapd(GetAppBundlePath(), GetAppDirectoryPath(), ...)`, as
    `OTRGlobals::RunExtract` does. `CallZapd` always returns false, and changes the process's
    current directory to a temporary one (a symlink to the framework's `assets/` in it) while ZAPD
    runs. On an exception the glue restores the directory and removes the temporary one. Success
    is no exception plus `mm.o2r` in the data folder (the last step copies it there and throws if
    ZAPD didn't write it). Progress: ZAPD sets `total` to the number of XMLs and `done` to the
    index of the one it's on.
  - `IsArchiveOutdated`: `portVersion`'s major version differs from `gBuildVersionMajor` (the
    game deletes and re-extracts such an `mm.o2r`; no `portVersion` counts as 0), or `version`
    holds a ROM CRC other than the two above (the game shows an error and exits).
  - Menu: Escape (libultraship's `Gui` toggles 2Ship's menu on it).
- `port.sh`: the host build is `HARBOUR_TOOLS_ONLY=ON`, target `Generate2ShipOtr`.
  `bundle_game_data` takes `2ship.o2r` from `build/2ship/host/mm/` and puts into the framework
  root what the desktop POST_BUILD step puts next to the executable: `2ship.o2r`, `assets/` (`mm/assets/extractor`: configs, `EnumData.xml`,
  `filelists/`, `symbols/`) and `assets/xml/` (`mm/assets/xml`, 9 MB).

## Host build

ZAPD links libultraship, so the macOS host build configures libultraship the desktop way, with
Homebrew's `sdl2` (or `sdl2-compat`), `glew`, `libzip`, `nlohmann-json`, `tinyxml2` and `libpng`
(spdlog is fetched). It builds libultraship, ZAPD and OTRExporter once; afterwards
`Generate2ShipOtr` is a no-op until ZAPD or `mm/assets/custom` changes.

## Updating

- The version (`project(2s2h VERSION ...)`) changes: nothing to do; the new `--portVer` changes
  the command, so Ninja rebuilds `2ship.o2r`. The game exits if `2ship.o2r`'s version isn't
  exactly its own.
- New supported ROMs (`goodCrcs`/`verMap` in `Extract.cpp`, `validHashes` in `BenPort.cpp`):
  update `kRom*` in `TwoShipPort.mm` and the catalog's `roms`.
- `CallZapd`'s signature or output name changes: revisit `ExtractRom`.
- The upstream `Generate2ShipOtr` command changes (new ZAPD arguments): mirror it in the
  tools-only block.

## Known issues

- Extraction runs ZAPD in-process on one thread and keeps every exported file in memory until it
  writes `mm.o2r`. Untested on a device; watch time and memory on small-RAM iPhones. `CallZapd` changes the process-wide current directory for its duration.
- libultraship downloads `stb_image.h` and rewrites `stb_impl.c` at every CMake configure, so a
  reconfigure (editing any CMake file, `port.cmake` included) needs the network and recompiles
  what includes them. Builds without a reconfigure are no-ops.
- `configure_file` writes `mm/src/boot/build.c` and `mm/windows/properties.h` into the source tree
  (gitignored); the simulator and device builds write identical contents.
- `exit()` paths in `OTRGlobals::RunExtract` (missing `assets/`, `mm.o2r` that can't be removed)
  and `OTRGlobals::Initialize` (invalid ROM hash) only trigger if the framework is incomplete or
  the launcher starts the game with an archive `IsArchiveOutdated` would have flagged.
- A few ZAPD audio paths call `exit(1)` on malformed AIFF input; the ROM's audio doesn't reach them.
