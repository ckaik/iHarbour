# SpaghettiKart. Read by scripts/build-engine.sh.

GAME_TITLE="SpaghettiKart"
GAME_DIR=games/SpaghettiKart
FRAMEWORK_NAME=SpaghettiKart
CMAKE_TARGET=Spaghettify
FRAMEWORK_OUTPUT=SpaghettiKart.framework

PATCHES=(
    ".:spaghettikart.patch"
    "libultraship:libultraship.patch"
)

# The game looks for spaghetti.o2r (its fonts, shaders and textures) and the
# extraction specs (config.yml, yamls/, meta/mods.toml) in
# Ship::Context::GetAppBundlePath(), which the libultraship patch points at the
# framework.
bundle_game_data() {
    local framework="$1"

    # spaghetti.o2r is a zip of assets/, which the desktop build makes with
    # `torch pack assets spaghetti.o2r o2r`: every file under its path relative to
    # assets/, no directory entries. Packed again only when assets/ changed (a
    # changed, added or removed file makes something in it newer), so an
    # unchanged build hands over the same file.
    local packed
    packed="$(dirname "$framework")/spaghetti.o2r"
    if [[ ! -f "$packed" || -n "$(find "$GAME_PATH/assets" -newer "$packed" -print -quit)" ]]; then
        harbour_note "packing spaghetti.o2r"
        local list="$packed.files"
        (cd "$GAME_PATH/assets" && find . -type f ! -name .DS_Store | sed 's|^\./||' | LC_ALL=C sort) > "$list"
        rm -f "$packed.tmp"
        (cd "$GAME_PATH/assets" && "${HARBOUR_CLEAN_ENV[@]}" cmake -E tar cf "$packed.tmp" --format=zip --files-from="$list")
        mv "$packed.tmp" "$packed"
    fi
    rsync -a "$packed" "$framework/spaghetti.o2r"

    # Torch logs every asset at debug level unless its config says otherwise;
    # extraction runs in the launcher, so only errors are logged. The copy keeps
    # the original's modification time, so it doesn't look new every build. It's
    # written next to the old one and moved over it: the old one may be a hard
    # link to the copy in HarbourEngines/.
    awk '{ print } /^  config:$/ { print "    logging: ERROR" }' "$GAME_PATH/config.yml" > "$framework/config.yml.tmp"
    touch -r "$GAME_PATH/config.yml" "$framework/config.yml.tmp"
    mv "$framework/config.yml.tmp" "$framework/config.yml"
    rsync -a --delete "$GAME_PATH/yamls/" "$framework/yamls/"
    rsync -a --delete "$GAME_PATH/meta/" "$framework/meta/"
}
