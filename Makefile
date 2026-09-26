XCODE_TOOLCHAIN := $(shell xcrun --show-toolchain-path)
SWIFT_FORMAT := $(XCODE_TOOLCHAIN)/usr/bin/swift-format
SWIFTLINT := mint run swiftlint
LINT_FORMAT_PATHS := app

default: hooks

hooks:
	git config core.hooksPath .githooks

format: check-mint
	$(SWIFTLINT) --config .swiftlint.yml --fix $(LINT_FORMAT_PATHS)
	$(SWIFT_FORMAT) format --in-place --recursive $(LINT_FORMAT_PATHS)

lint: lint-format lint-swift

lint-format:
	$(SWIFT_FORMAT) lint --strict --recursive $(LINT_FORMAT_PATHS)

lint-swift: check-mint
	$(SWIFTLINT) lint --config .swiftlint.yml --strict $(LINT_FORMAT_PATHS)

check-mint:
	@command -v mint >/dev/null 2>&1 || { echo "mint is not installed. Install with 'brew install mint', then run 'mint bootstrap' to install the pinned SwiftLint." >&2; exit 1; }

.PHONY: hooks format lint lint-format lint-swift check-mint
