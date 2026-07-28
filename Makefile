.PHONY: build api-dump surface-check hygiene-check reflection-check gate clean

SCHEME := otpless-ios-intelligence-sdk
DERIVED_DATA := .build/xcode-derived-data

# ---------------------------------------------------------------------------
# Verification
# ---------------------------------------------------------------------------
#
# NOTE: `swift build` cannot be used in this repo. The package declares iOS as its only
# platform and depends on the IdentityFraud.xcframework binary target, which has no
# macOS slice — so a host build is impossible by construction. Everything goes through
# xcodebuild against an iOS Simulator destination instead.

build:
	xcodebuild build -scheme $(SCHEME) \
		-destination 'generic/platform=iOS Simulator' \
		-derivedDataPath $(DERIVED_DATA)

# Regenerate the committed public-API golden. Review the resulting diff — it is
# exactly what a consumer of the next release would see.
api-dump:
	bash scripts/check-public-surface.sh --update

surface-check:
	bash scripts/check-public-surface.sh

hygiene-check:
	bash scripts/check-release-hygiene.sh

# The reflection-contract check on its own — the check with the worst failure mode
# in this repo. See the long explanation at the top of the script.
reflection-check:
	bash scripts/check-reflection-contract.sh

# THE GATE — the single canonical definition of "verified" for this repo.
# CLAUDE.md and .github/workflows/build-test.yml restate this recipe; change it HERE
# first. Nothing may be merged to main that has not passed `make gate`.
#
#   check-release-hygiene.sh     : fails if OTPLESS_DEBUG is enabled in Package.swift
#                                  (would ship verbose request/response logging to
#                                  every consumer), and reports resolved versions.
#   check-reflection-contract.sh : asserts the ObjC class name and the
#                                  fetchIntelligenceWithParams:updateInfo:completion:
#                                  selector the iOS SDK dispatches by string still
#                                  exist. A rename compiles everywhere and SILENTLY
#                                  disables device intelligence — this already
#                                  happened for the whole 2.x line.
#   check-public-surface.sh      : builds for the iOS Simulator and diffs the compiled
#                                  module's public symbol graph — including @objc
#                                  selectors — against api/public-surface.txt.
#
# There is NO `swift test` / xcodebuild test step: this repo has no test target at all
# (Package.swift declares only the binary target and the library target). Adding one is
# a separate piece of work; do not read the green gate as "the tests pass".
gate:
	bash scripts/check-release-hygiene.sh
	bash scripts/check-reflection-contract.sh
	bash scripts/check-public-surface.sh

clean:
	rm -rf $(DERIVED_DATA) .build
