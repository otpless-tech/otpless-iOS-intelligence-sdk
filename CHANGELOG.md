# Changelog

`OtplessBM` reaches this library entirely by runtime reflection
(`NSClassFromString` + an `@objc` selector), so there is no dependency-bump commit
anywhere to act as a review point. Every merchant-visible change belongs here, in
particular:

- **any change to the reflection contract** asserted by
  `scripts/check-reflection-contract.sh` — always breaking, however small the edit
  looked, because the consumer resolves it by string at runtime and fails silently;
- **any change to the public surface recorded in `api/public-surface.txt`**, including
  `@objc` selector changes.

This file was introduced alongside the verification gate; releases made before it are not
reconstructed here. Consult the git history for anything below `1.2.0`.

## Unreleased

- Added a verification gate (`make gate`): a release-hygiene check that fails if
  `OTPLESS_DEBUG` is enabled in `Package.swift`,
  `scripts/check-reflection-contract.sh` (asserts the ObjC runtime class name, the
  `shared` accessor, and the `fetchIntelligenceWithParams:updateInfo:completion:`
  selector and its completion-block shape, all of which `OtplessBM` dispatches by
  string), and a committed public-API golden (`api/public-surface.txt`) extracted from
  the compiled module's symbol graph. Added CI
  (`.github/workflows/build-test.yml`).
- `CLAUDE.md` is no longer gitignored; it is now the committed constitution for this
  repo.

## 1.2.0

Current podspec version. See git history.
