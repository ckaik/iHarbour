#!/bin/bash
# Builds one game's framework for iOS.
#
#   scripts/build-engine.sh <game>        # <game> is a folder in ports/: soh, 2ship, ...
#
# Xcode runs this for every game through scripts/build-engines.sh (the
# HarbourEngines target of app/iHarbour.xcodeproj). It also runs on its own.
#
# The game builds with CMake and Ninja, the way the desktop builds do, into
# build/<game>/ at the repo root. Those directories outlive Xcode's DerivedData,
# so "Clean Build Folder" doesn't cost a full rebuild of seven games.
#
# Steps:
#   1. Apply the game's patches (patches/<game>/) to its submodules, unless
#      they're applied already.
#   2. If the game packs its own assets with a tool that has to run on this Mac,
#      build that tool and the archive in a macOS build (build/<game>/host).
#   3. Configure (again whenever the arguments change) and build the game
#      for $PLATFORM_NAME (build/<game>/<platform>-<build type>).
#   4. Put the framework, with the game's read-only data inside it, into
#      $BUILT_PRODUCTS_DIR/HarbourEngines/.
#
# Environment (Xcode sets the first three; defaults are for running by hand):
#   PLATFORM_NAME                iphoneos or iphonesimulator (default iphonesimulator)
#   IPHONEOS_DEPLOYMENT_TARGET   minimum iOS version (default 17.0)
#   BUILT_PRODUCTS_DIR           where HarbourEngines/ goes (default build/products/<platform>)
#   HARBOUR_ENGINE_BUILD_TYPE    CMake build type of the games (default Release)
#   HARBOUR_JOBS                 parallel compile jobs (default: Ninja's choice)
#   HARBOUR_KEEP_DEPENDENCY_HISTORY  1 keeps the git history of the dependency checkouts

set -euo pipefail

HARBOUR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$HARBOUR_ROOT/scripts/lib/common.sh"

GAME="${1:-}"
if [[ -z "$GAME" || ! -f "$HARBOUR_ROOT/ports/$GAME/port.sh" ]]; then
    echo "usage: $0 <game>, where <game> is one of: $(harbour_games)" >&2
    exit 64
fi

PLATFORM_NAME="${PLATFORM_NAME:-iphonesimulator}"
IPHONEOS_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-17.0}"
BUILT_PRODUCTS_DIR="${BUILT_PRODUCTS_DIR:-$HARBOUR_ROOT/build/products/$PLATFORM_NAME}"
# One optimized build serves Xcode's Debug and Release configurations: the
# launcher is what gets debugged, an unoptimized game is too slow to play on a
# phone, and seven games' worth of build directories take a lot of disk. Line
# tables keep crash reports symbolicated.
HARBOUR_ENGINE_BUILD_TYPE="${HARBOUR_ENGINE_BUILD_TYPE:-Release}"

case "$PLATFORM_NAME" in
    iphoneos | iphonesimulator) ;;
    *)
        echo "error: build-engine.sh builds for iphoneos or iphonesimulator, not $PLATFORM_NAME" >&2
        exit 1
        ;;
esac

# --- The game's recipe ---------------------------------------------------------
# port.sh sets:
#   GAME_TITLE          name for messages
#   GAME_DIR            the game's submodule, relative to the repo root
#   FRAMEWORK_NAME      name of the framework (and of its binary)
#   CMAKE_TARGET        the CMake target that builds the framework
#   FRAMEWORK_OUTPUT    where the framework ends up, relative to the build directory
#   PATCHES             "<dir relative to GAME_DIR>:<patch in patches/<game>/>" pairs,
#                       applied in order
#   HOST_CMAKE_ARGS     arguments for the macOS build; empty means none is needed
#   HOST_TARGETS        what to build in it
#   IOS_CMAKE_ARGS      extra arguments for the iOS build
# and defines bundle_game_data <framework dir> <build dir>, which copies the
# game's read-only data (its own archive, extraction specs) into the framework.
# <build dir> is the game's iOS build directory, for data the build makes.
GAME_TITLE="" GAME_DIR="" FRAMEWORK_NAME="" CMAKE_TARGET="" FRAMEWORK_OUTPUT=""
PATCHES=() HOST_CMAKE_ARGS=() HOST_TARGETS=() IOS_CMAKE_ARGS=()
source "$HARBOUR_ROOT/ports/$GAME/port.sh"
GAME_PATH="$HARBOUR_ROOT/$GAME_DIR"

harbour_note "building $GAME_TITLE ($GAME) for $PLATFORM_NAME, $HARBOUR_ENGINE_BUILD_TYPE"

harbour_require_tools
if [[ ! -f "$GAME_PATH/CMakeLists.txt" ]]; then
    echo "error: $GAME_DIR is missing. Run: git submodule update --init --recursive" >&2
    exit 1
fi

# --- 1. Patches -------------------------------------------------------------------
for entry in ${PATCHES[@]+"${PATCHES[@]}"}; do
    harbour_apply_patch "$GAME_PATH/${entry%%:*}" "$HARBOUR_ROOT/patches/$GAME/${entry#*:}"
