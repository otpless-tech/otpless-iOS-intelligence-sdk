# OTPless Intelligence SDK — iOS Integration Guide

## Overview

OTPless Intelligence SDK collects real-time device risk signals and sends them to the OTPless platform for fraud analysis. It detects jailbreak, VPN, app tampering, GPS spoofing, screen mirroring, cloned apps, and more.

**Internal flow:**

```
initialize(appId)
    └── Fetch credentials from OTPless platform API
    └── Initialise IdentityFraud engine with those credentials
    └── Bootstrap OtplessEventIO for telemetry + tracking IDs

fetchIntelligence(params:updateInfo:)
    └── IdentityFraud engine fingerprints the device
    └── Push raw signals to OTPless backend → receive dfrId
    └── Return complete raw backend response directly to your app

Using dfrId (server-side)
    └── Your backend calls the OTPless platform API with dfrId
    └── Receive full detailed intelligence report
```

---

## Table of Contents

- [Requirements](#requirements)
- [Installation](#installation)
  - [Swift Package Manager](#swift-package-manager)
  - [CocoaPods](#cocoapods)
- [Project Setup](#project-setup)
  - [Info.plist Permissions](#infoplist-permissions)
  - [Entitlements](#entitlements)
  - [Requesting Location Permission](#requesting-location-permission)
- [Integration](#integration)
  - [Step 1 — Import](#step-1--import)
  - [Step 2 — Initialize](#step-2--initialize)
  - [Step 3 — Fetch Intelligence](#step-3--fetch-intelligence)
  - [Step 4 — Get Detailed Intelligence (Server-side)](#step-4--get-detailed-intelligence-server-side)
- [API Reference](#api-reference)
- [Response Reference](#response-reference)
- [Error Reference](#error-reference)
- [SwiftUI Example](#swiftui-example)
- [Objective-C Integration](#objective-c-integration)
- [Troubleshooting](#troubleshooting)
- [Changelog](#changelog)

---

## Requirements

| Requirement | Value |
|---|---|
| iOS deployment target | 13.0+ |
| Runtime (initialize / fetchIntelligence) | iOS 15.0+ |
| Swift | 5.5 – 6.0 |
| Xcode | 14+ |

> If your deployment target is below iOS 15, wrap SDK calls in `if #available(iOS 15.0, *) { }`.

---

## Installation

### Swift Package Manager

**Via Xcode:**

1. **File → Add Package Dependencies…**
2. Enter the URL:
   ```
   https://github.com/otpless-tech/otpless-ios-intelligence-sdk
   ```
3. Set version rule to **Up to Next Major Version** from `1.2.0`
4. Select **OTPlessIntelligence** and add to your target

**Via Package.swift:**

```swift
dependencies: [
    .package(
        url: "https://github.com/otpless-tech/otpless-ios-intelligence-sdk",
        from: "1.2.0"
    )
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "OTPlessIntelligence", package: "otpless-ios-intelligence-sdk")
        ]
    )
]
```

---

### CocoaPods

```ruby
platform :ios, '13.0'

target 'YourApp' do
  use_frameworks!
  pod 'OTPlessIntelligence', '~> 1.2.0'
end
```

```bash
pod install
```

> Always open `.xcworkspace`, not `.xcodeproj` after CocoaPods install.

---

## Project Setup

### Info.plist Permissions

```xml
<!-- Enables GPS location and geo-spoofing detection -->
<key>NSLocationWhenInUseUsageDescription</key>
<string>Used to detect location spoofing and protect your account.</string>
```

**In Xcode:** Target → **Info** tab → `+` → `Privacy - Location When In Use Usage Description`

Permissions are best-effort — the SDK never crashes if one is missing. More permissions = better signal accuracy.

---

### Entitlements

**Access WiFi Information** — improves network identity signals:

1. Target → **Signing & Capabilities** → **+ Capability** → **Access WiFi Information**

**iCloud / CloudKit** — improves cross-device identity signals:

1. **Signing & Capabilities** → **+ Capability** → **iCloud** → enable **CloudKit**

---

### Requesting Location Permission

The SDK does not request location permission itself:

```swift
import CoreLocation
CLLocationManager().requestWhenInUseAuthorization()
```

---

## Integration

### Step 1 — Import

```swift
import OTPlessIntelligence
```

---

### Step 2 — Initialize

Call **once**, as early as possible — in `AppDelegate` or SwiftUI `@main init()`.

**UIKit:**

```swift
import UIKit
import OTPlessIntelligence

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        if #available(iOS 15.0, *) {
            OTPlessIntelligence.shared.initialize(appId: "YOUR_APP_ID") { success in
                print("OTPless Intelligence ready: \(success)")
            }
        }
        return true
    }
}
```

**SwiftUI:**

```swift
import SwiftUI
import OTPlessIntelligence

@main
struct MyApp: App {
    init() {
        if #available(iOS 15.0, *) {
            OTPlessIntelligence.shared.initialize(appId: "YOUR_APP_ID") { success in
                print("OTPless Intelligence ready: \(success)")
            }
        }
    }
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

**Response:**

```
true  → SDK ready, fetchIntelligence can be called
false → SDK failed to initialise (check [OTPless] console logs in debug builds)
```

> **Where is my App ID?** OTPless Dashboard → select your app → Settings → copy App ID.

---

### Step 3 — Fetch Intelligence

**Swift (recommended — async/await):**

```swift
if #available(iOS 15.0, *) {
    Task {
        do {
            let response = try await OTPlessIntelligence.shared.fetchIntelligence(
                params: ["state": stateToken, "rsId": rsId],
                updateInfo: UpdateInfo(userId: "user_123", userEventType: .LOGIN)
            )
            print("dfrId: \(response.dfrId)")

            // Send dfrId to your backend to get the full intelligence report
            // See Step 4 (server-side)
        } catch {
            self.handleError(error)
        }
    }
}
```

**Swift / ObjC (callback):**

The callback form is bridged to Objective-C, so `updateInfo` is a dictionary (not the typed `UpdateInfo` struct) and the completion is a flat `(Bool, String?, NSDictionary?, String?)`:

```swift
if #available(iOS 15.0, *) {
    OTPlessIntelligence.shared.fetchIntelligence(
        params: ["state": stateToken, "rsId": rsId],
        updateInfo: ["userId": "user_123", "userEventType": "LOGIN"]
    ) { success, dfrId, intelligenceResponse, errorMessage in
        DispatchQueue.main.async {
            if success, let dfrId {
                print("dfrId: \(dfrId)")
                // Send dfrId to your backend (Step 4)
            } else {
                self.handleError(errorMessage)
            }
        }
    }
}
```

Both `params` and `updateInfo` are optional — pass `nil` if you don't need them. `params` is a generic pass-through: every non-reserved key you supply is forwarded into the push body verbatim (matches the Android SDK). Reserved keys (managed by the SDK): `data`, `status`, `requestId`, `message`, plus the SDK-set `tsId`, `inId`, `platform`, `appId`.

`updateInfo` (dict form) accepts keys `userId`, `phoneNumber`, `merchantId`, `phoneInputType`, `otpInputType`, `userEventType`, `additionalInput`. Enum-typed fields expect raw-value strings matching the case names (`"MANUAL"`, `"COPY_PASTED"`, `"LOGIN"`, …). Unknown keys and invalid enum strings are silently dropped.

**Response — success:** `IntelligenceApiResponse`

```swift
public struct IntelligenceApiResponse {
    public let dfrId: String
    public let intelligenceResponse: [String: Any]?
}
```

```json
{
    "dfrId": "ce81f2fae92949938aef4ccd0e7836d9",
    "intelligenceResponse": null
}
```

> `intelligenceResponse` is `null` today. Once the backend starts populating it, it will appear in `response.intelligenceResponse` automatically — no SDK update needed.

**Response — failure:**

The async form throws `OTPlessIntelligenceError`; the callback form flattens it to `(success: false, dfrId: nil, intelligenceResponse: nil, errorMessage: String)`.

| Error case (async) | Callback `errorMessage` | When it occurs |
|---|---|---|
| `.notConfigured` | `"SDK not initialised"` | `initialize()` not called or returned `false` |
| `.intelligenceError(requestId:message:)` | server-provided message | Engine error, push failed, or `dfrId` missing after all retries |
| `.unknown` | `"Unknown intelligence error"` | Unexpected internal state |

**Retry logic** — both the engine call and the push use `BackoffTimer` with 500 ms base, exponential, max 4 attempts (matches Android Veritaserum SDK). Delays: 500 ms → 1 s → 2 s → 4 s → error.

> `fetchIntelligence` waits for the backend push to complete before calling your closure.  
> Completion is called on a background thread — use `DispatchQueue.main.async` before any UI update.

---

### Step 4 — Get Detailed Intelligence (Server-side)

After receiving `dfrId`, your **backend server** calls the OTPless platform to get the full detailed report.

> **Server-to-server call only** — never call this from the iOS app. It uses `CLIENT_ID` and `CLIENT_SECRET` which must be kept on your server.

```bash
curl --request POST \
  --url https://platform.otpless.app/client/v1/device-fingerprint \
  --header 'clientid: YOUR_CLIENT_ID' \
  --header 'clientsecret: YOUR_CLIENT_SECRET' \
  --header 'content-type: application/json' \
  --data '{
    "dfrId": "DFRID_FROM_SDK",
    "deviceType": "IOS"
  }'
```

| Field | Value |
|---|---|
| `clientid` header | Your OTPless Client ID |
| `clientsecret` header | Your OTPless Client Secret |
| `dfrId` | The value from `fetchIntelligence` response |
| `deviceType` | `"IOS"` for iOS apps |

**Flow:**

```
iOS App                    Your Backend Server        OTPless Platform
    │                              │                        │
    │── fetchIntelligence() ──────>│ (SDK handles)          │
    │<── { dfrId } ───────────────│                        │
    │                              │                        │
    │── send dfrId to server ─────>│                        │
    │                              │── POST /client/v1/device-fingerprint ──>│
    │                              │<── full intelligence report ────────────│
    │<── risk decision ───────────│                        │
```

---

## API Reference

### `initialize(appId:completion:)`

```swift
@available(iOS 15.0, *)
public func initialize(
    appId: String,
    completion: @escaping (Bool) -> Void
)
```

| Parameter | Required | Description |
|---|---|---|
| `appId` | Yes | Your OTPless App ID |
| `completion` | Yes | `true` = ready, `false` = failed. Called on a background thread. |

---

### `isInitialized`

```swift
public var isInitialized: Bool { get }
```

`true` once `initialize(appId:completion:)` has completed successfully. Equivalent to Android `OtplessDeviceIntelligence.isInit`.

---

### `fetchIntelligence(params:updateInfo:completion:)` — callback (ObjC-bridged)

```swift
@available(iOS 15.0, *)
@objc(fetchIntelligenceWithParams:updateInfo:completion:)
public func fetchIntelligence(
    params: [String: String]?,
    updateInfo: [String: Any]?,
    completion: @escaping (Bool, String?, NSDictionary?, String?) -> Void
    //                    success, dfrId, intelligenceResponse, errorMessage
)
```

### `fetchIntelligence(params:updateInfo:)` — async/await (Swift only)

```swift
@available(iOS 15.0, *)
public func fetchIntelligence(
    params: [String: String]? = nil,
    updateInfo: UpdateInfo? = nil
) async throws -> IntelligenceApiResponse
```

| Parameter | Description |
|---|---|
| `params` | Optional per-call map. Every non-reserved key is forwarded into the push body verbatim (matches Android). Typical keys: `"state"`, `"rsId"`. Reserved (SDK-managed): `data`, `status`, `requestId`, `message`, plus the SDK-set `tsId`, `inId`, `platform`, `appId`. Never persisted. |
| `updateInfo` | Optional per-call enrichment. Typed `UpdateInfo` on the async form; `[String: Any]` dictionary on the callback form (see Step 3 for the accepted keys). |
| `completion` | Called on a background thread. |

Retry behaviour: both the engine call and the push use `BackoffTimer` with 500 ms base, exponential, max 4 attempts (matches Android Veritaserum SDK).

---

### `UpdateInfo`

```swift
public struct UpdateInfo {
    public let userId: String?
    public let phoneNumber: String?
    public let merchantId: String?
    public let phoneInputType: PhoneInputType?
    public let otpInputType: OtpInputType?
    public let userEventType: UserEventType?
    public let additionalInput: [String: String]?
}

public enum PhoneInputType: String { case MANUAL, COPY_PASTED, GOOGLE_HINT }
public enum OtpInputType:   String { case MANUAL, COPY_PASTED, AUTO_FILLED }
public enum UserEventType:  String { case LOGIN, SIGNUP, TRANSACTION, OTHERS }
```

---

## Response Reference

### `fetchIntelligence` — Success

```swift
public struct IntelligenceApiResponse {
    public let dfrId: String
    public let intelligenceResponse: [String: Any]?
}
```

`intelligenceResponse` mirrors the raw backend response payload.

**Current:**
```json
{
    "dfrId": "ce81f2fae92949938aef4ccd0e7836d9",
    "intelligenceResponse": null
}
```

**Future (once backend populates `intelligenceResponse`):**
```json
{
    "dfrId": "ce81f2fae92949938aef4ccd0e7836d9",
    "intelligenceResponse": {
        "requestId": "...",
        "deviceId": "...",
        "newDevice": true,
        "vpn": false,
        "proxy": false,
        "simulator": false,
        "jailbroken": false,
        "cloned": false,
        "geoSpoofed": false,
        "mirroredScreen": false,
        "hooking": false,
        "appTampering": false,
        "factoryReset": false,
        "factoryResetTime": 1694102352105,
        "ip": "152.59.198.179",
        "sessionRiskScore": 0.0,
        "deviceRiskScore": 0.0,
        "gpsLocation": { "latitude": 28.51, "longitude": 77.08, "altitude": 237.24 },
        "ipDetails": {
            "city": "New Delhi",
            "region": "National Capital Territory of Delhi",
            "country": "IN",
            "isp": "Reliance Jio Infocomm Limited",
            "asn": "55836",
            "fraudScore": 0.0
        },
        "deviceMeta": {
            "brand": "Apple",
            "model": "iPhone15,2",
            "iOSVersion": "17.4.1",
            "cpuType": "arm64",
            "screenResolution": "1179x2556",
            "totalRAM": "5368709120",
            "storageAvailable": "58363809792",
            "storageTotal": "113598214144"
        }
    }
}
```

---

## Error Reference

```swift
public enum OTPlessIntelligenceError: Error {
    case notConfigured
    case intelligenceError(requestId: String, message: String)
    case unknown
}
```

| Case | When | Action |
|---|---|---|
| `notConfigured` | `fetchIntelligence()` before `initialize()` succeeded | Call `initialize(appId:)` at launch, wait for `true` before calling `fetchIntelligence()` |
| `intelligenceError(requestId:message:)` | Engine error, push failed, `dfrId` missing after all retries | Log `requestId` for support. Degrade gracefully. |
| `unknown` | Unexpected state | Degrade gracefully |

> The callback form of `fetchIntelligence` collapses all failure cases into a single `errorMessage: String?` — the mapping is shown in Step 3.

**Always degrade gracefully:**

```swift
case .failure:
    proceedWithoutRiskCheck()
```

---

## SwiftUI Example

```swift
import SwiftUI
import OTPlessIntelligence

@main
struct MyApp: App {
    init() {
        if #available(iOS 15.0, *) {
            OTPlessIntelligence.shared.initialize(appId: "YOUR_APP_ID") { _ in }
        }
    }
    var body: some Scene {
        WindowGroup { LoginView() }
    }
}

@MainActor
class LoginViewModel: ObservableObject {
    @Published var isLoading = false

    func runDeviceCheck() {
        guard #available(iOS 15.0, *) else { return }
        isLoading = true

        Task {
            defer { isLoading = false }
            do {
                let response = try await OTPlessIntelligence.shared.fetchIntelligence()
                print("dfrId: \(response.dfrId)")
                // send dfrId to your backend
            } catch {
                print("Intelligence error: \(error)")
                // degrade gracefully
            }
        }
    }
}

struct LoginView: View {
    @StateObject private var vm = LoginViewModel()
    var body: some View {
        Group {
            if vm.isLoading { ProgressView("Checking device…") }
            else { LoginFormView() }
        }
        .onAppear { vm.runDeviceCheck() }
    }
}
```

---

## Objective-C Integration

`initialize` and the callback form of `fetchIntelligence` are bridged directly — no Swift shim required.

**Initialize:**

```objc
#import <OTPlessIntelligence/OTPlessIntelligence-Swift.h>

if (@available(iOS 15.0, *)) {
    [[OTPlessIntelligence shared] initializeWithAppId:@"YOUR_APP_ID"
                                            completion:^(BOOL success) {
        NSLog(@"[OTPless] ready: %@", success ? @"YES" : @"NO");
    }];
}
```

**Fetch intelligence:**

```objc
if (@available(iOS 15.0, *)) {
    [[OTPlessIntelligence shared]
        fetchIntelligenceWithParams:@{@"state": stateToken, @"rsId": rsId}
                         updateInfo:@{@"userId": @"user_123",
                                      @"userEventType": @"LOGIN"}
                         completion:^(BOOL success,
                                      NSString * _Nullable dfrId,
                                      NSDictionary * _Nullable intelligenceResponse,
                                      NSString * _Nullable errorMessage) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) {
                NSLog(@"dfrId: %@", dfrId);
                // send dfrId to your backend (Step 4)
            } else {
                NSLog(@"Error: %@", errorMessage);
                // degrade gracefully
            }
        });
    }];
}
```

`updateInfo` keys mirror the Swift `UpdateInfo` fields: `userId`, `phoneNumber`, `merchantId`, `phoneInputType`, `otpInputType`, `userEventType`, `additionalInput`. Enum-typed fields expect raw-value strings (`@"MANUAL"`, `@"COPY_PASTED"`, `@"LOGIN"`, …); unknown keys and invalid enum strings are silently dropped. Pass `nil` for either dictionary if you don't need it.

---

## Troubleshooting

### `initialize` returns `false`

Check the Xcode console for `[OTPless]` logs (visible in debug builds only):

| Log | Cause | Fix |
|---|---|---|
| `Config API error — status: 404` | App ID not found | Verify App ID in OTPless dashboard |
| `Config API error — status: 401` | Invalid App ID | Check App ID is copied correctly |
| `Config request error — offline` | No internet | Check connectivity |
| `IdentityFraud SDK initialisation failed` | Credentials rejected | Contact OTPless support |

---

### `fetchIntelligence` returns `.notConfigured`

`initialize()` was called but `fetchIntelligence()` ran before it finished:

```swift
// ❌ Wrong
OTPlessIntelligence.shared.initialize(appId: "...") { _ in }
OTPlessIntelligence.shared.fetchIntelligence { _ in }

// ✅ Correct — initialize at launch, fetchIntelligence on a different screen
```

---

### `fetchIntelligence` returns error after retries

The push to `platform.otpless.app` failed all 3 attempts or `dfrId` was missing in every response. Check for `[OTPless][ERROR]` logs.

---

### GPS signals missing

```swift
CLLocationManager().requestWhenInUseAuthorization()
// then call fetchIntelligence after user responds
```

---

### Build error: `No such module 'OTPlessIntelligence'`

- **CocoaPods:** Open `.xcworkspace`. Run `pod install` again if needed.
- **SPM:** File → Packages → Resolve Package Versions.
- **Clean:** Product → Clean Build Folder (`⇧⌘K`).

---

### Completion called on background thread — UI crash

```swift
OTPlessIntelligence.shared.fetchIntelligence { result in
    DispatchQueue.main.async {
        self.updateUI(result)
    }
}
```

---

### Testing on Simulator

Always test on a **real device** before App Store submission — some signals are unavailable or mocked in Simulator.

---

## Changelog

### 1.2.0
- **Breaking:** `configure(appID:sessionContext:completion:)` renamed to `initialize(appId:completion:)`. `OTPlessSessionContext` removed entirely.
- **Breaking:** `fetchIntelligence(completion:)` signature changes — now `fetchIntelligence(params:updateInfo:completion:)`. The callback form is ObjC-bridged: `updateInfo` is `[String: Any]?` and completion is `(Bool, String?, NSDictionary?, String?)` (success, dfrId, intelligenceResponse, errorMessage). Swift callers wanting typed access should use the async form. Every non-reserved key in `params` is forwarded into the push body verbatim (matches Android). Typical keys: `"state"`, `"rsId"`.
- **Breaking:** `updateAuthSessionWithIntelligence(authMap:)` and `gettsID()` removed from the public surface.
- **Breaking:** `updateOptions(userId:phoneNumber:additionalAttributes:)` removed — pass per-call via `UpdateInfo` instead.
- **Breaking:** `state` is no longer persisted in Keychain or auto-fetched. Callers supply it via `params["state"]` at each call.
- Added `async`/`await` variant: `fetchIntelligence(params:updateInfo:) async throws -> IntelligenceApiResponse` — returns typed `IntelligenceApiResponse` and throws `OTPlessIntelligenceError`.
- Added `isInitialized: Bool` property.
- `tsId` / `inId` are now sourced from `OtplessEventIO.trackingIds` — single source of truth shared with other OTPless SDKs.
- Engine-side retry added (500 ms base, exponential, 4 max attempts) — matches Android Veritaserum SDK.
- Push retry schedule migrated to the same `BackoffTimer` (500 ms base, 4 attempts), replacing the previous fixed 3 s / 6 s schedule.
- Telemetry: every state transition is now emitted as an `afp_*` event via `OtplessEventIO`. Events: `afp_initialize_called`, `afp_get_intelligence_called`, `afp_get_intelligence_async_called`, `afp_request_intelligence`, `afp_request_intelligence_result`, `afp_config_cached`, `afp_awaiting_init`, `afp_fetch_intelligence_retry`, `afp_init_play_intelligence`, `afp_fetch_play_intelligence_result`, `afp_fetch_play_intelligence_error`, `afp_push_intelligence`, `afp_push_intelligence_retry`, `afp_push_intelligence_failed`.

### 1.1.0
- `configure()` only requires `appID` — credentials fetched automatically
- Added `OTPlessSessionContext` — pass `rsId`, `inId`, `tsId`, `state` at configure time
- `fetchIntelligence()` returns `Result<[String: Any], OTPlessIntelligenceError>` — raw backend response directly, no wrapper
- Backend push retries: 3 attempts with fixed delays (immediate → +3s → +6s)
- `dfrId` must be present in response — missing `dfrId` triggers retry
- `fetchIntelligence()` waits for backend push before calling completion
- Upgraded to IdentityFraud framework v1.1.2
- Intelligence push migrated to `platform.otpless.app/sdk/v1/device-fingerprint`
- `gaId` (IDFV), `platform: IOS`, `rsId` added to all push payloads
- SSL pinning enabled on IdentityFraud SDK initialisation
- `@_implementationOnly import IdentityFraud` — consumers cannot access IdentityFraud types
- All SDK logs are `#if DEBUG` only — zero output in production builds
- All internal state (`dfrID`, push methods, session management) is fully private

### 1.0.5
- Initial release
