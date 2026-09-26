# Lighthouse

| | |
| --- | --- |
| Id | `lighthouse` |
| Submodule | `games/Lighthouse` (libultraship `62e973ae`, Torch `2ab12fe`) |
| Framework | `Lighthouse.framework` (CMake target `Lighthouse`) |
| Data folder | `Documents/Lighthouse/`, config `lighthouse.cfg.json` |
| ROMs | US 1.0, US 1.1, PAL, JP (`.z64` SHA-1s in `GameExtractor.cpp` and the catalog) |
| Archives | `bk.o2r` (extracted from a ROM), `mods/~lang/bk<region>.o2r` (language packs, listed on the game's page), `lighthouse.o2r` (the port's own, in the framework) |
| Menu key | Escape |

## Game patch (`patches/lighthouse/lighthouse.patch`)

- `CMakeLists.txt`:
  - includes `cmake/HarbourIOS.cmake` after `project()` and the CVar includes, before
    libultraship;
  - the `if(IOS)` block keeps `PLATFORM_IOS=1` but skips the leetal toolchain under
    `HARBOUR_ROOT`;
  - the game is a `SHARED` library passed to `harbour_add_game_framework`, instead of the app
    bundle built from the nonexistent `libultraship/ios` files;
  - the target gets `__IOS__` and `LIGHTHOUSE_NATIVE_FILE_DIALOG=0`, so file pickers (romhacks,
    language packs) use libultraship's ImGui browser instead of portable-file-dialogs;
  - `ADDITIONAL_LIBRARY_DEPENDENCIES` is empty on iOS: the desktop list names
    `SDL2_net::SDL2_net`, which the static SDL_net build doesn't have, and
    `harbour_add_game_framework` links SDL, SDL_net and the codecs;
  - the host block (TorchExternal, ExtractAssets, GeneratePortO2R, install rules, macOS icons,
    the `gamecontrollerdb.txt` download) is left out under `HARBOUR_ROOT`.
- `src/port/Game.cpp`: `SDL_main`/`main` becomes `extern "C" int HarbourGame_Main` under
  `HARBOUR_IOS`. It already returns and already `chdir`s to `SHIP_HOME`.
- `src/port/Engine.cpp`: `RelaunchIfRequested` doesn't `execv` under `HARBOUR_IOS`. The mod
  menu's "Apply & Restart" and "Restart now?" close the game; the change applies the next time
  iHarbour starts (a game runs once per process).

Networking (`USE_NETWORKING`, Anchor co-op) stays on; SDL_net comes from `HarbourIOS.cmake`.

Regenerate the patch with `git -C games/Lighthouse diff --ignore-submodules`, since the
libultraship patch leaves that submodule modified.

## libultraship patch

The same as Ship of Harkinian's (`patches/soh/libultraship.patch`): both pin `62e973ae`.

## Port glue (`ports/lighthouse/`)

- `IdentifyRom`: `GameExtractor::RunStandalone`, which only accepts the four retail SHA-1s, so
  romhacks are rejected (the game extracts them as mods from its own menu). The description is
  "language pack" when the ROM becomes one (below), empty otherwise.
- `ExtractRom`: `GameExtractor::GenerateOTR(count, total, "bk")`, what the desktop flow runs
  minus its prompts. Specs: `config.yml` and `assets/` in the framework (the extractor takes the
  parent of `assets/`). Output in the data folder, with `torch.hash.yml`. Success means a
  newly written archive.
  - Every retail ROM makes `bk.o2r`. If a current `bk.o2r` of another region is already there
    (by the ROM CRC Torch stamps into its `version` file), the ROM becomes a language pack
    instead, `mods/~lang/bk<region>.o2r`, like the menu's "Add Language Pack from ROM". A ROM of
    the same region replaces `bk.o2r`. To switch the base region, delete `bk.o2r` first.
  - Progress: Torch resets its counter per asset file (parse, then export). The glue polls the
    counters and publishes a monotonic count out of twice the total GameExtractor counts up
    front. Language packs report none: they only extract the dialog out of that total.
- `IsArchiveOutdated`: `portVersion` holds major, minor, patch as big-endian `u16`s (no
  endianness byte). The game deletes `bk.o2r` when major or minor differ from its own; a missing
  version counts as 0.0.0. Language packs and `lighthouse.o2r` aren't version-checked.
- `bundle_game_data` puts into the framework: `lighthouse.o2r`, `config.yml`, `assets/`.

`lighthouse.o2r` is what `torch pack` makes of `port/` plus `libultraship/src/fast/shaders/` as
`shaders/`: a plain zip, no version file. So there is no host build: `bundle_game_data` stages
both and zips them with `cmake -E tar` into `harbour-dist/`, only when something in them changed.
The game only checks that the file exists (and quits without it and without `assets/`).

Paths computed in static initializers (`SaveManager.cpp`, `Rando.cpp`, `RefreshOptions.cpp`) run
at `dlopen`; the launcher sets `SHIP_HOME` before it loads the framework.

## Updating

- If `GeneratePortO2R` stops being a plain `torch pack` of those two folders, or gains
  `-u <version>` that the game then checks, revisit `bundle_game_data`.
- If `ReadPortVersionFromOTR`/`VerifyArchiveVersion` in `ExtractFlow.cpp` change, change
  `IsArchiveOutdated`.
- New supported ROMs: `mGameList` in `GameExtractor.cpp`, `config.yml`, and the catalog.

## Known issues

- Romhacks can't be imported from the launcher, only from the in-game menu (Settings → Romhack
  Menu), which browses the data folder with the ImGui file browser.
- A romhack with custom code would make the extractor wait for an ImGui prompt; the launcher
  never gets one there because only retail ROMs pass `IdentifyRom`.
- `CMakeLists.txt` still downloads `sse2neon.h` at configure time (unused).
