# iHarbour

One iOS app for the Harbour Masters' PC ports. iHarbour builds each game from its upstream
repository for iOS, runs it inside the app, and gives them one launcher: add a ROM you own,
iHarbour recognizes which game it belongs to and extracts that game's assets, and you play with a
controller or the on-screen one.

| Game | Upstream |
| --- | --- |
| Ship of Harkinian | [HarbourMasters/Shipwright](https://github.com/HarbourMasters/Shipwright) |
| 2 Ship 2 Harkinian | [2ship2harkinian/2ship2harkinian](https://github.com/2ship2harkinian/2ship2harkinian) |
| Ghostship | [HarbourMasters/Ghostship](https://github.com/HarbourMasters/Ghostship) |
| SpaghettiKart | [HarbourMasters/SpaghettiKart](https://github.com/HarbourMasters/SpaghettiKart) |
| Starship | [HarbourMasters/Starship](https://github.com/HarbourMasters/Starship) |
| Lighthouse | [IsleOPorts/Lighthouse](https://github.com/IsleOPorts/Lighthouse) |
| PaperBoat | [HarbourMasters/PaperBoat](https://github.com/HarbourMasters/PaperBoat) |

iHarbour contains no game and no copyrighted asset. Every game needs a ROM dump you supply, and the
games' code comes from their upstream repositories, unmodified in git and patched at build time.

## Status

- All seven games build for the iOS Simulator and for devices (arm64, iOS 17+), and each starts
  inside iHarbour on the iOS 27 simulator (without its archives, up to its own "missing archive"
  prompt).
- Ship of Harkinian is tested end to end on the simulator: the launcher recognizes a ROM,
  extracts it, and the game runs. Extracting for one game and then playing another (two
  frameworks in one process) works.
- The other six games' ROM extraction and gameplay are untested. Their extraction runs each game's
  own extractor, the same code their desktop versions use.
- On a device, the app with all seven games builds, signs and installs; playing there is untested.
- A game runs once per launch of the app. Each game's page in [docs/games/](docs/games/) lists its
  known issues.

## Quick start

```bash
git clone --recursive <this repository>
brew install cmake ninja python git
brew install sdl2 glew libzip nlohmann-json tinyxml2 libpng   # only for 2 Ship 2 Harkinian's asset tool
open app/iHarbour.xcodeproj        # scheme iHarbour, pick a simulator or device, Run
```

For a device, copy `app/Config/Local.xcconfig.example` to `app/Config/Local.xcconfig` first and put
in your team ID and a bundle identifier (not in Xcode's Signing & Capabilities tab, which writes
them into the checked-in project). The first build compiles all seven games and takes a
while; `HARBOUR_GAMES` in the same file limits it to some. Details: [docs/BUILDING.md](docs/BUILDING.md).

In the app: tap **+**, pick a ROM (`.z64`, `.n64` or `.v64`), wait for the extraction, open the
game, **Play**. **MENU** while playing opens the game's own menu (enhancements, randomizers,
controls, ...). Each game keeps its files in its own folder under *On My iPhone › iHarbour* in the
Files app. A game runs once per launch of the app: after quitting one, reopen iHarbour to play
again.

## How it's built

Each game builds, with its own CMake project, into a framework that exports a single C function
table. The SwiftUI launcher loads a game's framework only when it's needed and runs the game
inside the app's process. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) has the whole design.

```
app/        Xcode project and SwiftUI launcher
engine/     code every game's framework shares: the C interface, SDL inside the app, the gamepad
ports/      per game: build recipe and glue
patches/    per game: changes to the upstream repositories; SDL's UIScene patch
cmake/      iOS dependencies and the framework helper for the games' CMake builds
scripts/    the build and the Xcode build phases
games/      upstream repositories (submodules)
docs/       documentation
```

## Documentation

- [docs/BUILDING.md](docs/BUILDING.md): requirements, building, choosing games, linting, testing.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): how the app, the frameworks and the build fit together, and why.
- [docs/PORTING.md](docs/PORTING.md): how a game becomes an iHarbour game; the rules every port follows.
- [docs/MAINTENANCE.md](docs/MAINTENANCE.md): updating games and patches.
- [docs/games/](docs/games/): what each game's port changes.

## Credits

The games are the work of the Harbour Masters, the Isle O' Ports team, and everyone who
contributed to them and to the decompilation projects they're built on. iHarbour builds on
libultraship, Torch, SDL and the other libraries the games use. Each game keeps its own license; see its repository.
