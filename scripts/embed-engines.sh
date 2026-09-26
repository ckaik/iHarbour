#!/bin/bash
# Copies the games' frameworks into the app and signs them.
#
# Xcode runs this as a build phase of the iHarbour app target, after
# scripts/build-engines.sh put the frameworks in $BUILT_PRODUCTS_DIR/HarbourEngines.
# The app doesn't link the frameworks (it loads them with dlopen when needed), so
# Xcode's own "Embed Frameworks" phase, which wants linked ones, doesn't apply.
# Xcode signs the app itself after this phase, sealing the signed frameworks in.

set -euo pipefail

source_dir="$BUILT_PRODUCTS_DIR/HarbourEngines"
destination="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH"
mkdir -p "$destination"

# What each framework was embedded from, so unchanged ones aren't copied and
# signed again on every build.
stamps="$DERIVED_FILE_DIR/embedded-engines"
mkdir -p "$stamps"

built=()
for framework in "$source_dir"/*.framework; do
    [[ -e "$framework" ]] || continue
    name="$(basename "$framework")"
    built+=("$name")
    fingerprint="$(cd "$framework" && find . -type f -exec stat -f '%m %z %N' {} + | sort | shasum)"
    fingerprint+=" ${CODE_SIGNING_ALLOWED:-NO} ${EXPANDED_CODE_SIGN_IDENTITY:-} ${OTHER_CODE_SIGN_FLAGS:-}"
    if [[ -d "$destination/$name" && "$(cat "$stamps/$name" 2> /dev/null)" == "$fingerprint" ]]; then
        continue
    fi
    echo "note: embedding $name"
    rsync -a --delete "$framework/" "$destination/$name/"
    if [[ "${CODE_SIGNING_ALLOWED:-NO}" == "YES" && -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]]; then
        echo "note: signing $name with ${EXPANDED_CODE_SIGN_IDENTITY_NAME:-$EXPANDED_CODE_SIGN_IDENTITY}"
        codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" ${OTHER_CODE_SIGN_FLAGS:-} \
            --timestamp=none --preserve-metadata=identifier,entitlements,flags \
            "$destination/$name"
    fi
    echo "$fingerprint" > "$stamps/$name"
done

# Frameworks of games the build no longer includes. Every game's framework is
# signed by this script, and nothing else in the app is a framework, so anything
# not built this time goes.
for framework in "$destination"/*.framework; do
    [[ -e "$framework" ]] || continue
    name="$(basename "$framework")"
    if [[ ! " ${built[*]+"${built[*]}"} " == *" $name "* ]]; then
        echo "note: removing $name from the app"
        rm -rf "$framework"
    fi
done
