# SpaghettiKart

| | |
| --- | --- |
| Id | `spaghettikart` |
| Submodule | `games/SpaghettiKart` (libultraship `60c9bb71`, Torch `2d474ddb`) |
| Framework | `SpaghettiKart.framework` (CMake target `Spaghettify`) |
| Data folder | `Documents/SpaghettiKart/`, config `spaghettify.cfg.json` |
| ROM | US only, `.z64` SHA-1 `579c48e211ae952530ffc8738709f078d5dd215e` |
| Archives | `mk64.o2r` (extracted from the ROM), `spaghetti.o2r` (the port's own, in the framework) |
| Menu key | Escape |

## Game patch (`patches/spaghettikart/spaghettikart.patch`)

- `CMakeLists.txt`: includes `cmake/HarbourIOS.cmake` before the iOS block. Under
  `HARBOUR_ROOT` the iOS block skips the leetal toolchain and the Xcode properties, but keeps
  `SPAGHETTIKART_IOS` (and so `PLATFORM_IOS=1`). The bundle resources from the nonexistent
  `libultraship/ios` are skipped. The game is a `SHARED` library passed to
  `harbour_add_game_framework`, with `__IOS__` and `MA_NO_DEVICE_IO`. The POST_BUILD copy of
  `config.yml`/`yamls`/`meta` and the whole host Torch block (TorchExternal, ExtractAssets,
  GenerateO2R) are left out under `HARBOUR_ROOT`.
- `cmake/SetFlags.cmake`: `-fno-lto` under `HARBOUR_ROOT` (the desktop build uses `-flto=auto`).
- `src/port/Game.cpp`: `main` becomes `extern "C" int HarbourGame_Main` under `HARBOUR_IOS` and
  returns 0 instead of `_Exit(0)`. The macOS press-and-hold preference is not written on iOS.
- `src/port/SpaghettiGui.cpp`: fixes the include path of `ship/port/mobile/MobileImpl.h`, which
  only `__IOS__` builds compile.

`MA_NO_DEVICE_IO`: the game's miniaudio engine (HMAS) runs without a device, and miniaudio's
Core Audio backend is Objective-C on iOS. The define changes `ma_engine`'s layout, so it's set for
the whole target, not just `HMAS.cpp`.

## libultraship patch

The same hunks as Ship of Harkinian's (`patches/soh/libultraship.patch`), made against
`60c9bb71`, an ancestor of SoH's `62e973ae` with no build changes in between. Only the
`AudioPlayer.h` index line differs.

## Port glue (`ports/spaghettikart/`)

- `IdentifyRom`: SHA-1 of the file (`Companion::CalculateHash`) against the US hash.
- `ExtractRom`: what `GameExtractor::GenerateOTR` does, minus the ROM prompts: Torch as a library,
  specs from the framework, `meta/mods.toml` added to the archive, output `mk64.o2r` and
  `torch.hash.yml` in the data folder. Torch returns silently on several errors, so success means
  a new `mk64.o2r`. The `Companion` is freed afterwards. No progress (Torch has no hook).
- `IsArchiveOutdated`: reads `mods.toml` from the archive and checks it's `mk64-assets` in the
  range the game requires (`1.0.0-alpha1`, `AddCoreDependencies` in `ModManager.cpp`). The game
  quits at startup otherwise. An archive that doesn't open or has no `mods.toml` is outdated.
- `bundle_game_data` puts into the framework: `spaghetti.o2r`, `config.yml` (with
  `logging: ERROR`, so Torch doesn't log every asset), `yamls/`, `meta/`.

`spaghetti.o2r` is a plain zip of `assets/` (the desktop build runs `torch pack assets
spaghetti.o2r o2r`, which does the same), so there is no host build: `bundle_game_data` zips it
with `cmake -E tar` into `harbour-dist/`, again only when something in `assets/` changed.

## Updating

- When `ModManager.cpp` changes the required `mk64-assets` version, change
  `kArchiveVersionRange` in `SpaghettiKartPort.mm`.
- If `GenerateO2R.cmake` stops being a plain `torch pack`, revisit `bundle_game_data`.
- `lib/wasm-micro-runtime` is a stale `.gitmodules` entry; it isn't used.

## Known issues

- Only the US ROM is supported upstream.
- The desktop build's `FMT_CONSTEVAL=` workaround also applies on iOS (`APPLE`); harmless.
