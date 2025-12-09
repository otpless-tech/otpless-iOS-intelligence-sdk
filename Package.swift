// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "otpless-ios-intelligence-sdk",
    platforms: [
        // IdentityFraud APIs are available from iOS 15,
        // but you can keep the minimum lower if you want to compile on older,
        // as long as you gate calls with @available checks.
        .iOS(.v15)
    ],
    products: [
        // This is what apps / other SDKs will import:
        // import OTPlessIntelligence
        .library(
            name: "OTPlessIntelligence",
            targets: ["OTPlessIntelligence"]
        )
    ],
    targets: [
        // 1) Binary xcframework from IdentityFraud
        .binaryTarget(
            name: "IdentityFraud",
            path: "Frameworks/IdentityFraud.xcframework"
        ),

        // 2) Your Swift wrapper target that depends on IdentityFraud
        .target(
            name: "OTPlessIntelligence",
            dependencies: ["IdentityFraud"],
            path: "Sources/otpless-ios-intelligence-sdk"
        )
    ]
)
