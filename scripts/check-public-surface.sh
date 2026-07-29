#!/usr/bin/env bash
#
# Public-surface golden check for the OTPlessIntelligence Swift module.
#
# WHY THIS EXISTS
# ---------------
# OTPlessIntelligence is not consumed by merchants directly — it ships *inside* the
# OTPLESS iOS SDK. A change to a public symbol, a signature, a default argument, or an
# @objc selector therefore reaches merchant apps through a routine version bump, and
# until this check existed nothing in the repo would notice.
#
# The @objc surface matters as much as the Swift one: `OTPlessIntelligence` is an
# @objc final class whose selectors (e.g. initializeWithAppId:completion:) are what
# Objective-C and bridged consumers bind to by NAME at runtime. Renaming a Swift
# parameter can change the generated selector, which no Swift compiler will flag for a
# consumer that calls it dynamically. The symbol graph below records the selectors, so
# this golden covers them.
#
# WHAT IT CHECKS
# --------------
# It builds the package for the iOS Simulator (this package is iOS-only and depends on
# the IdentityFraud.xcframework binary target, so `swift build` for the macOS host
# cannot work), runs the compiler's own symbol-graph extractor over the built module,
# and diffs a normalised, sorted rendering of every public symbol against a committed
# golden.
#
# Usage:
#   scripts/check-public-surface.sh            # verify against the golden
#   scripts/check-public-surface.sh --update   # regenerate the golden (review the diff!)
#
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

MODULE="OTPlessIntelligence"
SCHEME="otpless-ios-intelligence-sdk"
GOLDEN_PATH="api/public-surface.txt"
DERIVED_DATA="${DERIVED_DATA:-.build/xcode-derived-data}"
PRODUCTS_DIR="$DERIVED_DATA/Build/Products/Debug-iphonesimulator"

UPDATE=0
if [[ "${1:-}" == "--update" ]]; then
  UPDATE=1
fi

echo "Building $SCHEME for iOS Simulator ..." >&2
xcodebuild build \
  -scheme "$SCHEME" \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$DERIVED_DATA" \
  -quiet >&2

if [[ ! -d "$PRODUCTS_DIR/$MODULE.swiftmodule" ]]; then
  echo "error: $PRODUCTS_DIR/$MODULE.swiftmodule not found after build" >&2
  exit 1
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# The golden is extracted for the arm64 simulator slice. The public surface has no
# per-slice differences (no #if arch(...) in Sources/), so one slice is sufficient and
# keeps the golden stable regardless of the host machine's architecture.
xcrun --sdk iphonesimulator swift-symbolgraph-extract \
  -module-name "$MODULE" \
  -I "$PRODUCTS_DIR" \
  -F "$PRODUCTS_DIR" \
  -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  -target arm64-apple-ios13.0-simulator \
  -minimum-access-level public \
  -output-dir "$WORKDIR" >&2

SYMBOLS_JSON="$WORKDIR/$MODULE.symbols.json"
if [[ ! -f "$SYMBOLS_JSON" ]]; then
  echo "error: symbol graph not produced at $SYMBOLS_JSON" >&2
  exit 1
fi

ACTUAL_PATH="$WORKDIR/actual-surface.txt"

# Deterministic rendering: one sorted line per public symbol.
#   <accessLevel> <symbol-kind> <dotted path> :: <declaration>
# Nothing version- or path-dependent (no USRs, no file paths, no source locations) so
# the golden is stable across machines and toolchain patch releases.
python3 - "$SYMBOLS_JSON" > "$ACTUAL_PATH" <<'PY'
import json, sys

data = json.load(open(sys.argv[1]))
lines = set()
for sym in data.get("symbols", []):
    access = sym.get("accessLevel", "?")
    if access not in ("public", "open"):
        continue
    kind = sym["kind"]["identifier"]
    path = ".".join(sym.get("pathComponents", []))
    decl = "".join(f["spelling"] for f in sym.get("declarationFragments", []))
    decl = " ".join(decl.split())
    lines.add(f"{access} {kind} {path} :: {decl}")

if not lines:
    sys.exit("error: symbol graph contained no public symbols — refusing to write a golden")

for line in sorted(lines):
    print(line)
PY

if [[ ! -s "$ACTUAL_PATH" ]]; then
  echo "error: extracted surface is empty — refusing to compare" >&2
  exit 1
fi

if [[ "$UPDATE" -eq 1 ]]; then
  mkdir -p "$(dirname "$GOLDEN_PATH")"
  cp "$ACTUAL_PATH" "$GOLDEN_PATH"
  echo "Updated golden file: $GOLDEN_PATH"
  exit 0
fi

if [[ ! -f "$GOLDEN_PATH" ]]; then
  echo "error: golden file $GOLDEN_PATH does not exist. Run with --update to create it." >&2
  exit 1
fi

if diff -u "$GOLDEN_PATH" "$ACTUAL_PATH"; then
  echo "OK: public surface of $MODULE matches $GOLDEN_PATH"
  exit 0
fi

cat >&2 <<EOF

=====================================================================
PUBLIC SURFACE CHANGED — the diff above is what consumers would see.
=====================================================================
OTPlessIntelligence ships inside the OTPLESS iOS SDK, so anything above
reaches merchant apps through a version bump there.

Watch for @objc selector changes in particular (the '@objc(...)'
fragments above): Objective-C and bridged callers resolve those by name
at runtime, so a changed selector fails at CALL TIME, not build time.

If the change is intentional:
  1. Confirm no consumer breaks (grep the iOS SDK for the symbol and,
     for @objc members, for the selector string).
  2. Note it in CHANGELOG.md so the consumer's bump protocol can
     classify the bump.
  3. Regenerate the golden: scripts/check-public-surface.sh --update
If it is not intentional, fix the source.
EOF
exit 1
