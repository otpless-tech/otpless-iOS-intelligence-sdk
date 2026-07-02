// swift-tools-version:5.9
import PackageDescription

// REMOVE the `swiftSettings: [.define("OTPLESS_DEBUG")]` line on the
// OTPlessIntelligence target before publishing any release tag / pushing
// to main / cutting a podspec bump — otherwise every SPM consumer will
// inherit the verbose request/response logging.
let package = Package(
    name: "otpless-ios-intelligence-sdk",
    platforms: [
        // IdentityFraud APIs are available from iOS 15,
        // but you can keep the minimum lower if you want to compile on older,
        // as long as you gate calls with @available checks.
        .iOS(.v13)
    ],
    products: [
        // This is what apps / other SDKs will import:
        // import OTPlessIntelligence
        .library(
            name: "OTPlessIntelligence",
            targets: ["OTPlessIntelligence"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/otpless-tech/otpless-event-io-ios",
            from: "1.0.0"
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
            dependencies: [
                "IdentityFraud",
                .product(name: "OtplessEventIO", package: "otpless-event-io-ios")
            ],
            path: "Sources/otpless-ios-intelligence-sdk"
//            ,swiftSettings: [.define("OTPLESS_DEBUG")]
        )
    ]
)
