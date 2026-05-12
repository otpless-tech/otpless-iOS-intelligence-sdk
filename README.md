# OTPless Intelligence SDK — iOS Integration Guide

## Overview

OTPless Intelligence SDK collects real-time device signals to detect fraud and security risks — jailbreak, VPN, app tampering, GPS spoofing, screen mirroring, cloned apps, and more. These signals are used to protect authentication flows and high-value transactions.

**How it works:**

```
Your App  ──configure(appID)──▶  OTPless Platform  ──credentials──▶  IdentityFraud Engine
                                                                              │
Your App  ◀──risk signals──  OTPless Platform  ◀──raw signals──  IdentityFraud Engine
```

1. Your app calls `configure(appID:)` — the SDK fetches credentials from OTPless
2. The IdentityFraud engine initialises with those credentials
3. Your app calls `fetchIntelligence()` — the engine fingerprints the device
4. Risk signals are returned to your app and also pushed to OTPless backend

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Installation](#installation)
  - [Swift Package Manager](#option-a--swift-package-manager-recommended)
  - [CocoaPods](#option-b--cocoapods)
- [Project Setup](#project-setup)
  - [Permissions](#1-permissions-infoplist)
  - [Entitlements](#2-entitlements)
- [SDK Integration](#sdk-integration)
  - [Step 1 — Import](#step-1--import)
  - [Step 2 — Configure](#step-2--configure)
  - [Step 3 — Update User Context](#step-3--update-user-context-optional)
  - [Step 4 — Fetch Intelligence](#step-4--fetch-intelligence)
  - [Step 5 — Handle Response](#step-5--handle-the-response)
  - [Step 6 — Link Auth Session](#step-6--link-auth-session-otpless-auth-users-only)
- [API Reference](#api-reference)
- [Response Reference](#response-reference)
- [Error Reference](#error-reference)
- [SwiftUI Integration](#swiftui-integration)
- [Objective-C Integration](#objective-c-integration)
- [Sequence Diagrams](#sequence-diagrams)
- [Troubleshooting](#troubleshooting)
- [Changelog](#changelog)

---

## Prerequisites

| Requirement | Details |
|---|---|
| Xcode | 14.0 or later |
| iOS deployment target | 13.0 or later (runtime features require iOS 15.0+) |
| Swift | 5.5 – 6.0 |
| OTPless account | Sign up at [otpless.com](https://otpless.com) |
| App ID | Found in the OTPless dashboard under your app's settings |

> **iOS 13 vs iOS 15:** The SDK _compiles_ on iOS 13+. The `configure()` and `fetchIntelligence()` methods are `@available(iOS 15.0, *)`. If your deployment target is below iOS 15, wrap these calls in `if #available(iOS 15.0, *) { }`.

---

## Installation

### Option A — Swift Package Manager (Recommended)

**Using Xcode:**

1. Open your project in Xcode
2. Go to **File → Add Package Dependencies…**
3. In the search bar paste:
   ```
   https://github.com/otpless-tech/otpless-ios-intelligence-sdk
   ```
4. Set the version rule to **Up to Next Major Version** from `1.1.0`
5. Click **Add Package**
6. In the **Choose Package Products** sheet, tick **OTPlessIntelligence** and select your app target
7. Click **Add Package**

**Using Package.swift (for library/framework targets):**

```swift
// Package.swift
let package = Package(
    ...
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
)
```

---

### Option B — CocoaPods

1. If you don't have a `Podfile` yet, run `pod init` in your project directory.

2. Add the pod to your `Podfile`:

```ruby
platform :ios, '13.0'

target 'YourApp' do
  use_frameworks!

  pod 'OTPlessIntelligence', '~> 1.1.0'
end
```

3. Install:

```bash
pod install
```

4. **Important:** From now on always open `YourApp.xcworkspace`, not `YourApp.xcodeproj`.

---

## Project Setup

### 1. Permissions (Info.plist)

Signals are collected on a best-effort basis. Any permission that is not granted is silently skipped — the SDK will not crash or ask for permissions itself. The more permissions are available, the higher the signal accuracy.

Open your `Info.plist` and add:

```xml
<!-- GPS location — enables gpsLocation and geoSpoofed signals -->
<key>NSLocationWhenInUseUsageDescription</key>
<string>Used to detect location spoofing and protect your account security.</string>
```

**In Xcode UI:**
- Select your target → **Info** tab → hover over any row → click **+**
- Add key: `Privacy - Location When In Use Usage Description`
- Value: Your description string

> You must request location permission from the user in code before calling `fetchIntelligence()` for the GPS signals to be populated. See [Requesting Location Permission](#requesting-location-permission).

---

### 2. Entitlements

**Access WiFi Information** — enables network identity signals.

1. Select your target → **Signing & Capabilities** tab
2. Click **+ Capability**
3. Search for and add **Access WiFi Information**

This adds the following to your `.entitlements` file automatically:
```xml
<key>com.apple.developer.networking.wifi-info</key>
<true/>
```

**iCloud / CloudKit** — improves cross-device identity signal accuracy.

1. **Signing & Capabilities** → **+ Capability** → **iCloud**
2. Under iCloud, tick **CloudKit**

---

### Requesting Location Permission

The SDK does not request location permission on its own. If you want GPS signals, request permission before calling `fetchIntelligence()`:

```swift
import CoreLocation

class LocationHelper: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    func requestPermission() {
        manager.delegate = self
        manager.requestWhenInUseAuthorization()
    }
}
```

Or with SwiftUI:

```swift
import CoreLocation

struct ContentView: View {
    @StateObject private var locationManager = LocationManager()

    var body: some View {
        Text("Hello")
            .onAppear {
                locationManager.requestPermission()
            }
    }
}

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    override init() {
        super.init()
        manager.delegate = self
    }
    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }
}
```

---

## SDK Integration

### Step 1 — Import

Add this import at the top of every file that uses the SDK:

```swift
import OTPlessIntelligence
```

---

### Step 2 — Configure

Call `configure(appID:completion:)` **once**, as early as possible — in `AppDelegate` or your SwiftUI `@main` struct's `init()`.

Only your `appID` is required. The SDK fetches its own credentials from the OTPless platform automatically.

**UIKit — AppDelegate**

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
                if success {
                    print("OTPless Intelligence SDK ready")
                } else {
                    print("OTPless Intelligence SDK failed to initialise — check console for [OTPless] logs")
                }
            }
        }

        return true
    }
}
```

**SwiftUI — App Entry Point**

```swift
import SwiftUI
import OTPlessIntelligence

@main
struct MyApp: App {

    init() {
        if #available(iOS 15.0, *) {
            OTPlessIntelligence.shared.configure(appID: "YOUR_APP_ID") { success in
                print("OTPless Intelligence SDK ready: \(success)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

**What happens during configure:**

```
configure(appID: "YOUR_APP_ID")
    │
    ├─ Generates session tracking ID (tsId)
    ├─ Restores installation ID (inId) from UserDefaults
    ├─ Restores state token from Keychain (if previously saved)
    │
    └─ GET platform.otpless.app/sdk/v1/device-fingerprint/config
           header: appId = YOUR_APP_ID
           query:  packageName = your.bundle.id, platform = IOS
           ↓
           { intelligenceClientId, secret }
           ↓
       IdentitySDK.initAsync(clientId, secret)  →  fingerprint.otpless.com
           ↓
       completion(true / false)
```

> **Where is my App ID?**  
> Log into the [OTPless Dashboard](https://otpless.com/dashboard) → select your app → copy the App ID from the Settings page.

---

### Step 3 — Update User Context (Optional)

Call `updateOptions()` to attach user-specific information to the next `fetchIntelligence()` call. This improves fraud detection accuracy.

**Call this before `fetchIntelligence()`**, especially at key events like login, signup, or checkout.

```swift
if #available(iOS 15.0, *) {
    OTPlessIntelligence.shared.updateOptions(
        userId: "user_123",              // your internal user/account ID
        phoneNumber: "+919876543210",    // E.164 format
        additionalAttributes: [
            "eventType": "LOGIN",        // custom key-value pairs
            "signupMethod": "OTP"
        ]
    )
}
```

All three parameters are optional — pass only what you have:

```swift
// Only userId, nothing else
OTPlessIntelligence.shared.updateOptions(userId: "user_123")

// Only phone number
OTPlessIntelligence.shared.updateOptions(phoneNumber: "+919876543210")

// Only custom attributes
OTPlessIntelligence.shared.updateOptions(
    additionalAttributes: ["screen": "checkout", "amount": "5000"]
)
```

> **Note:** Options reset after each `fetchIntelligence()` call. If you need them for the next call too, set them again.

---

### Step 4 — Fetch Intelligence

Call `fetchIntelligence()` at any point where you need a risk assessment.

**Recommended call sites:**
- Login screen — before showing the OTP input
- Transaction screen — before processing payment
- Signup screen — before account creation
- Any screen that handles sensitive data

```swift
if #available(iOS 15.0, *) {
    OTPlessIntelligence.shared.fetchIntelligence { result in
        // Completion is called on a background thread.
        // Dispatch to main if you update UI here.
        DispatchQueue.main.async {
            switch result {
            case .success(let data):
                self.handleIntelligenceResponse(data.response)
            case .failure(let error):
                self.handleIntelligenceError(error)
            }
        }
    }
}
```

**What happens during fetchIntelligence:**

```
fetchIntelligence()
    │
    ├─ Guard: sdkInitialized == true (else returns .notConfigured error)
    │
    ├─ IdentitySDK.getIntelligence()  →  fingerprint.otpless.com
    │       Collects: jailbreak, VPN, GPS, IP, tampering, hooking,
    │                 screen mirror, clone, factory reset, device meta…
    │
    ├─ On success:
    │    ├─ POST platform.otpless.app/sdk/v1/device-fingerprint
    │    │       header: appId
    │    │       body:   { tsId, inId, appId, gaId, platform, state?, data }
    │    │       ← { dfrId }  (stored for auth session linking)
    │    │
    │    └─ completion(.success(OTPlessIntelligenceResult))
    │
    └─ On error:
         ├─ POST platform.otpless.app/sdk/v1/device-fingerprint  (error payload)
         └─ completion(.failure(OTPlessIntelligenceError))
```

---

### Step 5 — Handle the Response

```swift
func handleIntelligenceResponse(_ r: OTPlessIntelligenceResponse) {

    // ── Identifiers ──────────────────────────────────────────────────
    print("requestId : \(r.requestId)")   // unique ID for this call
    print("deviceId  : \(r.deviceId)")   // persistent device identifier
    print("ip        : \(r.ip)")          // current public IP

    // ── Risk flags ───────────────────────────────────────────────────
    print("simulator    : \(r.simulator)")     // running in Xcode Simulator
    print("jailbroken   : \(r.jailbroken)")    // device is jailbroken
    print("vpn          : \(r.vpn)")           // VPN active
    print("proxy        : \(r.proxy)")         // HTTP proxy active
    print("geoSpoofed   : \(r.geoSpoofed)")   // GPS being faked
    print("appTampering : \(r.appTampering)")  // app binary modified
    print("hooking      : \(r.hooking)")       // Frida / Substrate detected
    print("mirroredScreen: \(r.mirroredScreen)") // screen recording/mirroring
    print("cloned       : \(r.cloned)")        // cloned app instance
    print("newDevice    : \(r.newDevice)")     // first time device seen
    print("factoryReset : \(r.factoryReset)")  // suspicious factory reset
    print("factoryResetTime: \(r.factoryResetTime)") // epoch seconds

    // ── Server-side rule decision ─────────────────────────────────────
    // Only present when rules are configured on the OTPless dashboard.
    if let rule = r.ruleAction {
        print("rule.action      : \(rule.action ?? "")")
        print("rule.name        : \(rule.name ?? "")")
        print("rule.description : \(rule.ruleDescription ?? "")")
        print("rule.message     : \(rule.message ?? "")")

        switch rule.action {
        case "BLOCK":
            showBlockedMessage(rule.message ?? "Access denied.")
            return
        case "CHALLENGE":
            triggerOTPChallenge()
            return
        default:
            break
        }
    }

    // ── GPS location ─────────────────────────────────────────────────
    if let gps = r.gpsLocation {
        print("latitude  : \(gps.latitude ?? 0)")
        print("longitude : \(gps.longitude ?? 0)")
        print("altitude  : \(gps.altitude ?? 0)")
    }

    // ── IP intelligence ───────────────────────────────────────────────
    if let ip = r.ipDetails {
        print("city       : \(ip.city ?? "")")
        print("region     : \(ip.region ?? "")")
        print("country    : \(ip.country ?? "")")
        print("isp        : \(ip.isp ?? "")")
        print("asn        : \(ip.asn ?? "")")
        print("fraudScore : \(ip.fraudScore ?? 0)")  // 0 = clean, 100 = high risk
    }

    // ── Device metadata ───────────────────────────────────────────────
    if let meta = r.deviceMeta {
        print("model      : \(meta.model ?? "")")
        print("iOSVersion : \(meta.iOSVersion ?? "")")
        print("totalRAM   : \(meta.totalRAM ?? "")")
        print("storage    : \(meta.storageAvailable ?? "") / \(meta.storageTotal ?? "")")
    }

    // ── Your risk logic ───────────────────────────────────────────────
    let isHighRisk = r.jailbroken || r.appTampering || r.hooking || r.cloned
    if isHighRisk {
        // Block the action, show warning, or step up authentication
        presentSecurityChallenge()
        return
    }

    if r.vpn || r.proxy {
        // Log for analytics — may or may not block depending on your policy
        logSecurityEvent("vpn_or_proxy_detected", deviceId: r.deviceId)
    }

    // All clear — proceed
    proceedNormally()
}

func handleIntelligenceError(_ error: OTPlessIntelligenceError) {
    switch error {
    case .notConfigured:
        // configure() was not called or failed
        // This should not happen in production — fix by calling configure() at launch
        print("[OTPless] SDK not configured")

    case .intelligenceError(let requestId, let message):
        // The engine or server returned an error
        // Log requestId for debugging — share with OTPless support if needed
        print("[OTPless] Error [\(requestId)]: \(message)")
        // Degrade gracefully — allow the user to proceed
        proceedNormally()

    case .unknown:
        print("[OTPless] Unknown error")
        proceedNormally()
    }
}
```

---

### Step 6 — Link Auth Session (OTPless Auth Users Only)

If your app also uses the **OTPless Auth SDK**, call this after a successful authentication. It links the device fingerprint record (`dfrId`) to the auth session on the backend, enabling end-to-end fraud correlation.

```swift
// Call this inside your OTPless auth success callback
OTPlessIntelligence.shared.updateAuthSessionWithIntelligence(authMap: [
    "asId": authSessionId,   // Auth Session ID from OTPless auth response
    "token": authToken       // Token from OTPless auth response
])
```

> This is a no-op if `fetchIntelligence()` has not been successfully called in the current session. Always call `fetchIntelligence()` first.

---

## API Reference

### `OTPlessIntelligence.shared`

The singleton used for all SDK operations.

---

#### `configure(appID:completion:)`

```swift
@available(iOS 15.0, *)
public func configure(
    appID: String,
    completion: @escaping (Bool) -> Void
)
```

Initialises the SDK. Must be called **once before any other method**.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `appID` | `String` | Yes | Your OTPless App ID from the dashboard |
| `completion` | `(Bool) -> Void` | Yes | Called on any thread. `true` = ready, `false` = failed |

**Notes:**
- `completion` is called on an internal background thread. Dispatch to `DispatchQueue.main` before touching UI.
- If `appID` is empty, `completion(false)` is called immediately.
- Console logs prefixed `[OTPless]` show detailed progress and error reasons.

---

#### `updateOptions(userId:phoneNumber:additionalAttributes:)`

```swift
@available(iOS 15.0, *)
public func updateOptions(
    userId: String? = nil,
    phoneNumber: String? = nil,
    additionalAttributes: [String: String]? = nil
)
```

Enriches the next intelligence call with user context. All parameters are optional.

| Parameter | Type | Description |
|---|---|---|
| `userId` | `String?` | Your internal user or account ID |
| `phoneNumber` | `String?` | User's phone number (E.164 format, e.g. `+919876543210`) |
| `additionalAttributes` | `[String: String]?` | Any custom key-value pairs |

---

#### `fetchIntelligence(completion:)`

```swift
@available(iOS 15.0, *)
public func fetchIntelligence(
    completion: @escaping (Result<OTPlessIntelligenceResult, OTPlessIntelligenceError>) -> Void
)
```

Runs the device intelligence assessment.

| Parameter | Type | Description |
|---|---|---|
| `completion` | `(Result<OTPlessIntelligenceResult, OTPlessIntelligenceError>) -> Void` | Called on any thread |

**Notes:**
- Returns `.failure(.notConfigured)` immediately if `configure()` has not succeeded.
- Automatically pushes raw signals to the OTPless backend (with retry — up to 5 attempts, exponential backoff starting at 100ms).
- `completion` is called on an internal thread. Use `DispatchQueue.main.async` before any UI update.

---

#### `updateAuthSessionWithIntelligence(authMap:)`

```swift
public func updateAuthSessionWithIntelligence(authMap: [String: String])
```

Links the device fingerprint to an OTPless auth session.

| Key | Description |
|---|---|
| `"asId"` | Auth Session ID from OTPless auth response |
| `"token"` | Token from OTPless auth response |

---

#### `gettsID()`

```swift
@objc public func gettsID() -> String
```

Returns the current session tracking ID (`tsId`). Useful for correlating your own logs with OTPless backend records.

---

## Response Reference

### `OTPlessIntelligenceResult`

```swift
public struct OTPlessIntelligenceResult {
    public let response: OTPlessIntelligenceResponse
}
```

Wrapper returned from `fetchIntelligence()`. Access the intelligence data via `.response`.

---

### `OTPlessIntelligenceResponse`

| Property | Type | Description |
|---|---|---|
| `requestId` | `String` | Unique ID for this intelligence call. Use for debugging and support. |
| `deviceId` | `String` | Persistent unique identifier for the device. Stable across app sessions. |
| `ip` | `String` | Current public IP address of the device. |
| `simulator` | `Bool` | `true` when running inside Xcode Simulator. |
| `jailbroken` | `Bool` | `true` when the device has been jailbroken (root access). |
| `vpn` | `Bool` | `true` when a VPN is currently active. |
| `geoSpoofed` | `Bool` | `true` when GPS location appears to be mocked or faked. |
| `appTampering` | `Bool` | `true` when the app binary has been modified from the original. |
| `hooking` | `Bool` | `true` when runtime hooking (Frida, Substrate) is detected. |
| `proxy` | `Bool` | `true` when an HTTP/S proxy is configured on the device. |
| `mirroredScreen` | `Bool` | `true` when the device screen is being recorded or mirrored externally. |
| `cloned` | `Bool` | `true` when this is a cloned or repackaged instance of the app. |
| `newDevice` | `Bool` | `true` when this device has never been seen by OTPless before. |
| `factoryReset` | `Bool` | `true` when a suspicious factory reset has been recently performed. |
| `factoryResetTime` | `Int` | Unix epoch (seconds) of the last detected factory reset. `0` if never. |
| `gpsLocation` | `GPSLocation?` | GPS coordinates. `nil` if location permission not granted. |
| `ipDetails` | `IPDetails?` | Enriched IP intelligence — location, ISP, fraud score. |
| `deviceMeta` | `DeviceMeta?` | Hardware and OS information. |
| `ruleAction` | `OTPlessRuleAction?` | Server-side rule decision. `nil` if no rules are configured. |

---

### `GPSLocation`

```swift
public class GPSLocation: NSObject, Codable {
    public var latitude: NSNumber?   // decimal degrees
    public var longitude: NSNumber?  // decimal degrees
    public var altitude: NSNumber?   // metres
}
```

| Property | Type | Description |
|---|---|---|
| `latitude` | `NSNumber?` | Latitude in decimal degrees (e.g. `28.6139`) |
| `longitude` | `NSNumber?` | Longitude in decimal degrees (e.g. `77.2090`) |
| `altitude` | `NSNumber?` | Altitude in metres above sea level |

---

### `IPDetails`

```swift
public class IPDetails: NSObject, Codable {
    public var city: String?
    public var region: String?
    public var country: String?
    public var isp: String?
    public var asn: String?
    public var fraudScore: NSNumber?
    public var latitude: NSNumber?
    public var longitude: NSNumber?
}
```

| Property | Type | Description |
|---|---|---|
| `city` | `String?` | City resolved from the IP (e.g. `"Mumbai"`) |
| `region` | `String?` | State or region (e.g. `"Maharashtra"`) |
| `country` | `String?` | ISO 3166-1 alpha-2 country code (e.g. `"IN"`) |
| `isp` | `String?` | Internet Service Provider name |
| `asn` | `String?` | Autonomous System Number |
| `fraudScore` | `NSNumber?` | IP fraud score: `0` = clean, `100` = very high risk |
| `latitude` | `NSNumber?` | Approximate latitude based on IP geolocation |
| `longitude` | `NSNumber?` | Approximate longitude based on IP geolocation |

---

### `DeviceMeta`

```swift
public class DeviceMeta: NSObject, Codable {
    public var brand: String?
    public var model: String?
    public var product: String?
    public var cpuType: String?
    public var iOSVersion: String?
    public var screenResolution: String?
    public var totalRAM: String?
    public var storageAvailable: String?
    public var storageTotal: String?
}
```

| Property | Type | Description |
|---|---|---|
| `brand` | `String?` | Manufacturer (always `"Apple"` on iOS) |
| `model` | `String?` | Device model identifier (e.g. `"iPhone15,2"`) |
| `product` | `String?` | Product name |
| `cpuType` | `String?` | CPU architecture (e.g. `"arm64"`) |
| `iOSVersion` | `String?` | iOS version string (e.g. `"17.4.1"`) |
| `screenResolution` | `String?` | Resolution in pixels (e.g. `"1179x2556"`) |
| `totalRAM` | `String?` | Total physical RAM in bytes as a string |
| `storageAvailable` | `String?` | Free storage in bytes as a string |
| `storageTotal` | `String?` | Total storage capacity in bytes as a string |

---

### `OTPlessRuleAction`

Returned when the OTPless backend evaluates configured rules against the device signals.

```swift
public class OTPlessRuleAction: NSObject, Codable {
    public let action: String?
    public let name: String?
    public let ruleDescription: String?
    public let message: String?
}
```

| Property | Type | Description |
|---|---|---|
| `action` | `String?` | Action the SDK should take: `"BLOCK"`, `"CHALLENGE"`, `"ALLOW"`, or a custom value |
| `name` | `String?` | Name of the rule that fired (as configured in the dashboard) |
| `ruleDescription` | `String?` | Technical description of why the rule fired |
| `message` | `String?` | User-facing message you can display in your UI |

> `ruleAction` is `nil` when no rules are configured, or when none of the configured rules matched the device. Always check for `nil` before accessing properties.

---

## Error Reference

### `OTPlessIntelligenceError`

```swift
public enum OTPlessIntelligenceError: Error {
    case notConfigured
    case intelligenceError(requestId: String, message: String)
    case unknown
}
```

| Case | When it occurs | Recommended action |
|---|---|---|
| `notConfigured` | `fetchIntelligence()` was called before `configure()` completed successfully | Ensure `configure(appID:)` is called at app launch and `completion` returned `true` before calling `fetchIntelligence()` |
| `intelligenceError(requestId:message:)` | The fingerprinting engine or backend returned an error | Log `requestId` for debugging. Degrade gracefully — allow the user to proceed |
| `unknown` | Unexpected internal state | Degrade gracefully. If persistent, contact support |

**Pattern: always degrade gracefully**

```swift
case .failure(let error):
    // Log the error
    logError(error)

    // Do NOT block the user for an intelligence failure
    // The intelligence call failing should not prevent a legitimate user from continuing
    proceedWithoutRiskCheck()
```

---

## SwiftUI Integration

A complete SwiftUI example:

```swift
import SwiftUI
import OTPlessIntelligence

// ── App Entry Point ───────────────────────────────────────────────────────────

@main
struct MyApp: App {
    init() {
        if #available(iOS 15.0, *) {
            OTPlessIntelligence.shared.configure(appID: "YOUR_APP_ID") { success in
                print("OTPless ready: \(success)")
            }
        }
    }
    var body: some Scene {
        WindowGroup { LoginView() }
    }
}

// ── ViewModel ─────────────────────────────────────────────────────────────────

@MainActor
class LoginViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isBlocked = false
    @Published var blockMessage = ""

    func runDeviceCheck() {
        guard #available(iOS 15.0, *) else { return }
        isLoading = true

        OTPlessIntelligence.shared.updateOptions(
            additionalAttributes: ["screen": "login"]
        )

        OTPlessIntelligence.shared.fetchIntelligence { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false

                switch result {
                case .success(let data):
                    self.handleResponse(data.response)
                case .failure(let error):
                    // Intelligence failure — degrade gracefully
                    print("Intelligence error: \(error)")
                }
            }
        }
    }

    private func handleResponse(_ r: OTPlessIntelligenceResponse) {
        // Server rule takes priority
        if let rule = r.ruleAction, rule.action == "BLOCK" {
            isBlocked = true
            blockMessage = rule.message ?? "Access denied."
            return
        }

        // Local high-risk check
        if r.jailbroken || r.appTampering || r.hooking {
            isBlocked = true
            blockMessage = "This device does not meet our security requirements."
            return
        }
    }
}

// ── View ──────────────────────────────────────────────────────────────────────

struct LoginView: View {
    @StateObject private var vm = LoginViewModel()

    var body: some View {
        ZStack {
            if vm.isLoading {
                ProgressView("Checking device security…")
            } else if vm.isBlocked {
                BlockedView(message: vm.blockMessage)
            } else {
                LoginFormView()
            }
        }
        .onAppear {
            vm.runDeviceCheck()
        }
    }
}

struct BlockedView: View {
    let message: String
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 60))
                .foregroundColor(.red)
            Text(message)
                .multilineTextAlignment(.center)
                .padding()
        }
    }
}

struct LoginFormView: View {
    var body: some View {
        Text("Login Form")
    }
}
```

---

## Objective-C Integration

All public types are `@objcMembers NSObject` subclasses — fully usable from Objective-C.

**Import:**

```objc
// In your .m / .mm file
#import <OTPlessIntelligence/OTPlessIntelligence-Swift.h>

// Or if using CocoaPods with module
@import OTPlessIntelligence;
```

**Configure:**

```objc
// AppDelegate.m
- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    if (@available(iOS 15.0, *)) {
        [[OTPlessIntelligence shared] configureWithAppID:@"YOUR_APP_ID"
                                              completion:^(BOOL success) {
            NSLog(@"[OTPless] SDK ready: %@", success ? @"YES" : @"NO");
        }];
    }
    return YES;
}
```

**Update options:**

```objc
if (@available(iOS 15.0, *)) {
    [[OTPlessIntelligence shared]
        updateOptionsWithUserId:@"user_123"
        phoneNumber:@"+919876543210"
        additionalAttributes:@{@"eventType": @"LOGIN"}];
}
```

**Fetch intelligence:**

> Swift `Result` types are not directly bridged to Objective-C. Create a thin Swift wrapper:

```swift
// IntelligenceBridge.swift — add this to your project
import OTPlessIntelligence

@objc class IntelligenceBridge: NSObject {

    @available(iOS 15.0, *)
    @objc static func fetchIntelligence(
        success: @escaping (OTPlessIntelligenceResponse) -> Void,
        failure: @escaping (String) -> Void
    ) {
        OTPlessIntelligence.shared.fetchIntelligence { result in
            switch result {
            case .success(let data):
                success(data.response)
            case .failure(let error):
                switch error {
                case .intelligenceError(_, let message): failure(message)
                default: failure("Intelligence error")
                }
            }
        }
    }
}
```

Use from Objective-C:

```objc
if (@available(iOS 15.0, *)) {
    [IntelligenceBridge fetchIntelligenceWithSuccess:^(OTPlessIntelligenceResponse *response) {
        NSLog(@"jailbroken: %d", response.jailbroken);
        NSLog(@"vpn: %d", response.vpn);
        NSLog(@"deviceId: %@", response.deviceId);

        if (response.jailbroken || response.appTampering) {
            [self showSecurityWarning];
        }
    } failure:^(NSString *message) {
        NSLog(@"Intelligence error: %@", message);
    }];
}
```

**Link auth session:**

```objc
[[OTPlessIntelligence shared]
    updateAuthSessionWithIntelligence:@{
        @"asId": authSessionId,
        @"token": authToken
    }];
```

---

## Sequence Diagrams

### Normal Flow

```
App                  OTPlessIntelligence      platform.otpless.app    fingerprint.otpless.com
 │                          │                          │                        │
 │── configure(appID) ─────>│                          │                        │
 │                          │── GET /device-fingerprint/config ───────────────> │ (not here)
 │                          │<──────── { clientId, secret } ────────────────────│
 │                          │                                                   │
 │                          │── IdentitySDK.initAsync(clientId, secret) ───────>│
 │                          │<────────────── completion(true) ───────────────────│
 │<── completion(true) ─────│                          │                        │
 │                          │                          │                        │
 │── fetchIntelligence() ──>│                          │                        │
 │                          │── getIntelligence() ─────────────────────────────>│
 │                          │<── onSuccess(IntelligenceResponse) ────────────────│
 │                          │── POST /device-fingerprint ─────────────────────> │ (not here)
 │                          │<──────── { dfrId } ──────│                        │
 │<── .success(result) ─────│                          │                        │
```

### With OTPless Auth SDK

```
App                  OTPlessIntelligence         OtplessBM (Auth SDK)
 │                          │                          │
 │── configure(appID) ─────>│                          │
 │                          │  (shares tsId with auth SDK via runtime bridge)
 │                          │                          │
 │── fetchIntelligence() ──>│                          │
 │<── .success(result) ─────│                          │
 │                          │                          │
 │── [user completes auth] ─────────────────────────── │
 │<── authSessionId, token ──────────────────────────── │
 │                          │                          │
 │── updateAuthSession(asId, token) ──>│               │
 │                          │── POST /device-fingerprint (with dfrId + asId + token)
 │                          │   (links device fingerprint ↔ auth session on backend)
```

---

## Troubleshooting

### `completion(false)` from `configure()`

Check the Xcode console for `[OTPless]` logs. They will tell you exactly what failed.

**Check the logs for one of these patterns:**

| Log message | Cause | Fix |
|---|---|---|
| `Config API error — status: 404` | App ID not found or iOS not enabled | Log into OTPless dashboard and verify the app ID and enable iOS intelligence |
| `Config API error — status: 401` | App ID is invalid or expired | Check that your App ID is correct |
| `Config request error — The Internet connection appears to be offline` | No network | Check device connectivity |
| `IdentityFraud SDK initialisation failed` | Sign3 credentials rejected | Contact OTPless support with the `requestId` |

---

### `fetchIntelligence()` returns `.notConfigured`

`configure()` has not completed successfully before `fetchIntelligence()` was called.

**Common cause:** Calling `fetchIntelligence()` immediately after `configure()` without waiting for the completion callback.

```swift
// ❌ Wrong — fetchIntelligence() runs before configure() finishes
OTPlessIntelligence.shared.configure(appID: "YOUR_APP_ID") { _ in }
OTPlessIntelligence.shared.fetchIntelligence { result in ... }

// ✅ Correct — wait for configure to complete
OTPlessIntelligence.shared.configure(appID: "YOUR_APP_ID") { success in
    guard success else { return }
    OTPlessIntelligence.shared.fetchIntelligence { result in ... }
}

// ✅ Also correct — configure once at launch, fetchIntelligence later on a different screen
// configure() is called in AppDelegate, fetchIntelligence() is called in LoginViewController
```

---

### GPS location is `nil` in the response

Location permission has not been granted by the user.

```swift
// Request permission before calling fetchIntelligence
import CoreLocation
CLLocationManager().requestWhenInUseAuthorization()
// Then call fetchIntelligence after the user has responded
```

---

### `ruleAction` is always `nil`

Rules are not configured for your app in the OTPless dashboard. `ruleAction` is only populated when the backend matches the device against a configured rule. This is expected if you haven't set up rules yet.

---

### Build error: `No such module 'IdentityFraud'`

- **CocoaPods:** Make sure you opened `.xcworkspace` not `.xcodeproj`. Run `pod install` again if needed.
- **SPM:** Go to **File → Packages → Resolve Package Versions** in Xcode.
- **Clean build:** **Product → Clean Build Folder** (`⇧⌘K`), then build again.

---

### Signals show `false` / inaccurate on Simulator

The Xcode Simulator is a controlled environment. Several signals behave differently:

| Signal | Simulator behaviour |
|---|---|
| `simulator` | Always `true` |
| `jailbroken` | Always `false` (Simulator cannot be jailbroken) |
| `gpsLocation` | Returns Simulator's simulated location |
| `ip` | Returns your Mac's IP |
| Hardware signals (RAM, storage) | Returns Simulator host values |

Always validate on a **real physical device** before submitting to the App Store.

---

### `completion` is called on a background thread — UI crashes

The `configure()` and `fetchIntelligence()` completions are called on an internal background thread. Wrap any UI update in `DispatchQueue.main.async`:

```swift
OTPlessIntelligence.shared.fetchIntelligence { result in
    DispatchQueue.main.async {
        // Safe to update UI here
        self.updateUI(result)
    }
}
```

---

## Changelog

### 1.1.0
- `configure()` now only requires `appID` — credentials fetched automatically from `platform.otpless.app`
- Upgraded to IdentityFraud framework v1.1.2 (Swift 6.2, Xcode 26 SDK, min iOS 13)
- Added `ruleAction: OTPlessRuleAction?` to `OTPlessIntelligenceResponse`
- Intelligence data push migrated to `platform.otpless.app/sdk/v1/device-fingerprint`
- `gaId` (vendor identifier / IDFV) and `platform: IOS` added to all push payloads
- SSL pinning enabled on IdentityFraud SDK initialisation
- Detailed `[OTPless]` console logging added throughout the initialisation flow

### 1.0.5
- Initial public release
