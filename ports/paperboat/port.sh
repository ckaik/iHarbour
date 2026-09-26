# PaperBoat. Read by scripts/build-engine.sh.

GAME_TITLE="PaperBoat"
GAME_DIR=games/PaperBoat
FRAMEWORK_NAME=PaperBoat
CMAKE_TARGET=Paperboat
FRAMEWORK_OUTPUT=PaperBoat.framework

PATCHES=(
    ".:paperboat.patch"
    "external/libultraship:libultraship.patch"
)

# paperboat.o2r, the game's own assets (port/), is a plain zip that the iOS
# build's GeneratePortO2R target writes into the build directory, so no host
# build is needed.

# The game looks for paperboat.o2r, config.yml and the extraction specs
# (assets/) in Ship::Context::GetAppBundlePath(), which the libultraship patch
# points at the framework. Torch reads config.yml and assets/yaml/us from there.
bundle_game_data() {
    local port_archive="$2/paperboat.o2r"
    if [[ ! -f "$port_archive" ]]; then
        echo "error: $port_archive is missing; the GeneratePortO2R target should have made it" >&2
        exit 1
    fi
    rsync -a "$port_archive" "$1/paperboat.o2r"
    rsync -a "$GAME_PATH/config.yml" "$1/config.yml"
    rsync -a --delete "$GAME_PATH/assets/" "$1/assets/"
}
