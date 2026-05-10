# OTPless Intelligence SDK — iOS

Device intelligence and fraud-detection SDK for iOS. Collect real-time risk signals from a device — jailbreak, VPN, app tampering, GPS spoofing, screen mirroring, cloned apps, and more — to secure authentication and transaction flows.

---

## Table of Contents

1. [Requirements](#requirements)
2. [Installation](#installation)
   - [Swift Package Manager](#swift-package-manager)
   - [CocoaPods](#cocoapods)
3. [Project Setup](#project-setup)
   - [Info.plist Permissions](#infoplist-permissions)
   - [Entitlements](#entitlements)
4. [Integration Steps](#integration-steps)
   - [Step 1 — Import the SDK](#step-1--import-the-sdk)
   - [Step 2 — Configure at App Launch](#step-2--configure-at-app-launch)
   - [Step 3 — Update User Context (Optional)](#step-3--update-user-context-optional)
   - [Step 4 — Fetch Intelligence](#step-4--fetch-intelligence)
   - [Step 5 — Handle the Response](#step-5--handle-the-response)
   - [Step 6 — Link Auth Session (OTPless Auth users)](#step-6--link-auth-session-otpless-auth-users)
5. [API Reference](#api-reference)
6. [Response Reference](#response-reference)
7. [Error Reference](#error-reference)
8. [Objective-C Usage](#objective-c-usage)
9. [Complete Example](#complete-example)
10. [Troubleshooting](#troubleshooting)
11. [Changelog](#changelog)

---

## Requirements

| Requirement | Value |
|---|---|
| iOS deployment target | 13.0+ |
| Runtime features available from | iOS 15.0+ |
| Swift | 5.5 – 6.0 |
| Xcode | 14+ |

> The SDK compiles on iOS 13+. The `configure()` and `fetchIntelligence()` calls are annotated `@available(iOS 15.0, *)` — wrap them in an availability check or ensure your minimum deployment target is iOS 15.

---

## Installation

### Swift Package Manager

**Option A — Xcode UI**

1. Open your project in Xcode
2. Go to **File → Add Package Dependencies…**
3. Enter the repository URL:
   ```
   https://github.com/otpless-tech/otpless-ios-intelligence-sdk
   ```
4. Select version **1.1.0** (Up to Next Major)
5. Add **OTPlessIntelligence** to your app target

**Option B — Package.swift**

```swift
// Package.swift
dependencies: [
    .package(
        url: "https://github.com/otpless-tech/otpless-ios-intelligence-sdk",
        from: "1.1.0"
    )
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "OTPlessIntelligence", package: "otpless-ios-intelligence-sdk")
        ]
    )
]
```

---

### CocoaPods

1. Add the pod to your `Podfile`:

```ruby
platform :ios, '13.0'

target 'YourApp' do
  use_frameworks!
  pod 'OTPlessIntelligence', '~> 1.1.0'
end
```

2. Run:

```bash
pod install
```

3. Open the `.xcworkspace` file (not `.xcodeproj`) from now on.

---

## Project Setup

### Info.plist Permissions

Signals are collected on a best-effort basis. Permissions that are not granted are silently skipped — the SDK will not crash. The more permissions are available, the higher the signal accuracy.

Add the following keys to your `Info.plist`:

```xml
<!-- Required for GPS location and geo-spoofing detection -->
<key>NSLocationWhenInUseUsageDescription</key>
<string>Your location is used to detect suspicious activity and protect your account.</string>

<!-- Recommended — improves location accuracy -->
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Your location is used to detect suspicious activity and protect your account.</string>
```

**In Xcode:**
- Select your project → target → **Info** tab
- Click **+** on any row
- Add `Privacy - Location When In Use Usage Description` with a description string

---

### Entitlements

**Access WiFi Information** — allows the SDK to collect network identity signals.

1. In Xcode select your target → **Signing & Capabilities**
2. Click **+ Capability**
3. Add **Access WiFi Information**

This adds `com.apple.developer.networking.wifi-info` to your `.entitlements` file.

**iCloud** — improves cross-device identity signals.

1. In **Signing & Capabilities** click **+ Capability**
2. Add **iCloud**
3. Enable **CloudKit**

---

## Integration Steps

### Step 1 — Import the SDK

In every file where you use the SDK:

```swift
import OTPlessIntelligence
```

---

### Step 2 — Configure at App Launch

Call `configure` **once**, as early as possible — ideally in `AppDelegate` or your app's entry point.

Only your `appID` is needed. The SDK fetches credentials automatically from the OTPless platform.

**AppDelegate (UIKit)**

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
                    print("[OTPless] Intelligence SDK ready")
                } else {
                    print("[OTPless] Intelligence SDK failed to initialise")
                }
            }
        }

        return true
    }
}
```

**SwiftUI App**

```swift
import SwiftUI
import OTPlessIntelligence

@main
struct MyApp: App {

    init() {
        if #available(iOS 15.0, *) {
            OTPlessIntelligence.shared.configure(appID: "YOUR_APP_ID") { success in
                print("[OTPless] SDK ready: \(success)")
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

> **Where do I find my `appID`?**  
> Log in to the [OTPless Dashboard](https://otpless.com/dashboard), navigate to your app, and copy the App ID shown on the settings page.

---

### Step 3 — Update User Context (Optional)

Call `updateOptions` to enrich the intelligence data with user-specific signals. This is optional but improves fraud detection accuracy.

Call it **before** `fetchIntelligence`, especially at key moments like login, signup, or transaction initiation.

```swift
if #available(iOS 15.0, *) {
    OTPlessIntelligence.shared.updateOptions(
        userId: "user_123",
        phoneNumber: "+919876543210",       // E.164 format
        additionalAttributes: [
            "eventType": "LOGIN",           // LOGIN | SIGNUP | TRANSACTION
            "signupMethod": "OTP"
        ]
    )
}
```

All parameters are optional — pass only what you have:

```swift
// Just the userId
OTPlessIntelligence.shared.updateOptions(userId: currentUser.id)

// Just additional attributes
OTPlessIntelligence.shared.updateOptions(
    additionalAttributes: ["screen": "checkout"]
)
```

> **Note:** Options are reset after each `getIntelligence` call inside the SDK. If you need them for the next call, set them again before calling `fetchIntelligence`.

---

### Step 4 — Fetch Intelligence

Call `fetchIntelligence` at any point where you need a risk assessment — login screen, before a transaction, on a sensitive screen.

```swift
if #available(iOS 15.0, *) {
    OTPlessIntelligence.shared.fetchIntelligence { result in
        switch result {
        case .success(let data):
            // Use data.response
            self.handleIntelligenceResponse(data.response)

        case .failure(let error):
            self.handleIntelligenceError(error)
        }
    }
}
```

---

### Step 5 — Handle the Response

```swift
func handleIntelligenceResponse(_ response: OTPlessIntelligenceResponse) {

    // ── Core risk flags ──────────────────────────────────────────────
    print("Device ID   : \(response.deviceId)")
    print("Request ID  : \(response.requestId)")
    print("IP Address  : \(response.ip)")

    print("Jailbroken  : \(response.jailbroken)")
    print("Simulator   : \(response.simulator)")
    print("VPN active  : \(response.vpn)")
    print("Proxy       : \(response.proxy)")
    print("Geo spoofed : \(response.geoSpoofed)")
    print("App tampered: \(response.appTampering)")
    print("Hooking     : \(response.hooking)")
    print("Mirrored    : \(response.mirroredScreen)")
    print("Cloned app  : \(response.cloned)")
    print("New device  : \(response.newDevice)")
    print("Fact. reset : \(response.factoryReset)")

    // ── High-risk check ──────────────────────────────────────────────
    let isHighRisk = response.jailbroken
        || response.appTampering
        || response.hooking
        || response.cloned

    if isHighRisk {
        // Block the action or present a challenge
        showSecurityChallenge()
        return
    }

    // ── Server-side rule decision ────────────────────────────────────
    // Present only when rules are configured on the OTPless dashboard.
    if let rule = response.ruleAction {
        print("Rule action : \(rule.action ?? "")")
        print("Rule name   : \(rule.name ?? "")")
        print("Message     : \(rule.message ?? "")")

        switch rule.action {
        case "BLOCK":
            blockUser(reason: rule.message)
        case "CHALLENGE":
            presentOTPChallenge()
        default:
            proceedNormally()
        }
        return
    }

    // ── GPS location ─────────────────────────────────────────────────
    if let gps = response.gpsLocation {
        print("GPS: \(gps.latitude ?? 0), \(gps.longitude ?? 0)")
    }

    // ── IP details ───────────────────────────────────────────────────
    if let ip = response.ipDetails {
        print("City        : \(ip.city ?? "")")
        print("Country     : \(ip.country ?? "")")
        print("ISP         : \(ip.isp ?? "")")
        print("IP fraud score: \(ip.fraudScore ?? 0)")
    }

    // ── Device metadata ──────────────────────────────────────────────
    if let meta = response.deviceMeta {
        print("Model  : \(meta.model ?? "")")
        print("iOS    : \(meta.iOSVersion ?? "")")
        print("RAM    : \(meta.totalRAM ?? "")")
    }

    proceedNormally()
}

func handleIntelligenceError(_ error: OTPlessIntelligenceError) {
    switch error {
    case .notConfigured:
        // configure() was never called or failed
        print("[OTPless] SDK not configured — call configure(appID:) first")

    case .intelligenceError(let requestId, let message):
        // The SDK or server returned an error
        print("[OTPless] Error [\(requestId)]: \(message)")

    case .unknown:
        print("[OTPless] Unknown error")
    }
}
```

---

### Step 6 — Link Auth Session (OTPless Auth users)

If you also use the **OTPless Auth SDK** (`OtplessBM`), call this after a successful authentication. It links the device fingerprint record to the auth event on the backend, enabling end-to-end fraud correlation.

```swift
// Call this after your OTPless auth flow completes successfully
OTPlessIntelligence.shared.updateAuthSessionWithIntelligence(authMap: [
    "asId": authSessionId,   // Auth Session ID from OTPless auth response
    "token": authToken       // Token from OTPless auth response
])
```

> This call is a no-op if `fetchIntelligence` hasn't been called yet in the current session. Always call `fetchIntelligence` before `updateAuthSessionWithIntelligence`.

---

## API Reference

### `OTPlessIntelligence.shared`

The singleton entry point for all SDK operations.

---

#### `configure(appID:completion:)`

```swift
@available(iOS 15.0, *)
public func configure(
    appID: String,
    completion: @escaping (Bool) -> Void
)
```

Initialises the SDK. Must be called **once** before any other method.

Internally this:
1. Generates a session tracking ID and restores any persisted state
2. Fetches `intelligenceClientId` + `secret` from `platform.otpless.app` using your `appID`
3. Initialises the underlying IdentityFraud engine with those credentials

| Parameter | Type | Description |
|---|---|---|
| `appID` | `String` | Your OTPless App ID from the dashboard |
| `completion` | `(Bool) -> Void` | Called on any thread. `true` = ready, `false` = failed |

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

Enriches the next `fetchIntelligence` call with user-specific context. All parameters are optional.

| Parameter | Type | Description |
|---|---|---|
| `userId` | `String?` | Your internal user / account ID |
| `phoneNumber` | `String?` | User's phone number in E.164 format |
| `additionalAttributes` | `[String: String]?` | Any custom key-value pairs |

---

#### `fetchIntelligence(completion:)`

```swift
@available(iOS 15.0, *)
public func fetchIntelligence(
    completion: @escaping (Result<OTPlessIntelligenceResult, OTPlessIntelligenceError>) -> Void
)
```

Runs the device intelligence assessment and returns a result. Also automatically pushes the raw signals to the OTPless backend.

| Parameter | Type | Description |
|---|---|---|
| `completion` | `(Result<OTPlessIntelligenceResult, OTPlessIntelligenceError>) -> Void` | Called on any thread with success or failure |

---

#### `updateAuthSessionWithIntelligence(authMap:)`

```swift
public func updateAuthSessionWithIntelligence(authMap: [String: String])
```

Links the device fingerprint to an OTPless auth session. Only fires if `fetchIntelligence` has already succeeded in this session.

| Key | Description |
|---|---|
| `"asId"` | Auth Session ID from OTPless auth SDK |
| `"token"` | Token from OTPless auth SDK |

---

#### `gettsID()`

```swift
@objc public func gettsID() -> String
```

Returns the current session tracking ID (`tsId`). Useful for correlating logs.

---

## Response Reference

### `OTPlessIntelligenceResponse`

| Property | Type | Description |
|---|---|---|
| `requestId` | `String` | Unique ID for this specific intelligence call |
| `deviceId` | `String` | Persistent unique identifier for the device |
| `ip` | `String` | Current public IP address of the device |
| `simulator` | `Bool` | `true` if running inside Xcode Simulator |
| `jailbroken` | `Bool` | `true` if the device has been jailbroken |
| `vpn` | `Bool` | `true` if a VPN is currently active |
| `geoSpoofed` | `Bool` | `true` if GPS location appears to be faked |
| `appTampering` | `Bool` | `true` if the app binary has been modified |
| `hooking` | `Bool` | `true` if runtime hooking (Frida / Substrate) is detected |
| `proxy` | `Bool` | `true` if an HTTP/S proxy is in use |
| `mirroredScreen` | `Bool` | `true` if the screen is being recorded or mirrored |
| `cloned` | `Bool` | `true` if this is a cloned instance of the app |
| `newDevice` | `Bool` | `true` if this device has never been seen before |
| `factoryReset` | `Bool` | `true` if a suspicious factory reset was detected |
| `factoryResetTime` | `Int` | Unix epoch (seconds) of the last factory reset |
| `gpsLocation` | `GPSLocation?` | Current GPS coordinates (if location permission is granted) |
| `ipDetails` | `IPDetails?` | Enriched IP intelligence |
| `deviceMeta` | `DeviceMeta?` | Hardware and OS metadata |
| `ruleAction` | `OTPlessRuleAction?` | Server-side rule decision (only present if rules are configured in the dashboard) |

---

### `GPSLocation`

| Property | Type | Description |
|---|---|---|
| `latitude` | `NSNumber?` | Latitude in decimal degrees |
| `longitude` | `NSNumber?` | Longitude in decimal degrees |
| `altitude` | `NSNumber?` | Altitude in metres |

---

### `IPDetails`

| Property | Type | Description |
|---|---|---|
| `city` | `String?` | City resolved from the IP |
| `region` | `String?` | Region / state |
| `country` | `String?` | ISO 3166-1 country code (e.g. `"IN"`) |
| `isp` | `String?` | Internet Service Provider name |
| `asn` | `String?` | Autonomous System Number |
| `latitude` | `NSNumber?` | IP-based latitude |
| `longitude` | `NSNumber?` | IP-based longitude |
| `fraudScore` | `NSNumber?` | IP fraud score (0 = clean, 100 = high risk) |

---

### `DeviceMeta`

| Property | Type | Description |
|---|---|---|
| `brand` | `String?` | Device manufacturer (e.g. `"Apple"`) |
| `model` | `String?` | Device model (e.g. `"iPhone15,2"`) |
| `product` | `String?` | Product name |
| `cpuType` | `String?` | CPU architecture (e.g. `"arm64"`) |
| `iOSVersion` | `String?` | iOS version string (e.g. `"17.4.1"`) |
| `screenResolution` | `String?` | Screen resolution (e.g. `"1179x2556"`) |
| `totalRAM` | `String?` | Total RAM in bytes as a string |
| `storageAvailable` | `String?` | Available storage in bytes as a string |
| `storageTotal` | `String?` | Total storage in bytes as a string |

---

### `OTPlessRuleAction`

Returned when the OTPless backend matches the device against a configured rule.

| Property | Type | Description |
|---|---|---|
| `action` | `String?` | Action to take: `"BLOCK"`, `"CHALLENGE"`, `"ALLOW"`, etc. |
| `name` | `String?` | Name of the rule that fired |
| `ruleDescription` | `String?` | Why the rule fired |
| `message` | `String?` | User-facing message to display |

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

| Case | When it occurs | What to do |
|---|---|---|
| `notConfigured` | `fetchIntelligence` called before `configure` succeeded | Ensure `configure(appID:)` is called at app launch and `completion` returned `true` |
| `intelligenceError(requestId:message:)` | SDK or server returned an error | Log `requestId` for debugging; retry or degrade gracefully |
| `unknown` | Unexpected internal state | Retry; contact support if persistent |

---

## Objective-C Usage

All public types are `@objcMembers` and `NSObject` subclasses — fully accessible from Objective-C.

**Configure:**

```objc
#import <OTPlessIntelligence/OTPlessIntelligence-Swift.h>

// In AppDelegate
if (@available(iOS 15.0, *)) {
    [[OTPlessIntelligence shared] configureWithAppID:@"YOUR_APP_ID"
                                          completion:^(BOOL success) {
        NSLog(@"Intelligence SDK ready: %@", success ? @"YES" : @"NO");
    }];
}
```

**Update options:**

```objc
if (@available(iOS 15.0, *)) {
    [[OTPlessIntelligence shared] updateOptionsWithUserId:@"user_123"
                                             phoneNumber:@"+919876543210"
                                    additionalAttributes:@{@"eventType": @"LOGIN"}];
}
```

**Fetch intelligence:**

```objc
if (@available(iOS 15.0, *)) {
    [[OTPlessIntelligence shared] fetchIntelligence:^(id result) {
        // result is a Swift Result type — use the Swift wrapper or bridge via a helper
    }];
}
```

> For Objective-C projects, consider writing a thin Swift wrapper around `fetchIntelligence` that calls the completion with a plain `NSDictionary` or `NSError` — Swift `Result` types are less ergonomic in ObjC.

---

## Complete Example

A minimal but complete Swift example showing all steps together:

```swift
import UIKit
import OTPlessIntelligence

// ── AppDelegate ──────────────────────────────────────────────────────────────

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        if #available(iOS 15.0, *) {
            OTPlessIntelligence.shared.configure(appID: "YOUR_APP_ID") { success in
                print("[OTPless] SDK initialised: \(success)")
            }
        }
        return true
    }
}

// ── LoginViewController ──────────────────────────────────────────────────────

class LoginViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        runDeviceCheck()
    }

    private func runDeviceCheck() {
        guard #available(iOS 15.0, *) else { return }

        // Enrich with user context (optional)
        OTPlessIntelligence.shared.updateOptions(
            userId: nil,                         // not known before login
            additionalAttributes: ["screen": "login"]
        )

        OTPlessIntelligence.shared.fetchIntelligence { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let data):
                    self?.handleResponse(data.response)
                case .failure(let error):
                    self?.handleError(error)
                }
            }
        }
    }

    private func handleResponse(_ r: OTPlessIntelligenceResponse) {
        // Server-side rule — takes priority if present
        if let rule = r.ruleAction, rule.action == "BLOCK" {
            showAlert(title: "Access Denied", message: rule.message ?? "Request blocked.")
            return
        }

        // Local risk check
        if r.jailbroken || r.appTampering || r.hooking {
            showAlert(title: "Security Warning", message: "This device does not meet security requirements.")
            return
        }

        if r.vpn {
            // Log for analytics but allow
            print("[OTPless] VPN detected — deviceId: \(r.deviceId)")
        }

        // Proceed to login
        showLoginForm()
    }

    private func handleError(_ error: OTPlessIntelligenceError) {
        // Non-fatal — degrade gracefully
        switch error {
        case .notConfigured:
            print("[OTPless] SDK not configured")
        case .intelligenceError(let id, let msg):
            print("[OTPless] [\(id)] \(msg)")
        case .unknown:
            print("[OTPless] Unknown error")
        }
        showLoginForm()   // allow login even if intelligence fails
    }

    private func showLoginForm() { /* show your login UI */ }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// ── Post-auth (if using OTPless Auth SDK) ────────────────────────────────────

extension LoginViewController {

    func onAuthSuccess(authSessionId: String, authToken: String) {
        OTPlessIntelligence.shared.updateAuthSessionWithIntelligence(authMap: [
            "asId": authSessionId,
            "token": authToken
        ])
    }
}
```

---

## Troubleshooting

### `configure` completion returns `false`

- Check your `appID` — copy it directly from the OTPless dashboard
- Ensure the device/simulator has internet connectivity
- Check for SSL/firewall issues blocking `platform.otpless.app`
- Check the Xcode console for any `[OTPless]` or `URLError` messages

### `fetchIntelligence` returns `.notConfigured`

- `configure(appID:completion:)` must be called and the completion must return `true` before calling `fetchIntelligence`
- Both methods require `iOS 15.0+` at runtime — check availability

### No GPS location in the response

- The user has not granted location permission
- Request permission before calling `fetchIntelligence`:

```swift
import CoreLocation

let manager = CLLocationManager()
manager.requestWhenInUseAuthorization()
// Then call fetchIntelligence after the user responds
```

### `ruleAction` is always `nil`

- Rules are only returned if you have configured rules in the OTPless dashboard
- If no rules are configured, this field will always be `nil` — this is expected

### Build error: `IdentityFraud module not found`

- If using CocoaPods, ensure you opened the `.xcworkspace`, not `.xcodeproj`
- Run `pod install` again and clean the build folder (**Product → Clean Build Folder**)
- If using SPM, ensure the `OTPlessIntelligence` package resolved correctly (File → Packages → Resolve Package Versions)

### Simulator vs real device differences

- `simulator: true` will always be set when running on an iOS Simulator
- Some signals (GPS, cell carrier, certain hardware checks) are unavailable or return mock values in the Simulator
- Always test on a real device before submitting to the App Store

---

## Changelog

### 1.1.0
- `configure()` now only requires `appID` — credentials are fetched automatically
- Upgraded to IdentityFraud framework v1.1.2 (Swift 6.2, Xcode 26 SDK)
- Added `ruleAction` to `OTPlessIntelligenceResponse` — server-side rule decisions
- Intelligence push migrated to `platform.otpless.app/sdk/v1/device-fingerprint`
- `gaId` (vendor identifier / IDFV) and `platform: IOS` added to all push payloads
- SSL pinning enabled on IdentityFraud SDK initialisation

### 1.0.5
- Initial public release
