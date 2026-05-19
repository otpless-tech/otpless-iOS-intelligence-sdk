# OTPless Intelligence SDK — iOS Integration Guide

## Overview

OTPless Intelligence SDK collects real-time device risk signals and sends them to the OTPless platform for fraud analysis. It detects jailbreak, VPN, app tampering, GPS spoofing, screen mirroring, cloned apps, and more.

**Internal flow:**

```
configure(appID)
    └── Fetch credentials from OTPless platform API
    └── Initialise IdentityFraud engine with those credentials

fetchIntelligence()
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
  - [Step 2 — Configure](#step-2--configure)
  - [Step 3 — Update User Context (Optional)](#step-3--update-user-context-optional)
  - [Step 4 — Fetch Intelligence](#step-4--fetch-intelligence)
  - [Step 5 — Get Detailed Intelligence (Server-side)](#step-5--get-detailed-intelligence-server-side)
  - [Step 6 — Link Auth Session (OTPless Auth Users)](#step-6--link-auth-session-otpless-auth-users-only)
- [API Reference](#api-reference)
- [OTPlessSessionContext Reference](#otplesssessioncontext-reference)
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
| Runtime (configure / fetchIntelligence) | iOS 15.0+ |
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
3. Set version rule to **Up to Next Major Version** from `1.1.0`
4. Select **OTPlessIntelligence** and add to your target

**Via Package.swift:**

```swift
dependencies: [
    .package(
        url: "https://github.com/otpless-tech/otpless-ios-intelligence-sdk",
        from: "1.1.0"
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
  pod 'OTPlessIntelligence', '~> 1.1.0'
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

### Step 2 — Configure

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
            OTPlessIntelligence.shared.configure(appID: "YOUR_APP_ID") { success in
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
            OTPlessIntelligence.shared.configure(appID: "YOUR_APP_ID") { success in
                print("OTPless Intelligence ready: \(success)")
            }
        }
    }
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

**With session context** — when you already have session IDs (e.g. from OTPless Auth SDK):

```swift
if #available(iOS 15.0, *) {
    let context = OTPlessSessionContext(
        rsId: "rs-abc123",
        inId: "86f0a8f0-...",
        tsId: authSDK.gettsID(),
        state: authSDK.getState()
    )
    OTPlessIntelligence.shared.configure(appID: "YOUR_APP_ID", sessionContext: context) { success in
        print("OTPless Intelligence ready: \(success)")
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

### Step 3 — Update User Context (Optional)

Call before `fetchIntelligence()` to improve fraud detection accuracy:

```swift
if #available(iOS 15.0, *) {
    OTPlessIntelligence.shared.updateOptions(
        userId: "user_123",
        phoneNumber: "+919876543210",
        additionalAttributes: ["eventType": "LOGIN"]
    )
}
```

All parameters are optional. Options reset after each `fetchIntelligence()` call.

---

### Step 4 — Fetch Intelligence

```swift
if #available(iOS 15.0, *) {
    OTPlessIntelligence.shared.fetchIntelligence { result in
        DispatchQueue.main.async {
            switch result {
            case .success(let response):
                // response is [String: Any] — complete raw backend JSON
                let dfrId = response["dfrId"] as? String
                print("dfrId: \(dfrId ?? "nil")")

                // Send dfrId to your backend to get the full intelligence report
                // See Step 5

            case .failure(let error):
                self.handleError(error)
            }
        }
    }
}
```

**Response — success:**

```json
{
    "dfrId": "ce81f2fae92949938aef4ccd0e7836d9",
    "intelligenceResponse": null
}
```

> `intelligenceResponse` is `null` today. Once the backend starts populating it, it will appear in the same dictionary automatically — no SDK update needed.

**Response — failure:**

| Error case | When it occurs |
|---|---|
| `.notConfigured` | `configure()` not called or returned `false` |
| `.intelligenceError(requestId:message:)` | Engine error, push failed, or `dfrId` missing after all 3 retries |
| `.unknown` | Unexpected internal state |

**Retry logic:**

| Attempt | Delay before next |
|---|---|
| 1 | 3 seconds |
| 2 | 6 seconds |
| 3 | Error returned if still failing |

> `fetchIntelligence` waits for the backend push to complete before calling your closure.  
> Completion is called on a background thread — use `DispatchQueue.main.async` before any UI update.

---

### Step 5 — Get Detailed Intelligence (Server-side)

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

### Step 6 — Link Auth Session (OTPless Auth Users Only)

If your app also uses the OTPless Auth SDK, call this after a successful authentication:

```swift
OTPlessIntelligence.shared.updateAuthSessionWithIntelligence(authMap: [
    "asId": authSessionId,
    "token": authToken
])
```

> No-op if `fetchIntelligence()` has not succeeded in the current session.

---

## API Reference

### `configure(appID:sessionContext:completion:)`

```swift
@available(iOS 15.0, *)
public func configure(
    appID: String,
    sessionContext: OTPlessSessionContext? = nil,
    completion: @escaping (Bool) -> Void
)
```

| Parameter | Required | Description |
|---|---|---|
| `appID` | Yes | Your OTPless App ID |
| `sessionContext` | No | Optional session IDs — pass `nil` to skip |
| `completion` | Yes | `true` = ready, `false` = failed. Called on a background thread. |

---

### `updateOptions(userId:phoneNumber:additionalAttributes:)`

```swift
@available(iOS 15.0, *)
public func updateOptions(
    userId: String? = nil,
    phoneNumber: String? = nil,
    additionalAttributes: [String: String]? = nil
)
```

All parameters optional. Enriches the next `fetchIntelligence()` call with user context.

---

### `fetchIntelligence(completion:)`

```swift
@available(iOS 15.0, *)
public func fetchIntelligence(
    completion: @escaping (Result<[String: Any], OTPlessIntelligenceError>) -> Void
)
```

Returns the complete raw backend response dictionary directly on success.

- Retries up to 3 times if push fails or `dfrId` is missing (immediate → +3s → +6s)
- Waits for the backend push to complete before calling your closure
- Completion called on a background thread

---

### `updateAuthSessionWithIntelligence(authMap:)`

```swift
public func updateAuthSessionWithIntelligence(authMap: [String: String])
```

| Key | Description |
|---|---|
| `"asId"` | Auth Session ID from OTPless auth response |
| `"token"` | Token from OTPless auth response |

---

### `gettsID()`

```swift
@objc public func gettsID() -> String
```

Returns the current tracking session ID. Use for log correlation.

---

## OTPlessSessionContext Reference

```swift
@objcMembers
public class OTPlessSessionContext: NSObject {
    public let rsId: String?    // request/session ID from upstream flow
    public let inId: String?    // installation ID
    public let tsId: String?    // tracking session ID
    public let state: String?   // server-issued state token
}
```

| ID | Provided | Not provided |
|---|---|---|
| `tsId` | Used as-is | Borrowed from OTPless Auth SDK if present, else generated |
| `inId` | Used as-is, saved to UserDefaults | Restored from UserDefaults, or generated |
| `state` | Used as-is, saved to Keychain | Restored from Keychain, or fetched lazily |
| `rsId` | Sent in every push body | Omitted from push body |

---

## Response Reference

### `fetchIntelligence` — Success

`[String: Any]` — the complete raw backend response.

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
| `notConfigured` | `fetchIntelligence()` before `configure()` succeeded | Call `configure(appID:)` at launch, wait for `true` before calling `fetchIntelligence()` |
| `intelligenceError(requestId:message:)` | Engine error, push failed, `dfrId` missing after 3 retries | Log `requestId` for support. Degrade gracefully. |
| `unknown` | Unexpected state | Degrade gracefully |

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
            OTPlessIntelligence.shared.configure(appID: "YOUR_APP_ID") { _ in }
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

        OTPlessIntelligence.shared.fetchIntelligence { [weak self] result in
            Task { @MainActor in
                self?.isLoading = false
                switch result {
                case .success(let response):
                    let dfrId = response["dfrId"] as? String
                    print("dfrId: \(dfrId ?? "nil")")
                    // send dfrId to your backend

                case .failure(let error):
                    print("Intelligence error: \(error)")
                    // degrade gracefully
                }
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

**Configure:**

```objc
#import <OTPlessIntelligence/OTPlessIntelligence-Swift.h>

