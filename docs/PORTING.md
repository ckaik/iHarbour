# Porting a game to iHarbour

How a libultraship game becomes one of iHarbour's games, and the rules every port follows.
Ship of Harkinian (`ports/soh`, `patches/soh`) is the reference port; read it next to this page.

- [What a port consists of](#what-a-port-consists-of)
- [The game patch](#the-game-patch)
- [The libultraship patch](#the-libultraship-patch)
- [The port glue](#the-port-glue)
- [The recipe: port.sh](#the-recipe-portsh)
- [Building and checking a port](#building-and-checking-a-port)
- [Adding the game to the launcher](#adding-the-game-to-the-launcher)
- [Pitfalls](#pitfalls)

## What a port consists of

A game `<id>` (a short lowercase name: `soh`, `2ship`, `starship`, ...) has:

| Path | What |
| --- | --- |
| `games/<Repo>/` | The upstream repository, a submodule. Never committed to; patched at build time. |
| `patches/<id>/<repo>.patch` | Changes to the game's own repository. |
| `patches/<id>/libultraship.patch` | Changes to the game's copy of libultraship (every game pins its own). |
| `patches/<id>/*.patch` | Changes to other submodules if needed (Torch, ZAPD, ...). |
| `ports/<id>/port.sh` | The recipe `scripts/build-engine.sh` reads. |
| `ports/<id>/*.mm`, `*.cpp`, `*.c`, `*.h` | The port glue: the game's side of `engine/HarbourPort.h`. Every source file here is compiled into the framework. |
| `ports/<id>/port.cmake` | Optional. CMake that only this game needs (an extra library, target aliases). `cmake/HarbourIOS.cmake` includes it. |
| `docs/games/<id>.md` | What the port changed and why. |
| `app/Launcher/Catalog/Game+Catalog.swift` | The game's entry in the launcher: names, archives, ROM checksums, settings. |
| `app/Launcher/Assets.xcassets/Game-<id>.imageset` | The game's artwork in the launcher. |

Patches are made against the pinned submodule commits and generated with `git diff` in the
submodule (`git -C games/<Repo> diff --ignore-submodules=all > patches/<id>/<repo>.patch`; without
`--ignore-submodules`, a patched nested submodule such as libultraship adds a "-dirty" line that
doesn't apply). `build-engine.sh` applies each
one unless it's applied already, and leaves it applied in the working tree. A patch for a nested
submodule that isn't checked out is an error.

## The game patch

Everything in it is guarded, so the game's desktop builds are unchanged. `HARBOUR_ROOT` is set only
when `scripts/build-engine.sh` configures the iOS build.

1. **Include iHarbour's CMake** before libultraship is added:

   ```cmake
   if(HARBOUR_ROOT)
       include(${HARBOUR_ROOT}/cmake/HarbourIOS.cmake)
   endif()
   ```

   It enables Objective-C, fetches SDL2 (with the UIScene patch), SDL2_net, Ogg, Vorbis (with
   `Vorbis::` aliases), Opus and opusfile (with an `OpusFile::opusfile` alias), all static, includes
   `ports/<id>/port.cmake`, and defines `harbour_add_game_framework()`.

2. **Skip the game's own iOS setup.** Several games have an `if(IOS)` block written for the Xcode
   generator that includes leetal/ios-cmake's toolchain after `project()`. That toolchain overwrites
   the sysroot, architectures, deployment target and compiler flags (and hides all symbols), which
   breaks CMake's native iOS support that iHarbour uses. Guard such blocks with
   `if(IOS AND NOT HARBOUR_ROOT)`, but keep the defines the game code relies on (`PLATFORM_IOS`,
   `__IOS__`).

3. **Build a framework, not an app:**

   ```cmake
   if(HARBOUR_ROOT)
       add_library(${PROJECT_NAME} SHARED ${ALL_FILES})
       harbour_add_game_framework(${PROJECT_NAME})
   else()
       add_executable(...)   # unchanged
   endif()
   ```

   `harbour_add_game_framework` adds `engine/` and `ports/<id>/` to the target, links SDL and the
   codecs, exports only `HarbourEngine_GetAPI`, and sets the framework properties. It also defines
   `HARBOUR_IOS=1` for the target, for game code that must behave differently inside iHarbour
   (plus `HARBOUR_GAME_ID` and `HARBOUR_FRAMEWORK_NAME`).

4. **Compile definitions for iOS:** `__IOS__` for the game target (libultraship only defines it for
   itself, and its public headers have `__IOS__` members), no `ENABLE_OPENGL` (iOS renders through
   Metal; `gfx_opengl.h` would pull in GLEW). Apple ld doesn't know GNU options, so iOS must not
   fall into Linux branches with `-Wl,-export-dynamic` or `-Wl,--whole-archive`; use
   `MATCHES "Darwin|iOS"` where the Darwin branch fits.

5. **Rename `main`** to `extern "C" int HarbourGame_Main(int argc, char* argv[])` on iOS. SDL's
   headers otherwise rename it to `SDL_main` behind the game's back. It must return, not call
   `exit`/`_Exit`: the launcher lives in the same process.

6. **Leave host-only steps out of the iOS build:** ExternalProject builds of standalone Torch,
   asset-extraction targets, `curl` downloads of `gamecontrollerdb.txt`, POST_BUILD copies into
   the bundle. Guard them with `if(NOT HARBOUR_ROOT)`. Data goes into the framework through
   `bundle_game_data` in `port.sh` instead.

7. **Game code:** only what can't be avoided. Typical: relaunch-by-`execv` paths return false on
   iOS, a game's own on-screen touch overlay defaults to off under `HARBOUR_IOS` (iHarbour draws its
   own), config file paths that libultraship prefixes twice.

## The libultraship patch

Every game's libultraship needs the same changes; `patches/soh/libultraship.patch` has them all.
Versions differ, so each game gets its own copy of the patch, adapted:

- `Context::GetAppBundlePath()` on iOS returns the directory of the binary that contains
  libultraship (`dladdr`), that is the game's framework. The game's read-only data (its own archive,
  extraction specs) lives there, so games don't collide in the app bundle.
- `Context::GetAppDirectoryPath()` on iOS returns `SHIP_HOME` when it's set. The launcher sets it to
  the game's folder in Documents (`Documents/<Game>/`) before it loads the framework, so saves,
  mods, logs and configs of different games stay apart.
- `SetFullscreenImpl` is a no-op on iOS. SDL's fullscreen resizes the window to the display mode,
  which is still portrait while the scene rotates to landscape: the game then draws a portrait frame
  into a landscape view.
- The window asks for `SDL_WINDOW_ALLOW_HIGHDPI`, so games render at the screen's native
  resolution.
- The macOS-only native fullscreen calls (`isNativeMacOSFullscreenActive`,
  `toggleNativeMacOSFullscreen`) are compiled out on iOS (`__APPLE__ && !__IOS__`). Without that the
  link fails.
- The game pauses between `SDL_APP_WILLENTERBACKGROUND` and `SDL_APP_DIDENTERFOREGROUND`
  (`mInBackground` in the SDL window backend): iOS doesn't let apps present from the background,
  and without frames the frame pacing is gone.
- The CoreAudio HAL output unit doesn't exist on iOS: SDL audio instead, where the libultraship
  version still has the CoreAudio player.

Some games' libultraship versions have part of this already (PaperBoat's and Ghostship's forks do
HiDPI and pixel-space ImGui themselves). Port what's missing; don't duplicate what's there.

## The port glue

`ports/<id>/<Name>Port.mm` implements `engine/HarbourPort.h`:

| Function | Contract |
| --- | --- |
| `GameVersion()` | The game's version string, for display. |
| `IdentifyRom(path, &description)` | Whether the game can extract the ROM at `path`, by its own checks, and a description of anything the catalog can't tell from the checksum (usually empty; Lighthouse's "language pack"). The launcher shows the catalog's name for the dump plus that. `path` is always a big-endian `.z64` file (the launcher converts byte-swapped dumps and names the copy `.z64`). No UI, no SDL message boxes: it runs on a background thread. |
| `ExtractRom(path, done, total)` | Extracts in-process into `Ship::Context::GetAppDirectoryPath()` (the game's folder; `SHIP_HOME` is set). Reads its specs from `Ship::Context::GetAppBundlePath()` (the framework). Reports progress through `done`/`total` if possible; `total` left at 0 means indeterminate. Catches exceptions. Verifies that the archive it should have written exists, since Torch returns silently on several errors. |
| `IsArchiveOutdated(path)` | Whether the game would reject or delete the archive at `path` (its version check, if it has one). `false` if the game has none. |
| `MenuScancode()` | The key that toggles the game's menu (`SDL_SCANCODE_ESCAPE` for most; Starship uses F1). |
| `IsMenuOpen()` | Whether the game's menu or menu bar is visible. Only called while the game runs. |

Mirror the game's own extraction code (the desktop flow, or an Android bridge where one exists)
minus its prompts and file dialogs.

## The recipe: port.sh

`scripts/build-engine.sh` sources `ports/<id>/port.sh`; `ports/soh/port.sh` is the model. It sets:

| Name | What |
| --- | --- |
| `GAME_TITLE` | The game's name, for the build log. |
| `GAME_DIR` | The submodule, relative to the repository (`games/Shipwright`). |
| `FRAMEWORK_NAME` | The framework's name (`ShipOfHarkinian`); the launcher's catalog uses the same. |
| `CMAKE_TARGET` | The game's CMake target (`soh`). |
| `FRAMEWORK_OUTPUT` | Where the framework lands in the iOS build directory (`soh/ShipOfHarkinian.framework`). |
| `PATCHES` | Array of `"<directory in the submodule>:<patch in patches/<id>/>"`, applied in order (`".:shipwright.patch" "libultraship:libultraship.patch"`). |
| `HOST_CMAKE_ARGS`, `HOST_TARGETS` | Optional. Arguments and targets of a macOS build of the game repository that builds only the game's own archive (`-DSOH_TOOLS_ONLY=ON`, `GenerateSohOtr`). Empty: no host build. |
| `IOS_CMAKE_ARGS` | Optional. Extra arguments for the iOS configure. |
| `bundle_game_data <framework dir> <iOS build dir>` | A function that copies into the framework whatever `GetAppBundlePath()` must find: the game's own `.o2r`, `config.yml`, extraction specs. |

A recipe can use `HARBOUR_ROOT` (the repository), `GAME_PATH` (the submodule's absolute path),
`HARBOUR_CLEAN_ENV` (the clean environment the build runs tools in) and `harbour_note` (a log
line).

If the game's own archive is built by a host tool (ZAPD, the game's own asset tools),
`HOST_CMAKE_ARGS` configures a macOS build of the game repository that builds only that. When the
archive is a plain zip of a folder, `bundle_game_data` makes it with `cmake -E tar cf <out>
--format=zip` (or Python's `zipfile`) instead, or copies it from the iOS build directory when the
game's iOS build already makes it (PaperBoat).

## Building and checking a port

```bash
HARBOUR_JOBS=4 scripts/build-engine.sh <id>        # simulator; PLATFORM_NAME=iphoneos for devices
```

The framework ends up in `build/products/iphonesimulator/HarbourEngines/`. Check:

```bash
F=build/products/iphonesimulator/HarbourEngines/<Name>.framework
nm -gU $F/<Name>          # exactly one symbol: _HarbourEngine_GetAPI
nm -u $F/<Name> | grep -v '^_\(objc_\|_\)' | head   # nothing from the game should be undefined
ls $F                     # the data bundle_game_data copied
```

Then build the app with the game included and try it in the simulator (see `docs/BUILDING.md`).

## Adding the game to the launcher

`Game` (`app/Launcher/Catalog/Game.swift`) is what the launcher knows about a game without loading
its framework. Add an entry to `app/Launcher/Catalog/Game+Catalog.swift` and put it in `Game.all`:

- `id` (must match `ports/<id>`), `title`, `frameworkName`, `folderName` (its folder in
  Documents), `configFileName`;
- `imageName` (`Game-<id>` in the asset catalog) and `tint`;
- `archives`: the files it extracts, by path in its folder, and whether each is enough to play
  (`isMain`). Add-ons the game loads from a subfolder (voice or language packs in `mods/`) are
  archives with `isMain: false` and their path (`mods/sf64jp.o2r`);
- `roms`: supported dumps by SHA-1 of the `.z64` form, with a title for each;
- `gameCodes`: the two letters at offset 0x3C of the header, for recognizing unknown dumps;
- `settings`: the CVar names of the common settings (read them from the game's
  `lus-cvars.cmake` or its compile definitions; some games don't prefix them), or `nil` for one
  the game doesn't have, plus whether the volume is a float and the game's defaults;
- `originalFrameRate`, `menuDescription` (what the in-game menu offers), `website`.

## Pitfalls

- The `leetal/ios-cmake` toolchain, included by libultraship after `project()`, only works with
  the Xcode generator. `build-engine.sh` points `FETCHCONTENT_SOURCE_DIR_IOSTOOLCHAIN` at
  `cmake/ios-toolchain-stub`, which provides just `set_xcode_property`.
- Games that call `exit()` in prompts: the engine registers an `atexit` handler that `_exit`s
  before static destructors crash. Make sure the launcher never starts a game without its archives,
  so the prompts don't appear.
- A game can run once per process: none tears down its globals.
- Several games compute paths in static initializers, which run inside `dlopen`: `SHIP_HOME` is set
  before the framework loads.
- `configure_file` into the source tree and `add_subdirectory(libultraship <source dir>)` make the
  host, simulator and device builds share files. Put build output in the build directory.
- Torch keeps `torch.hash.yml` in its output folder and skips every spec whose hash it has seen:
  a leftover file makes a second extraction write a nearly empty archive. Delete it, or let Torch
  write into a fresh folder and move the archive into place (which also keeps the old archive if
  extraction fails).
- Torch sets spdlog's global level to debug and logs every asset. Ports add `logging: ERROR`
  to the `config.yml` they bundle.
- CMake policy CMP0126: with an old `cmake_minimum_required`, a game's `lus-cvars.cmake` (normal
  variables) and libultraship's `cvars.cmake` (cache variables) give different CVar names on the
  first configure and on later ones. Set the policy to NEW in the game patch.
- A game's own `.o2r` is often just a zip of a folder (`torch pack` = zip, plus `portVersion`
  when given `-u`). Such ports make it in `bundle_game_data` (`cmake -E tar --format=zip`, or
  Python's `zipfile`) instead of building a host Torch; PaperBoat's iOS build zips its own, and
  `bundle_game_data` copies it. Ship of Harkinian and 2 Ship 2 Harkinian
  pack theirs with a host build of their own tools (ZAPD converts 2 Ship 2 Harkinian's textures).
- ImGui on iOS must work in points with the screen's pixel density as framebuffer scale, with fonts
  baked at that density. A libultraship fork that runs ImGui in pixels draws its menus at a third of
  the size on 3× screens: PaperBoat's patch moves its ImGui to points, Ghostship's scales the menu
  and fonts by the pixel density.
- Games whose default gamepad mapping differs from libultraship's (Starship) get libultraship's
  defaults on iOS, so the on-screen controller's buttons do what their labels say.
