import Foundation
@_implementationOnly import IdentityFraud
import OtplessEventIO

// MARK: - Public Error Type

public enum OTPlessIntelligenceError: Error {
    /// `initialize(appId:)` was never successfully called
    case notConfigured

    /// SDK returned an error
    case intelligenceError(requestId: String, message: String)

    /// Unexpected nil / inconsistent state
    case unknown
}

// MARK: - OTPlessIntelligence (Public Facade)

@objc public final class OTPlessIntelligence: NSObject, @unchecked Sendable {

    @objc public static let shared = OTPlessIntelligence()
    private(set) var merchantAppId = ""
    override init() {}

    // MARK: - Initialize

    /// Initialises the SDK.
    ///
    /// Fetches `intelligenceClientId` + `secret` from the OTPless platform API,
    /// initialises the IdentityFraud engine with those credentials, and bootstraps
    /// `OtplessEventIO` so tracking IDs and event telemetry are ready.
    ///
    /// Equivalent of Android `OtplessDeviceIntelligence.initialize(context, creds)`.
    @available(iOS 15.0, *)
    @objc(initializeWithAppId:completion:)
    public func initialize(
        appId: String,
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        guard !appId.isEmpty else {
            completion(false)
            return
        }
        merchantAppId = appId

        OtplessEventIO.shared.initialize(appId: appId)
        IntelligenceEvents.initializeCalled()
        OtplessEventIO.shared.pushDeviceEvent(
            sdkVersion: OTPlessIntelligence.sdkVersion,
            platform: "otpless-intelligence-sdk(ios)"
        )

        DeviceIntelligenceManager.shared.initialize(completion: completion)
    }

    /// Whether `initialize(appId:completion:)` has succeeded.
    /// Equivalent of Android `OtplessDeviceIntelligence.isInit`.
    @objc public var isInitialized: Bool {
        DeviceIntelligenceManager.shared.sdkInitialized
    }

    /// Hard-coded SDK version. Bump in lockstep with `OTPlessIntelligence.podspec`.
    internal static let sdkVersion = "1.2.0"

    // MARK: - Fetch Intelligence

    /// Fetches device intelligence signals and pushes them to OTPless.
    ///
    /// ObjC-visible callback form. Swift callers can also use the `async throws`
    /// variant below for richer error information.
    ///
    /// Equivalent of Android `OtplessDeviceIntelligence.getIntelligenceAsync(params:updateInfo:callback:)`.
    ///
    /// - Parameters:
    ///   - params: Optional per-call map. Every entry is forwarded into the push
    ///     payload verbatim, except for SDK-reserved keys (`data`, `status`,
    ///     `requestId`, `message`, plus SDK-set `tsId`, `inId`, `platform`, `appId`).
    ///     Typical keys: `"state"`, `"rsId"`. Values are never persisted across calls.
    ///   - updateInfo: Optional dictionary with keys `userId`, `phoneNumber`,
    ///     `merchantId`, `phoneInputType`, `otpInputType`, `userEventType`,
    ///     `additionalInput`. Enum-typed fields take raw-value strings matching
    ///     the case names on `PhoneInputType` / `OtpInputType` / `UserEventType`
    ///     (e.g. `"MANUAL"`, `"COPY_PASTED"`, `"LOGIN"`). Unknown keys and
    ///     invalid enum strings are silently dropped.
    ///   - completion: Called on a background thread with
    ///     `(success, dfrId, intelligenceResponse, errorMessage)`. On success
    ///     `intelligenceResponse` may still be nil if the server omitted it.
    ///     Dispatch to main before UI updates.
    @available(iOS 15.0, *)
    @objc(fetchIntelligenceWithParams:updateInfo:completion:)
    public func fetchIntelligence(
        params: [String: String]?,
        updateInfo: [String: Any]?,
        completion: @escaping @Sendable (Bool, String?, NSDictionary?, String?) -> Void
    ) {
        let typedInfo = UpdateInfo.from(dictionary: updateInfo)
        fetchIntelligenceInternal(params: params, updateInfo: typedInfo) { result in
            switch result {
            case .success(let response):
                completion(true, response.dfrId, response.intelligenceResponse.map { $0 as NSDictionary }, nil)
            case .failure(let error):
                let message: String
                switch error {
                case .notConfigured:
                    message = "SDK not initialised"
                case .intelligenceError(_, let msg):
                    message = msg
                case .unknown:
                    message = "Unknown intelligence error"
                }
                completion(false, nil, nil, message)
            }
        }
    }

    /// Async/await variant of `fetchIntelligence`.
    ///
    /// Equivalent of Android `OtplessDeviceIntelligence.getIntelligence(updateInfo:)` (suspend fun).
    @available(iOS 15.0, *)
    public func fetchIntelligence(
        params: [String: String]? = nil,
        updateInfo: UpdateInfo? = nil
    ) async throws -> IntelligenceApiResponse {
        IntelligenceEvents.getIntelligenceCalled()
        return try await withCheckedThrowingContinuation { continuation in
            fetchIntelligenceInternal(params: params, updateInfo: updateInfo) { result in
                switch result {
                case .success(let response): continuation.resume(returning: response)
                case .failure(let error):    continuation.resume(throwing: error)
                }
            }
        }
    }

    // Shared pipeline for both the ObjC callback form and the async form.
    // Kept internal to preserve the typed `UpdateInfo` / `Result` shape for the
    // async wrapper without exposing a second Swift-only public callback method.
    @available(iOS 15.0, *)
    private func fetchIntelligenceInternal(
        params: [String: String]?,
        updateInfo: UpdateInfo?,
        completion: @escaping @Sendable (Result<IntelligenceApiResponse, OTPlessIntelligenceError>) -> Void
    ) {
        IntelligenceEvents.getIntelligenceSdkCalled()
        guard DeviceIntelligenceManager.shared.sdkInitialized else {
            IntelligenceEvents.awaitingInit()
            IntelligenceEvents.requestIntelligenceInitFailed()
            completion(.failure(.notConfigured))
            return
        }
        DeviceIntelligenceManager.shared.getScore(params: params, updateInfo: updateInfo) { response, error, apiResponse in
            if response != nil {
                guard let apiResponse else {
                    completion(.failure(
                        .intelligenceError(requestId: OtplessEventIO.shared.trackingIds.sessionId, message: "Failed to push intelligence data to server")
                    ))
                    return
                }
                completion(.success(apiResponse))
            } else if let error {
                completion(.failure(.intelligenceError(requestId: error.requestId, message: error.errorMessage)))
            } else {
                completion(.failure(.intelligenceError(requestId: OtplessEventIO.shared.trackingIds.sessionId, message: "Unknown intelligence error")))
            }
        }
    }
}