done

build_root="$HARBOUR_ROOT/build/$GAME"

# configure_and_build <build dir> <targets> <configure arguments...>
#
# Configures the CMake build in <build dir> unless it's configured with exactly
# these arguments already, then builds <targets> (a space-separated list). If
# that fails and dependencies had their history pruned (see
# harbour_prune_dependency_history), which FetchContent can then neither update
# nor patch again, it starts those dependencies over and tries once more.
configure_and_build() {
    local dir="$1" targets="$2"
    shift 2
    # The compilers are named explicitly: CMake ignores CC and CXX once it has
    # cached a compiler, and a different Xcode must mean a fresh configure.
    local args=(
        -G Ninja
        -DCMAKE_C_COMPILER="$HARBOUR_CC"
        -DCMAKE_CXX_COMPILER="$HARBOUR_CXX"
        -DFETCHCONTENT_UPDATES_DISCONNECTED=ON
        "$@"
    )
    local attempt
    for attempt in 1 2; do
        if try_configure_and_build "$dir" "$targets" "${args[@]}"; then
            harbour_prune_dependency_history "$dir"
            return 0
        fi
        if (( attempt == 2 )) || ! harbour_reset_pruned_dependencies "$dir"; then
            return 1
        fi
        harbour_note "retrying with fresh copies of the dependencies whose history was pruned"
    done
}

try_configure_and_build() {
    local dir="$1" targets="$2"
    shift 2
    if harbour_needs_configure "$dir" "$@"; then
        harbour_note "configuring $dir"
        "${HARBOUR_CLEAN_ENV[@]}" cmake -S "$GAME_PATH" -B "$dir" "$@" || return 1
        harbour_write_configure_stamp "$dir" "$@"
    fi
    # $targets is a list on purpose.
    # shellcheck disable=SC2086
    "${HARBOUR_CLEAN_ENV[@]}" cmake --build "$dir" --target $targets ${HARBOUR_JOBS:+-j "$HARBOUR_JOBS"}
}

# --- 2. Host tools ----------------------------------------------------------------
if (( ${#HOST_CMAKE_ARGS[@]} > 0 )); then
    harbour_note "building host tools: ${HOST_TARGETS[*]}"
    configure_and_build "$build_root/host" "${HOST_TARGETS[*]}" \
        -DCMAKE_BUILD_TYPE=Release \
        "${HOST_CMAKE_ARGS[@]}"
fi

# --- 3. The framework -------------------------------------------------------------
engine_dir="$build_root/$PLATFORM_NAME-$HARBOUR_ENGINE_BUILD_TYPE"
harbour_note "building $FRAMEWORK_NAME.framework for $PLATFORM_NAME (iOS $IPHONEOS_DEPLOYMENT_TARGET) in $engine_dir"
# CMake's own iOS support with Ninja. libultraship pulls in leetal/ios-cmake,
# which only works with the Xcode generator, so that include gets a stub.
configure_and_build "$engine_dir" "$CMAKE_TARGET" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$PLATFORM_NAME" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$IPHONEOS_DEPLOYMENT_TARGET" \
    -DCMAKE_BUILD_TYPE="$HARBOUR_ENGINE_BUILD_TYPE" \
    -DCMAKE_C_FLAGS="-gline-tables-only" \
    -DCMAKE_CXX_FLAGS="-gline-tables-only" \
    -DCMAKE_OBJC_FLAGS="-gline-tables-only" \
    -DCMAKE_OBJCXX_FLAGS="-gline-tables-only" \
    -DFETCHCONTENT_SOURCE_DIR_IOSTOOLCHAIN="$HARBOUR_ROOT/cmake/ios-toolchain-stub" \
    -DHARBOUR_ROOT="$HARBOUR_ROOT" \
    -DHARBOUR_GAME="$GAME" \
    -DHARBOUR_FRAMEWORK_NAME="$FRAMEWORK_NAME" \
    ${IOS_CMAKE_ARGS[@]+"${IOS_CMAKE_ARGS[@]}"}

# --- 4. Hand it over ----------------------------------------------------------------
# The framework plus the game's data, assembled next to the build, then copied
# as a whole. rsync -a keeps modification times, so unchanged data doesn't look
# new to the app's embed step, and --link-dest makes the copies hard links, so
# they cost no disk space. (rsync and ld replace files rather than write into
# them, so a hard link never changes behind another copy's back.)
built="$engine_dir/$FRAMEWORK_OUTPUT"
staged="$engine_dir/harbour-dist/$FRAMEWORK_NAME.framework"
mkdir -p "$(dirname "$staged")"
rsync -a --delete --link-dest="$built/" "$built/" "$staged/"
bundle_game_data "$staged" "$engine_dir"

destination="$BUILT_PRODUCTS_DIR/HarbourEngines"
mkdir -p "$destination"
rsync -a --delete --link-dest="$staged/" "$staged/" "$destination/$FRAMEWORK_NAME.framework/"
harbour_note "$FRAMEWORK_NAME.framework is in $destination"
