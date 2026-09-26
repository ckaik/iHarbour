#!/bin/bash
# Builds the frameworks of all games the app includes, one after the other.
#
# Xcode runs this from the HarbourEngines target of app/iHarbour.xcodeproj before
# it builds the app. It builds the games listed in HARBOUR_GAMES (a build setting,
# see app/Config/Project.xcconfig), or every game in ports/ when that's empty,
# and removes frameworks of games no longer listed, so the app leaves them out.
#
# Environment: that of build-engine.sh, plus
#   HARBOUR_GAMES   space-separated game ids (default: every game in ports/)

set -euo pipefail

HARBOUR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$HARBOUR_ROOT/scripts/lib/common.sh"

PLATFORM_NAME="${PLATFORM_NAME:-iphonesimulator}"
BUILT_PRODUCTS_DIR="${BUILT_PRODUCTS_DIR:-$HARBOUR_ROOT/build/products/$PLATFORM_NAME}"
export PLATFORM_NAME BUILT_PRODUCTS_DIR

if [[ "${ACTION:-build}" == "clean" ]]; then
    # Keep build/: a clean rebuild of seven games takes a long time and is rarely
    # what "Clean Build Folder" is after. Delete build/<game> by hand for that.
    rm -rf "$BUILT_PRODUCTS_DIR/HarbourEngines"
    exit 0
fi

games="${HARBOUR_GAMES:-}"
if [[ -z "${games// /}" ]]; then
    games="$(harbour_games)"
fi

wanted_frameworks=()
for game in $games; do
    if [[ ! -f "$HARBOUR_ROOT/ports/$game/port.sh" ]]; then
        echo "error: HARBOUR_GAMES names '$game', which has no port. Games: $(harbour_games)" >&2
        exit 1
    fi
    "$HARBOUR_ROOT/scripts/build-engine.sh" "$game"
    wanted_frameworks+=("$(FRAMEWORK_NAME="" && source "$HARBOUR_ROOT/ports/$game/port.sh" && echo "$FRAMEWORK_NAME")")
done

# Frameworks of games that were built before but aren't wanted any more.
for framework in "$BUILT_PRODUCTS_DIR/HarbourEngines"/*.framework; do
    [[ -e "$framework" ]] || continue
    name="$(basename "$framework" .framework)"
    if [[ ! " ${wanted_frameworks[*]} " == *" $name "* ]]; then
        harbour_note "removing $name.framework, which HARBOUR_GAMES leaves out"
        rm -rf "$framework"
    fi
done
