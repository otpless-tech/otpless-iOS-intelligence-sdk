# CLAUDE.md — otpless-iOS-intelligence-sdk

**This repo is a shared library, not an SDK.** It has no SDK-GUIDE, no artifact-size
budget, and no merchant-facing response contract of its own. What it has is a **public
surface that reaches merchant apps through the OTPLESS iOS SDK** — and the most important
part of that surface is reached by **runtime reflection**, where a mistake is invisible.

## Read this first: the reflection contract

`OtplessBM` (the OTPLESS iOS SDK) does **not** link or import this package. It discovers
it at runtime through the Objective-C runtime, by string, in
`Sources/OtplessBM/usecase/IntelligenceUseCase.swift`:

```swift
NSClassFromString("OTPlessIntelligence.OTPlessIntelligence")
NSSelectorFromString("shared")
NSSelectorFromString("fetchIntelligenceWithParams:updateInfo:completion:")
// dispatched via class_getMethodImplementation + a typed IMP cast, with the
// completion block typed (Bool, String?, NSDictionary?, String?) -> Void
```

Every failure path there just calls `completion(nil)`. So if the ObjC class name, the
`shared` accessor, or that selector changes: this package compiles, `OtplessBM` compiles
(there is no link edge), and at runtime `responds(to:)` returns false, one `os_log` line
is written, and the transaction proceeds **without** device intelligence. No crash, no
exception, nothing in crash reporting.

**This has already happened in production.** The iOS SDK's own `CHANGELOG.md` records it:

> Fixed device intelligence integration: the previous
> `runDeviceIntelligenceWithParams:onComplete:` selector did not exist on
> `OTPlessIntelligence`; device intelligence never ran in 2.x releases.

An entire major version shipped with the fraud/risk signal silently dead.

Note also that the selector is derived from Swift **argument labels**: renaming the
`params:` label — a change no reviewer would call breaking — changes the selector.

`scripts/check-reflection-contract.sh` is the mechanical guard, and it runs in `make gate`
and in CI. **If it fails, do not edit the script to make it pass.** Either restore the
name, or coordinate the change with the iOS SDK in the same release cycle (hub `CLAUDE.md`
change-flow rules 2 and 3) and update the script's expectations in that same PR.

## What it publishes

| | |
|---|---|
| CocoaPod | `OTPlessIntelligence` (`OTPlessIntelligence.podspec`, currently `1.2.0`) |
| SPM product | `OTPlessIntelligence` (`Package.swift`) |
| Platform | iOS 13+ (the IdentityFraud APIs it wraps require iOS 15; entry points are `@available(iOS 15.0, *)`) |
| Bundled binary | `Frameworks/IdentityFraud.xcframework` (vendored, iOS-only) |
| Entry point | `OTPlessIntelligence.shared` — an `@objc final class` |
| Dependency | `OtplessEventIO ~> 1.0` (see the note below) |
| What it does | Device intelligence for risk scoring and fraud detection, built on the IdentityFraud framework |

## Who consumes it, and how

| Consumer | How | Notes |
|---|---|---|
| `otpless-headless-iOS-sdk` (`OtplessBM`) | **Runtime reflection only** — no pod/SPM dependency declared | Merchants install `OTPlessIntelligence` themselves (`pod 'OTPlessIntelligence', '~> 1.3'` per the iOS SDK CHANGELOG) and call `initialize(appId:)` from their app; `OtplessBM` then finds it by `NSClassFromString` |

Two consequences of that arrangement:

- Because there is no dependency edge, **no version bump commit exists anywhere** to act
  as a review point. Merchants resolve this pod through their own range constraint.
- Because the integration is entirely reflective, the compiler protects nothing. The
  reflection-contract check is the only enforcement.

This library's own dependency on `OtplessEventIO` is `'~> 1.0'` — a range — so any `1.x`
release of that library also flows into merchant builds here with no review in between.

## Build & test

Requires Xcode with an iOS Simulator SDK.

```bash
make gate             # THE gate — run this before every merge
make reflection-check # the reflection contract on its own
make hygiene-check    # OTPLESS_DEBUG guard + resolved-version report
make build            # xcodebuild for a generic iOS Simulator destination
make api-dump         # regenerate api/public-surface.txt after an INTENTIONAL change
```

`make gate` is the single canonical definition of "verified" in this repo. It runs:

1. `scripts/check-release-hygiene.sh` — fails if `OTPLESS_DEBUG` is enabled in
   `Package.swift`, and reports the versions consumers resolve.
2. `scripts/check-reflection-contract.sh` — the check described above.
3. `scripts/check-public-surface.sh` — builds for the iOS Simulator and diffs the
   compiled module's public symbol graph against `api/public-surface.txt`.

**There is no test step, because there is no test target.** `Package.swift` declares only
the `IdentityFraud` binary target and the `OTPlessIntelligence` library target. A green
gate here means "it builds and the surface is unchanged" — it does **not** mean tests
pass, because none exist. Adding a test target is separate, worthwhile work.

**`swift build` cannot be used in this repo.** The package declares iOS as its only
platform and depends on `IdentityFraud.xcframework`, which has no macOS slice — a host
build is impossible by construction. Everything goes through `xcodebuild` against an iOS
Simulator destination.

## The public-surface golden

`api/public-surface.txt` is produced by `xcrun swift-symbolgraph-extract` over the
**compiled module**, one sorted line per public symbol
(`<access> <kind> <dotted path> :: <declaration>`). It contains no USRs, file paths or
source locations, so it is stable across machines and toolchain patch releases.

Critically, the declarations include the `@objc(...)` attributes, so **the golden covers
the Objective-C selectors** as well as the Swift surface. Objective-C and bridged callers
resolve those by name at runtime, so a changed selector fails at call time, not build
time.

**Never hand-edit the golden.** If a surface change is intentional:

1. Grep the iOS SDK for the symbol and, for `@objc` members, for the selector string.
2. Record it in `CHANGELOG.md`.
3. `make api-dump`, and include the golden diff in the PR.

## Working rules

- **`OTPLESS_DEBUG` must stay commented out.** `Package.swift` carries the warning in the
  repo's own words: enabling it makes every SPM consumer — and therefore every merchant
  app shipping the OTPLESS iOS SDK — inherit verbose request/response logging. That is a
  privacy problem, not just noise. `scripts/check-release-hygiene.sh` now enforces what
  the comment could only request.
- **Worktree-driven development.** The primary checkout belongs to the human. Every
  independent task gets its own worktree:
  `git worktree add /tmp/otpless-ios-intelligence-<task> <branch>` — work, commit and push
  from there, then `git worktree remove` it.
- Never push to `main`; everything goes through a PR that passes the gate.
- The Android counterpart `otpless-intelligence-sdk` has the **same** silent-degradation
  hazard, via `Class.forName` instead of `NSClassFromString`. Per the hub's change-flow
  rule 2 (Android ↔ iOS parity), a change to the intelligence entry point is a parity
  event on both platforms.
