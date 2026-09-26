# Building iHarbour

- [Requirements](#requirements)
- [First build](#first-build)
- [Choosing the games](#choosing-the-games)
- [From the command line](#from-the-command-line)
- [Where builds go](#where-builds-go)
- [Disk space](#disk-space)
- [Linting and git hooks](#linting-and-git-hooks)
- [Testing without a ROM, and scripted runs](#testing-without-a-rom-and-scripted-runs)
- [Troubleshooting](#troubleshooting)

## Requirements

- A Mac with Apple silicon and Xcode 27 (the iOS 27 SDK).
- Homebrew tools: `brew install cmake ninja python git`. The build checks for `cmake`, `ninja`,
  `git` and `python3`. Everything the games need on iOS (SDL2, codecs, libzip, spdlog, ...) is
  fetched and built from source by the games' CMake builds.
- For 2 Ship 2 Harkinian, whose own archive (`2ship.o2r`) is packed by a macOS build of its ZAPD
  tool: `brew install sdl2 glew libzip nlohmann-json tinyxml2 libpng`. Ship of Harkinian also packs
  its archive with a macOS build of its own tools, which needs nothing beyond the base tools; the
  other games zip theirs without a host build.
- Network access for the first build (FetchContent clones).
- For linting, `brew install mint`, then `mint bootstrap` in the repository to install the pinned
  SwiftLint. See [Linting and git hooks](#linting-and-git-hooks).
- The submodules: `git submodule update --init --recursive`.
- An iPhone or iPad on iOS 17 or later, or the iOS Simulator (arm64). The deployment target is
  iOS 17.0.

No ROM or game asset is part of the build. Players supply their own ROMs in the app.

## First build

1. For a device, copy `app/Config/Local.xcconfig.example` to `app/Config/Local.xcconfig` and set
   your team ID and a bundle identifier of your own. The simulator needs neither. Don't pick a
   team in Xcode's Signing & Capabilities tab: that writes it into the checked-in project, where
   it overrides `Local.xcconfig`.
2. Open `app/iHarbour.xcodeproj`.
3. Pick the **iHarbour** scheme and a device or simulator, then Run.

The first build compiles every game and its dependencies for the chosen platform: roughly 10–20
minutes per game on an M-series Mac, so over an hour for all seven. Xcode shows it as the
**HarbourEngines** target's "Build the games with CMake" step; its log is in the Report navigator.
Later builds only recompile what changed and take seconds per game.

## Choosing the games

`HARBOUR_GAMES` in `app/Config/Local.xcconfig` limits the build to some games, which saves build
time and disk space:

```
HARBOUR_GAMES = soh starship
```

The ids are the folder names in `ports/`: `soh`, `2ship`, `ghostship`, `spaghettikart`,
`starship`, `lighthouse`, `paperboat`. Empty (the default) means all of them. Games left out still
appear in the launcher, marked "Not in this build".

## From the command line

```bash
xcodebuild -project app/iHarbour.xcodeproj -scheme iHarbour \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build
```

`HARBOUR_GAMES=soh` on that command line overrides the setting for one build.

One game's framework, without Xcode:

```bash
scripts/build-engine.sh starship                              # simulator (default)
PLATFORM_NAME=iphoneos scripts/build-engine.sh starship       # device
HARBOUR_JOBS=4 scripts/build-engine.sh starship               # fewer parallel compile jobs
```

`build-engine.sh` reads these environment variables (Xcode sets the first three):

| Variable | Default | Effect |
| --- | --- | --- |
| `PLATFORM_NAME` | `iphonesimulator` | `iphoneos` or `iphonesimulator`. |
| `IPHONEOS_DEPLOYMENT_TARGET` | `17.0` | Minimum iOS version. |
| `BUILT_PRODUCTS_DIR` | `build/products/<platform>` | Where `HarbourEngines/` goes. |
| `HARBOUR_ENGINE_BUILD_TYPE` | `Release` | CMake build type of the games (for example `RelWithDebInfo` for full debug info). Each type gets its own build directory. |
| `HARBOUR_JOBS` | Ninja's choice | Parallel compile jobs. Keep it low when building several games at once. |
| `HARBOUR_KEEP_DEPENDENCY_HISTORY` | unset | `1` keeps the git history of the dependency checkouts. |
| `DEVELOPER_DIR` | `xcode-select -p` | The Xcode whose clang and SDKs the games use. |

## Where builds go

| Path | Contents |
| --- | --- |
| `build/<game>/host/` | A macOS build of the game's tools, for games whose own archive is packed by a tool (Ship of Harkinian, 2 Ship 2 Harkinian). |
| `build/<game>/<platform>-<build type>/` | The game for iOS, per platform (`iphoneos`, `iphonesimulator`); the build type is `Release` unless `HARBOUR_ENGINE_BUILD_TYPE` says otherwise. The framework is assembled in its `harbour-dist/`. |
| `build/products/<platform>/HarbourEngines/` | Frameworks built by hand with `build-engine.sh`. |
| DerivedData | The app, plus the frameworks the Xcode build staged (hard links into `build/`). |

`build/` sits outside DerivedData on purpose: **Product › Clean Build Folder** doesn't throw away
the games' builds. Delete `build/<game>/` by hand to rebuild a game from scratch.

Xcode's Debug and Release configurations share one optimized build of each game (CMake `Release`,
with line tables so crash reports symbolicate).

The build applies the patches in `patches/` to the game submodules' working trees and leaves them
there. `.gitmodules` sets `ignore = dirty`, so the parent's `git status` doesn't list the
submodules as modified; run `git -C games/<Game> status` to see the applied patches.
`scripts/unapply-patches.sh [<game>...]` takes them out again.

## Disk space

A game's build directory takes 0.3–0.8 GB per platform after the build (the dependencies' git
history is deleted once a build succeeds). All seven games take about 3 GB per platform, twice that
for simulator and device. Limit `HARBOUR_GAMES` if space is short, and delete
`build/<game>/<platform>-*` for platforms you no longer build for.

## Linting and git hooks

The launcher's Swift code is checked with swift-format (from Xcode) and SwiftLint (pinned in the
`Mintfile`), configured by `.swift-format` and `.swiftlint.yml`:

| Command | Effect |
| --- | --- |
| Building the app | The app target's first phase (`scripts/lint-swift.sh`) lints `app/` and shows the findings as warnings, except those SwiftLint rates as errors (such as `force_cast`, or a file over 800 lines), which fail the build. Without SwiftLint installed, it warns and goes on. |
| `make lint` | Lints `app/` with both tools in strict mode: every finding is an error. |
| `make format` | Fixes what SwiftLint can fix, then formats `app/` with swift-format. |
| `make` or `make hooks` | Points git at `.githooks/`. The pre-commit hook lints the staged Swift files in `app/`, the pre-push hook runs `make lint`. |

## Testing without a ROM, and scripted runs

Debug builds of the app take these launch arguments (in Xcode: **Product › Scheme › Edit Scheme ›
Run › Arguments**; or `xcrun simctl launch booted <bundle id> ...`):

| Argument | Effect |
| --- | --- |
| `-HarbourAutoImport YES` | Imports every ROM directly in the app's Documents or directly in a game's folder at launch. |
| `-HarbourAutoPlay <game id>` | Starts that game as soon as the launcher appears. |
| `-HarbourAllowPlayWithoutArchives YES` | Lets games start without their archives. Most then show their own "missing archive" prompt, which is enough to check that a game loads, renders and takes touches. Declining the prompt ends the app, as it ends the game on the desktop. |

For example, with a ROM copied into the simulator app's Documents:

```bash
xcrun simctl launch booted <bundle id> -HarbourAutoImport YES -HarbourAutoPlay soh
```

## Troubleshooting

**"patches/…​ neither applies to … nor is applied already."** The submodule moved on (or has local
changes). See [MAINTENANCE.md](MAINTENANCE.md#updating-a-game).

**A game's build fails after a submodule update with a FetchContent or patch error.** The
dependency checkouts in `build/<game>/` have no git history (see above), so they can't be updated
or re-patched in place. The build notices, deletes those checkouts and tries once more. If that
fails too, delete `build/<game>/<platform>-Release` and build again.

**"The first build takes forever."** It builds seven games. Build one game first with
`HARBOUR_GAMES` to check your setup.

**The app says a game "isn't part of this build".** Its framework isn't in the app: it's not in
`HARBOUR_GAMES`. (A game whose build fails stops the whole build, and the HarbourEngines target's
log says why.)
