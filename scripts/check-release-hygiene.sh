#!/usr/bin/env bash
#
# Release-hygiene checks for otpless-iOS-intelligence-sdk.
#
# 1) OTPLESS_DEBUG must not be enabled.
#    Package.swift carries this warning, in the repo's own words:
#
#      // REMOVE the `swiftSettings: [.define("OTPLESS_DEBUG")]` line on the
#      // OTPlessIntelligence target before publishing any release tag / pushing
#      // to main / cutting a podspec bump — otherwise every SPM consumer will
#      // inherit the verbose request/response logging.
#
#    A comment cannot enforce itself. This does. Verbose request/response logging in
#    a merchant's production app is a privacy problem, not just noise.
#
# 2) The podspec version and the CocoaPods dependency constraint are reported, so the
#    gate output always states what a consumer would resolve.
#
# Usage: scripts/check-release-hygiene.sh
#
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

status=0

# --- 1) OTPLESS_DEBUG must not be active -------------------------------------------
# Match a `.define("OTPLESS_DEBUG")` occurrence that is NOT on a commented-out line.
if grep -n 'OTPLESS_DEBUG' Package.swift | grep -v '^\s*[0-9]*:\s*//' | grep -q 'define'; then
  echo "" >&2
  echo "=============================================================" >&2
  echo " OTPLESS_DEBUG IS ENABLED IN Package.swift" >&2
  echo "=============================================================" >&2
  grep -n 'OTPLESS_DEBUG' Package.swift >&2
  cat >&2 <<'EOF'

Every SPM consumer of this package — and therefore every merchant app that
ships the OTPLESS iOS SDK — would inherit verbose request/response logging.
Comment the `swiftSettings: [.define("OTPLESS_DEBUG")]` line out again before
merging to main, tagging a release, or bumping the podspec.
EOF
  status=1
else
  echo "  ok  OTPLESS_DEBUG not enabled in Package.swift"
fi

# --- 2) report the versions a consumer resolves ------------------------------------
POD_VERSION="$(grep -E "s\.version\s*=" OTPlessIntelligence.podspec | head -1 | sed -e "s/.*'\(.*\)'.*/\1/")"
EVENTIO_DEP="$(grep -E "s\.dependency\s+'OtplessEventIO'" OTPlessIntelligence.podspec | head -1 | sed -e 's/^[[:space:]]*//')"
echo "  info podspec version: ${POD_VERSION:-<unparsed>}"
echo "  info ${EVENTIO_DEP:-<no OtplessEventIO dependency line found>}"

if [[ "$status" -eq 0 ]]; then
  echo "OK: release hygiene checks passed"
fi
exit "$status"
