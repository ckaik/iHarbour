# 2 Ship 2 Harkinian. Read by scripts/build-engine.sh.

GAME_TITLE="2 Ship 2 Harkinian"
GAME_DIR=games/2ship2harkinian
FRAMEWORK_NAME=TwoShip2Harkinian
CMAKE_TARGET=2ship
FRAMEWORK_OUTPUT=mm/TwoShip2Harkinian.framework

PATCHES=(
    ".:2ship2harkinian.patch"
    "libultraship:libultraship.patch"
    "ZAPDTR:zapdtr.patch"
)

# 2ship.o2r, the game's own assets (mm/assets/custom), is packed by ZAPD, which
# runs on the Mac. The game patch adds a tools-only mode that builds just ZAPD
# (with libultraship and OTRExporter, which need Homebrew's sdl2, glew, libzip,
# nlohmann-json, tinyxml2 and libpng) and the archive.
HOST_CMAKE_ARGS=(-DHARBOUR_TOOLS_ONLY=ON)
HOST_TARGETS=(Generate2ShipOtr)

# The game looks for 2ship.o2r and the extraction specs (assets/) in
# Ship::Context::GetAppBundlePath(), which the libultraship patch points at the
# framework. The layout is what the desktop build's POST_BUILD step makes next
# to the executable.
bundle_game_data() {
    rsync -a "$HARBOUR_ROOT/build/$GAME/host/mm/2ship.o2r" "$1/2ship.o2r"
    rsync -a --delete --exclude /xml "$GAME_PATH/mm/assets/extractor/" "$1/assets/"
    rsync -a --delete "$GAME_PATH/mm/assets/xml/" "$1/assets/xml/"
}
