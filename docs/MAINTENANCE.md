# Maintaining iHarbour

- [Updating a game](#updating-a-game)
- [Refreshing a patch](#refreshing-a-patch)
- [Updating SDL](#updating-sdl)
- [Changing the engine interface](#changing-the-engine-interface)
- [Changing the Xcode project](#changing-the-xcode-project)
- [Adding a game](#adding-a-game)

## Updating a game

Every game is a submodule of its upstream repository, pinned to the commit its patches were made
against. To move a game to a newer upstream commit:

```bash
scripts/unapply-patches.sh starship          # take iHarbour's patches out
git -C games/Starship fetch
git -C games/Starship checkout <commit>
git -C games/Starship submodule update --init --recursive   # its own libultraship, Torch, ...
scripts/build-engine.sh starship             # applies the patches, or says which one doesn't apply
```

If a patch doesn't apply, refresh it (below). Then build and test the game, and commit the new
submodule commit together with the refreshed patches.

The game's build directory reconfigures on its own. Its dependency checkouts have no git history,
so if they can't follow the update, the build deletes them and retries once (see
[BUILDING.md](BUILDING.md#troubleshooting)); delete `build/<game>/` if it still fails.

## Refreshing a patch

Apply what still applies, fix the rest by hand, then write the patch again from the submodule's
working tree:

```bash
git -C games/Starship apply --3way ../../patches/starship/starship.patch
# resolve conflicts, rebuild, test
git -C games/Starship diff --ignore-submodules=all > patches/starship/starship.patch
```

`--ignore-submodules=all` keeps out the `Subproject commit …-dirty` line a patched nested submodule
adds, which wouldn't apply. The same goes for nested submodules (`games/Starship/libultraship` →
`patches/starship/libultraship.patch`). `ports/<game>/port.sh` lists which patch goes where.

Keep patches minimal and guarded (`HARBOUR_ROOT` in CMake, `__IOS__`/`HARBOUR_IOS` in code), so
they're easy to rebase and never change the game's desktop builds. [PORTING.md](PORTING.md) lists
what each patch has to do.

## Updating SDL

All games share one SDL: `cmake/HarbourIOS.cmake` declares it (release 2.32.10) and applies
`patches/sdl2/sdl2-uikit-scene-support.patch` through `cmake/git-patch.cmake`, which re-applies it
when the patch changes. Bump `GIT_TAG` there, delete `build/*/*/_deps/sdl2-*`, and rebuild. If the
patch doesn't apply to the new tag, fix it in a fresh clone of SDL at that tag and export it with
`git diff`.

The patch makes SDL2 work in a UIScene app, which apps built with the iOS 27 SDK must be: it
attaches SDL's windows to the app's window scene, reads the interface orientation from the scene
instead of the status bar, and returns the Metal drawable size in pixels.

## Changing the engine interface

`engine/HarbourEngine.h` is shared by every framework and the app. Change it, implement the change
in `engine/HarbourEngine.mm` (and `engine/HarbourPort.h` plus every `ports/*/` if games must
provide something new), bump `HARBOUR_ENGINE_API_VERSION`, and update
`app/Launcher/Engine/GameEngine.swift`. The app refuses frameworks built against another version,
so a stale build can't crash it.

## Changing the Xcode project

Edit `app/iHarbour.xcodeproj` in Xcode and commit it. Swift, Objective-C++ and asset files in
`app/Launcher/` are picked up by the project on their own (a synchronized folder), so adding one
doesn't touch the project file.

Signing settings stay out of the project. `app/Config/Project.xcconfig` sets the defaults, and each
developer's team, bundle identifier and any manual signing go in the gitignored
`app/Config/Local.xcconfig`. A signing setting in the project would override both, so don't pick a
team in Xcode's Signing & Capabilities tab. If one gets in anyway,
`grep -nE "DEVELOPMENT_TEAM|CODE_SIGN|PROVISIONING" app/iHarbour.xcodeproj/project.pbxproj` finds
it.

## Adding a game

See [PORTING.md](PORTING.md). In short: add the submodule under `games/`, write
`patches/<id>/`, `ports/<id>/`, `docs/games/<id>.md`, add the game to
`app/Launcher/Catalog/Game+Catalog.swift` and its artwork to the asset catalog, and add the id to
the list in `app/Config/Project.xcconfig`'s comment.
