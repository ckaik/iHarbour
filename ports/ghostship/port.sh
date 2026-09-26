# Ghostship. Read by scripts/build-engine.sh.

GAME_TITLE="Ghostship"
GAME_DIR=games/Ghostship
FRAMEWORK_NAME=Ghostship
CMAKE_TARGET=Ghostship
FRAMEWORK_OUTPUT=Ghostship.framework

PATCHES=(
    ".:ghostship.patch"
    "libultraship:libultraship.patch"
)

# ghostship.o2r, the game's own archive (fonts, textures, shaders), is what the
# game's GeneratePortO2R target makes with a Mac build of Torch: port/ with
# libultraship's shaders copied over port/shaders, zipped by `torch pack -u
# <version>`, which adds a portVersion entry (major, minor and patch as
# big-endian 16-bit integers). That's a plain zip, so it's packed here instead,
# without building Torch for the Mac. Repacked only when its inputs change.
ghostship_pack_port_archive() {
    local archive="$1"
    local shaders="$GAME_PATH/libultraship/src/fast/shaders"
    if [[ -f "$archive" ]] && [[ -z "$(find "$GAME_PATH/port" "$shaders" "$GAME_PATH/CMakeLists.txt" \
        "${BASH_SOURCE[0]}" -newer "$archive" -print -quit)" ]]; then
        return 0
    fi
    local version
    version="$(sed -n 's/^project(Ghostship VERSION \([0-9.]*\).*/\1/p' "$GAME_PATH/CMakeLists.txt")"
    harbour_note "packing ghostship.o2r ($version)"
    mkdir -p "$(dirname "$archive")"
    "${HARBOUR_CLEAN_ENV[@]}" python3 - "$GAME_PATH/port" "$shaders" "$version" "$archive" << 'EOF'
import os, struct, sys, zipfile

port, shaders, version, archive = sys.argv[1:]
files = {}
for root, prefix in ((port, ""), (shaders, "shaders/")):
    for directory, _, names in os.walk(root):
        for name in names:
            if name != ".DS_Store":
                path = os.path.join(directory, name)
                files[prefix + os.path.relpath(path, root).replace(os.sep, "/")] = path

temporary = archive + ".tmp"
with zipfile.ZipFile(temporary, "w", zipfile.ZIP_DEFLATED) as output:
    for name in sorted(files):
        output.write(files[name], name)
    output.writestr("portVersion", struct.pack(">HHH", *(int(part) for part in version.split("."))))
os.replace(temporary, archive)
EOF
}

# Torch's config.yml with `logging: ERROR` for every ROM. Torch otherwise sets
# spdlog to debug and logs each of the ROM's thousands of assets.
ghostship_quiet_torch_config() {
    local config="$1"
    if [[ -f "$config" && "$config" -nt "$GAME_PATH/config.yml" && "$config" -nt "${BASH_SOURCE[0]}" ]]; then
        return 0
    fi
    mkdir -p "$(dirname "$config")"
    awk '{ print } /^  config:$/ { print "    logging: ERROR" }' "$GAME_PATH/config.yml" > "$config.tmp"
    mv "$config.tmp" "$config"
}

# The game looks for ghostship.o2r, config.yml and the extraction specs
# (assets/ymls) in Ship::Context::GetAppBundlePath(), which the libultraship
# patch points at the framework. The generated files are kept in build/ghostship/
# so an unchanged build copies unchanged files (same modification times).
bundle_game_data() {
    local generated="$HARBOUR_ROOT/build/$GAME"
    ghostship_pack_port_archive "$generated/ghostship.o2r"
    ghostship_quiet_torch_config "$generated/config.yml"
    rsync -a "$generated/ghostship.o2r" "$1/ghostship.o2r"
    rsync -a "$generated/config.yml" "$1/config.yml"
    rsync -a --delete --exclude .DS_Store "$GAME_PATH/assets/" "$1/assets/"
}
