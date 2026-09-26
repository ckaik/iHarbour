# Lighthouse. Read by scripts/build-engine.sh.

GAME_TITLE="Lighthouse"
GAME_DIR=games/Lighthouse
FRAMEWORK_NAME=Lighthouse
CMAKE_TARGET=Lighthouse
FRAMEWORK_OUTPUT=Lighthouse.framework

PATCHES=(
    ".:lighthouse.patch"
    "libultraship:libultraship.patch"
)

# The game looks for lighthouse.o2r (its fonts, textures, models and shaders),
# and its extractor for config.yml next to assets/ (the extraction specs), in
# Ship::Context::GetAppBundlePath(), which the libultraship patch points at the
# framework.
bundle_game_data() {
    local framework="$1"
    local shaders="$GAME_PATH/libultraship/src/fast/shaders"

    # lighthouse.o2r is a zip of port/ plus libultraship's shaders in shaders/,
    # which the desktop build (GeneratePortO2R) makes by copying both into one
    # folder and running `torch pack <folder> lighthouse.o2r o2r`: every file
    # under its path relative to the folder, no directory entries. Packed again
    # only when one of the two changed (a changed, added or removed file makes
    # something in them newer), so an unchanged build hands over the same file.
    local packed
    packed="$(dirname "$framework")/lighthouse.o2r"
    if [[ ! -f "$packed" || -n "$(find "$GAME_PATH/port" "$shaders" -newer "$packed" -print -quit)" ]]; then
        harbour_note "packing lighthouse.o2r"
        local staging="$packed.staging"
        rm -rf "$staging"
        mkdir -p "$staging"
        rsync -a --exclude=.DS_Store "$GAME_PATH/port/" "$staging/"
        rsync -a --exclude=.DS_Store "$shaders/" "$staging/shaders/"
        local list="$packed.files"
        (cd "$staging" && find . -type f | sed 's|^\./||' | LC_ALL=C sort) > "$list"
        rm -f "$packed.tmp"
        (cd "$staging" && "${HARBOUR_CLEAN_ENV[@]}" cmake -E tar cf "$packed.tmp" --format=zip --files-from="$list")
        mv "$packed.tmp" "$packed"
        rm -rf "$staging"
    fi
    rsync -a "$packed" "$framework/lighthouse.o2r"

    rsync -a "$GAME_PATH/config.yml" "$framework/config.yml"
    rsync -a --delete --exclude=.DS_Store --exclude=/bko2r* --exclude=/log.txt "$GAME_PATH/assets/" "$framework/assets/"
}
