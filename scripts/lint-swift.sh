#!/bin/bash
# Lints the launcher's Swift code with swift-format and SwiftLint.
#
# Xcode runs this as a build phase of the iHarbour app target, so the findings
# show up in the issue navigator. Here they're warnings, apart from the ones
# SwiftLint itself rates as errors, so a change in progress still builds.
# `make lint` (also the pre-push hook) turns every finding into an error.

set -uo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
lint_path="$repo_root/app"

# Xcode's PATH leaves out Homebrew, where mint lives.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# swift-format prints paths relative to the working directory when that's above
# them, and Xcode links only absolute paths to the source.
(cd / && xcrun swift-format lint --recursive "$lint_path")

# mint takes SwiftLint's version from the Mintfile in the working directory.
# Without the pinned version it would fetch and build one, so it's skipped.
cd "$repo_root"
if ! command -v mint > /dev/null || ! mint which swiftlint > /dev/null 2>&1; then
    echo "warning: SwiftLint didn't run: it isn't installed. Run 'brew install mint' and 'mint bootstrap' in $repo_root."
    exit 0
fi
exec mint run --no-install --silent swiftlint lint --config .swiftlint.yml --quiet "$lint_path"
