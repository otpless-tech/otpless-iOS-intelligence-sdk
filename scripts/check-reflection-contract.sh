#!/usr/bin/env bash
#
# =============================================================================
#  REFLECTION CONTRACT CHECK — the check with the worst failure mode here
# =============================================================================
#
# The OTPLESS iOS SDK (OtplessBM) does NOT link or import this package. It discovers
# it at RUNTIME through the Objective-C runtime, by string:
#
#   otpless-headless-iOS-sdk
#     Sources/OtplessBM/usecase/IntelligenceUseCase.swift
#
#       NSClassFromString("OTPlessIntelligence.OTPlessIntelligence")
#       NSSelectorFromString("shared")
#       NSSelectorFromString("fetchIntelligenceWithParams:updateInfo:completion:")
#       // dispatched via class_getMethodImplementation + a typed IMP cast:
#       //   (AnyObject, Selector, NSDictionary?, NSDictionary?, AnyObject) -> Void
#       // with the completion block typed
#       //   (Bool, String?, NSDictionary?, String?) -> Void
#
#   ...and every lookup failure path just calls `completion(nil)`.
#
# WHAT THAT MEANS
# ---------------
# If the ObjC class name, the `shared` accessor, or that selector changes, NOTHING
# fails: this package compiles, OtplessBM compiles (there is no link edge), and at
# runtime `responds(to:)` returns false, one os_log line is written, and the
# transaction simply proceeds without device intelligence. No crash, no exception.
#
# THIS HAS ALREADY HAPPENED IN PRODUCTION. The iOS SDK's own CHANGELOG records it:
#
#   "Fixed device intelligence integration: the previous
#    `runDeviceIntelligenceWithParams:onComplete:` selector did not exist on
#    `OTPlessIntelligence`; device intelligence never ran in 2.x releases."
#
# An entire major version shipped with the fraud/risk signal silently dead. This
# script is the mechanical check that would have caught it.
#
# Note also that the selector is derived from Swift ARGUMENT LABELS: renaming the
# `params:` label — a change no reviewer would call breaking — changes the selector.
#
# IF THIS CHECK FAILS, DO NOT "FIX" IT BY EDITING THIS SCRIPT.
# Either restore the name, or coordinate the change with the iOS SDK in the same
# release cycle (hub CLAUDE.md change-flow rules 2 and 3) and only then update the
# expectations below.
#
# Usage: scripts/check-reflection-contract.sh
#
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

SCHEME="otpless-ios-intelligence-sdk"
MODULE="OTPlessIntelligence"
DERIVED_DATA="${DERIVED_DATA:-.build/xcode-derived-data}"

# The ObjC runtime name for a Swift class is _TtC<len><module><len><class>.
# "OTPlessIntelligence" is 19 characters, hence 19/19 — this is exactly what
# NSClassFromString("OTPlessIntelligence.OTPlessIntelligence") resolves to.
EXPECTED_RUNTIME_NAME='_TtC19OTPlessIntelligence19OTPlessIntelligence'

fail() {
  echo "" >&2
  echo "=============================================================" >&2
  echo " REFLECTION CONTRACT BROKEN" >&2
  echo "=============================================================" >&2
  echo "$1" >&2
  cat >&2 <<'EOF'

CONSEQUENCE IF THIS SHIPS
-------------------------
OtplessBM resolves this class and selector by string via NSClassFromString /
NSSelectorFromString, and every failure path calls completion(nil). A missing
or re-signed symbol therefore does NOT crash and does NOT throw: device
intelligence silently stops running for every merchant app.

This exact failure already shipped once — the iOS SDK CHANGELOG records that
device intelligence "never ran in 2.x releases" because the selector it
dispatched did not exist.

WHAT TO DO
----------
1. Restore the exact ObjC class name / selector, OR
2. If the change is deliberate: port the matching change to
   Sources/OtplessBM/usecase/IntelligenceUseCase.swift in the iOS SDK in the
   same cycle (hub CLAUDE.md change-flow rules 2 and 3), then update the
   expectations in this script in the same PR.

Do NOT relax this check to make the build green.
EOF
  exit 1
}

echo "Building $SCHEME for iOS Simulator ..." >&2
xcodebuild build \
  -scheme "$SCHEME" \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$DERIVED_DATA" \
  -quiet >&2

# The compiler-generated Objective-C interface header is the authority on what the ObjC
# runtime will actually see: runtime class name, selectors, and block signatures.
HEADER="$(find "$DERIVED_DATA" -name "$MODULE-Swift.h" -print 2>/dev/null | head -1)"
if [[ -z "$HEADER" || ! -f "$HEADER" ]]; then
  fail "Generated Objective-C header $MODULE-Swift.h not found under $DERIVED_DATA.
Without it the @objc surface cannot be verified. If the class stopped being @objc at
all, that alone breaks the contract — OtplessBM would find nothing."
fi
echo "Reflection contract for $MODULE (from $(basename "$HEADER")):" >&2

require() {
  local what="$1" pattern="$2"
  if ! grep -qF -- "$pattern" "$HEADER"; then
    fail "Reflected symbol missing or renamed in the generated ObjC interface:
  caller does : $what
  expected    : $pattern

Search the generated header for what is actually exposed:
  $HEADER"
  fi
  echo "  ok  $what"
}

require \
  'NSClassFromString("OTPlessIntelligence.OTPlessIntelligence")' \
  "SWIFT_CLASS(\"$EXPECTED_RUNTIME_NAME\")"

require \
  'NSSelectorFromString("shared") (class accessor)' \
  '+ (OTPlessIntelligence * _Nonnull)shared'

# The full selector plus the completion block's ObjC type. The block type is checked
# because IntelligenceUseCase casts the IMP to a @convention(c) function whose last
# argument is a block of exactly this shape; changing the block's parameters would
# corrupt the call at runtime rather than fail to resolve.
require \
  'NSSelectorFromString("fetchIntelligenceWithParams:updateInfo:completion:")' \
  '- (void)fetchIntelligenceWithParams:'

require \
  'fetch selector: updateInfo: + completion: labels (they form the selector)' \
  'updateInfo:(NSDictionary<NSString *, id> * _Nullable)updateInfo completion:'

require \
  'fetch completion block shape (Bool, String?, NSDictionary?, String?)' \
  '(void (^ _Nonnull)(BOOL, NSString * _Nullable, NSDictionary * _Nullable, NSString * _Nullable))completion'

echo "OK: reflection contract intact — the iOS SDK can still reach device intelligence."
