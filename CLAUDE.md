# CLAUDE.md

iHarbour: one iOS app hosting several libultraship (LUS) game ports. Each game builds from its
upstream submodule (`games/`) into its own framework that exports only `HarbourEngine_GetAPI`; the
SwiftUI launcher (`app/`) `dlopen`s a game's framework on demand. Read `docs/ARCHITECTURE.md` first,
`docs/PORTING.md` before touching a game.

## Build

```bash
git submodule update --init --recursive
scripts/build-engine.sh <game>                     # one game's framework, simulator
PLATFORM_NAME=iphoneos scripts/build-engine.sh <game>
xcodebuild -project app/iHarbour.xcodeproj -scheme iHarbour \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' HARBOUR_GAMES=soh build
```

- Game ids = folders in `ports/`: soh, 2ship, ghostship, spaghettikart, starship, lighthouse, paperboat.
- Builds go to `build/<game>/<platform>-Release` (outside DerivedData). A game's first build takes
  10–20 minutes; keep `HARBOUR_JOBS` low when building several games at once.
- Edit the project in Xcode. Files in `app/Launcher/` are added to it automatically (synchronized
  folder).
- No test suite. Verify by building and running in the simulator; `docs/BUILDING.md` lists the
  debug launch arguments (`-HarbourAutoImport YES`, `-HarbourAutoPlay <id>`,
  `-HarbourAllowPlayWithoutArchives YES`).

## Rules

- Never commit to the submodules in `games/`. Changes to them are patches in `patches/<game>/`,
  generated with `git -C <submodule> diff --ignore-submodules=all > <patch>`, applied by
  `build-engine.sh`, and left applied in the working tree (`scripts/unapply-patches.sh` removes
  them).
- Every patch hunk is guarded (`HARBOUR_ROOT` in CMake, `__IOS__`/`HARBOUR_IOS` in code) so the
  game's desktop builds are unchanged.
- Game-specific code goes in `ports/<game>/`; `engine/` and `cmake/HarbourIOS.cmake` are shared by
  all games. Changing `engine/HarbourEngine.h` means bumping `HARBOUR_ENGINE_API_VERSION`.
- The launcher's knowledge of a game (ROM checksums, archive names, CVar names, folder) lives in
  `app/Launcher/Catalog/Game+Catalog.swift`; the id must match `ports/<id>`.
- Signing settings live only in `app/Config/Project.xcconfig` (defaults) and the gitignored
  `app/Config/Local.xcconfig`, never in the project. Xcode's Signing & Capabilities tab writes
  them into the project, where they override the xcconfigs.
- Swift: Swift 6, default MainActor isolation; model types that cross threads are `nonisolated`.
- Keep `docs/` current and in the present tense (no history): `docs/games/<game>.md` for a
  game's port, `ARCHITECTURE.md`, `BUILDING.md`, `PORTING.md`, `MAINTENANCE.md` for the shared parts.
