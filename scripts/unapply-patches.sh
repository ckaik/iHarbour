#!/bin/bash
# Takes iHarbour's patches out of the games' submodules again.
#
#   scripts/unapply-patches.sh [<game>...]     # default: every game in ports/
#
# scripts/build-engine.sh leaves its patches applied in the submodules' working
# trees (hidden from the parent's `git status` by `ignore = dirty` in
# .gitmodules). Run this before updating a submodule, or to see the upstream
# code. The next build applies them again.

set -euo pipefail

HARBOUR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$HARBOUR_ROOT/scripts/lib/common.sh"

games=("$@")
if (( ${#games[@]} == 0 )); then
    read -r -a games <<< "$(harbour_games)"
fi

for game in "${games[@]}"; do
    GAME_DIR="" PATCHES=()
    source "$HARBOUR_ROOT/ports/$game/port.sh"
    # In reverse order, since later patches may build on earlier ones.
    for (( i = ${#PATCHES[@]} - 1; i >= 0; i-- )); do
        entry="${PATCHES[$i]}"
        dir="$HARBOUR_ROOT/$GAME_DIR/${entry%%:*}"
        patch="$HARBOUR_ROOT/patches/$game/${entry#*:}"
        if git -C "$dir" apply --reverse --check "$patch" 2> /dev/null; then
            git -C "$dir" apply --reverse "$patch"
            harbour_note "took ${patch#"$HARBOUR_ROOT"/} out of ${dir#"$HARBOUR_ROOT"/}"
        fi
    done
done
