# Ship of Harkinian. Read by scripts/build-engine.sh.

GAME_TITLE="Ship of Harkinian"
GAME_DIR=games/Shipwright
FRAMEWORK_NAME=ShipOfHarkinian
CMAKE_TARGET=soh
FRAMEWORK_OUTPUT=soh/ShipOfHarkinian.framework

PATCHES=(
    ".:shipwright.patch"
    "libultraship:libultraship.patch"
)

# soh.o2r, the game's own assets (soh/assets/custom), is packed by a tool that
# runs on the Mac. The top-level CMakeLists.txt has a tools-only mode for that.
HOST_CMAKE_ARGS=(-DSOH_TOOLS_ONLY=ON)
HOST_TARGETS=(GenerateSohOtr)

# The game looks for soh.o2r and the extraction specs (assets/) in
# Ship::Context::GetAppBundlePath(), which the libultraship patch points at the
# framework.
bundle_game_data() {
    rsync -a "$GAME_PATH/soh.o2r" "$1/soh.o2r"
    rsync -a --delete "$GAME_PATH/soh/assets/yml/" "$1/assets/"
}
