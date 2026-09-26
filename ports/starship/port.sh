# Starship. Read by scripts/build-engine.sh.

GAME_TITLE="Starship"
GAME_DIR=games/Starship
FRAMEWORK_NAME=Starship
CMAKE_TARGET=Starship
FRAMEWORK_OUTPUT=Starship.framework

PATCHES=(
    ".:starship.patch"
    "libultraship:libultraship.patch"
)

# Dependencies libultraship and Torch pin (nlohmann_json, yaml-cpp) still declare
# a cmake_minimum_required that CMake 4 refuses.
IOS_CMAKE_ARGS=(-DCMAKE_POLICY_VERSION_MINIMUM=3.5)

# The game looks for starship.o2r (its Metal shader and a few textures) with
# LocateFileAcrossAppDirs, and Torch reads the extraction specs (config.yml,
# assets/yaml/) from Ship::Context::GetAppBundlePath(). The libultraship patch
# points that at the framework.
bundle_game_data() {
    local framework="$1"

    # starship.o2r is a zip of port/, which the desktop build makes with
    # `torch pack port starship.o2r o2r`: every file under its path relative to
    # port/, no directory entries. Packed again only when port/ changed (a
    # changed, added or removed file makes something in it newer), so an
    # unchanged build hands over the same file.
    local packed
    packed="$(dirname "$framework")/starship.o2r"
    if [[ ! -f "$packed" || -n "$(find "$GAME_PATH/port" -newer "$packed" -print -quit)" ]]; then
        harbour_note "packing starship.o2r"
        local list="$packed.files"
        (cd "$GAME_PATH/port" && find . -type f ! -name .DS_Store | sed 's|^\./||' | LC_ALL=C sort) > "$list"
        rm -f "$packed.tmp"
        (cd "$GAME_PATH/port" && "${HARBOUR_CLEAN_ENV[@]}" cmake -E tar cf "$packed.tmp" --format=zip --files-from="$list")
        mv "$packed.tmp" "$packed"
    fi
    rsync -a "$packed" "$framework/starship.o2r"

    # Torch logs every asset at the level the config sets (INFO); extraction runs
    # in the launcher, so only errors are logged. The copy keeps the original's
    # modification time, so it doesn't look new every build.
    sed 's/^\(    logging:\) INFO$/\1 ERROR/' "$GAME_PATH/config.yml" > "$framework/config.yml"
    touch -r "$GAME_PATH/config.yml" "$framework/config.yml"
    rsync -a --delete --exclude .DS_Store "$GAME_PATH/assets/" "$framework/assets/"
}