if (@available(iOS 15.0, *)) {
    [[OTPlessIntelligence shared] configureWithAppID:@"YOUR_APP_ID"
                                      sessionContext:nil
                                          completion:^(BOOL success) {
        NSLog(@"[OTPless] ready: %@", success ? @"YES" : @"NO");
    }];
}
```

**Fetch intelligence** — use a Swift bridge since `Result<[String: Any], ...>` is not ObjC-friendly:

```swift
// IntelligenceBridge.swift — add to your project
import OTPlessIntelligence

@objc class IntelligenceBridge: NSObject {
    @available(iOS 15.0, *)
    @objc static func fetch(
        success: @escaping ([String: Any]) -> Void,
        failure: @escaping (String) -> Void
    ) {
        OTPlessIntelligence.shared.fetchIntelligence { result in
            switch result {
            case .success(let response):
                success(response)
            case .failure(let e):
                if case .intelligenceError(_, let msg) = e { failure(msg) }
                else { failure("Intelligence error") }
            }
        }
    }
}
```

```objc
if (@available(iOS 15.0, *)) {
    [IntelligenceBridge fetchWithSuccess:^(NSDictionary *response) {
        NSString *dfrId = response[@"dfrId"];
        NSLog(@"dfrId: %@", dfrId);
        // send dfrId to your backend
    } failure:^(NSString *message) {
        NSLog(@"Error: %@", message);
    }];
}
```

---

## Troubleshooting

### `configure` returns `false`

Check the Xcode console for `[OTPless]` logs (visible in debug builds only):

| Log | Cause | Fix |
|---|---|---|
| `Config API error — status: 404` | App ID not found | Verify App ID in OTPless dashboard |
| `Config API error — status: 401` | Invalid App ID | Check App ID is copied correctly |
| `Config request error — offline` | No internet | Check connectivity |
| `IdentityFraud SDK initialisation failed` | Credentials rejected | Contact OTPless support |

---

### `fetchIntelligence` returns `.notConfigured`

`configure()` was called but `fetchIntelligence()` ran before it finished:

```swift
// ❌ Wrong
OTPlessIntelligence.shared.configure(appID: "...") { _ in }
OTPlessIntelligence.shared.fetchIntelligence { _ in }

// ✅ Correct — configure at launch, fetchIntelligence on a different screen
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
