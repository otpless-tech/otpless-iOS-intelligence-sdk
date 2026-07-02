import Foundation
import OtplessEventIO
@_implementationOnly import IdentityFraud

internal final class DeviceIntelligenceManager: @unchecked Sendable {

    static let shared = DeviceIntelligenceManager()
    private init() {}

    internal private(set) var sdkInitialized: Bool = false
    private var currentIntelligenceTask: Task<Void, Never>?

    private lazy var intelligenceDataUseCase: IntelligenceDataSyncUseCase = {
        return IntelligenceDataSyncUseCase()
    }()

    private lazy var getConfigUseCase: GetConfig = {
        return GetConfig()
    }()

    private var dfrID = ""

    // MARK: - Initialize

    // completion is @Sendable so it can be safely captured in the Task closure (Swift 6).
    internal func initialize(completion: @escaping @Sendable (Bool) -> Void) {
        guard #available(iOS 15.0, *) else {
            IntelligenceEvents.initFailed(reason: "ios_version_unsupported")
            completion(false)
            return
        }
        Task { [weak self] in
            guard let config = await self?.getConfigUseCase.invoke() else {
                IntelligenceEvents.initFailed(reason: "config_fetch_failed")
                completion(false)
                return
            }

            let builder = Options.OptionBuilder()
                .setClientId(config.intelligenceClientId)
                .setClientSecret(config.secret)

            let options = builder.build()

            let initStartMs = Self.currentTimeMs()
            IdentitySDK.getInstance().initAsync(options: options) { [weak self] initialized in
                let elapsedMs = Self.currentTimeMs() - initStartMs
                IntelligenceEvents.initPlayIntelligence(
                    result: initialized,
                    responseTimeMs: elapsedMs
                )
                if !initialized {
                    IntelligenceEvents.initFailed(reason: "identity_fraud_init_failed")
                }
                self?.sdkInitialized = initialized
                completion(initialized)
            }
        }
    }

    // MARK: - Get Score

    // Uses withCheckedContinuation to bridge IdentitySDK's callback to async/await.
    // This avoids capturing callback parameters (IntelligenceResponse) inside a Task,
    // which is a Swift 6 region-isolation violation.
    internal func getScore(
        params: [String: String]? = nil,
        updateInfo: UpdateInfo? = nil,
        completion: @escaping @Sendable (_ response: IntelligenceResponse?, _ error: IntelligenceError?, _ apiResponse: IntelligenceApiResponse?) -> Void
    ) {
        self.dfrID = ""

        guard #available(iOS 15.0, *) else {
            IntelligenceEvents.getScoreFailed(reason: "ios_version_unsupported")
            let error = IntelligenceError(
                requestId: OtplessEventIO.shared.trackingIds.sessionId,
                errorMessage: "Unsupported iOS version"
            )
            completion(nil, error, nil)
            return
        }

        applyUpdateOptions(updateInfo)

        IntelligenceEvents.requestIntelligenceStart()
        OTPlessLogger.log("Fetching device intelligence — tsId: \(OtplessEventIO.shared.trackingIds.sessionId)")

        Task {
            // Engine call wrapped in a 500ms-base exponential retry loop (4 max).
            let result = await DeviceIntelligenceManager.shared.runEngineWithRetry()

            let (response, sdkError) = (result.response, result.error)

            if let response {
                OTPlessLogger.log("IdentityFraud response received — requestId: \(response.requestId ?? "nil")")
                let rawPayload = DeviceIntelligenceManager.shared.buildRawJSON(from: response)
                IntelligenceEvents.fetchPlayIntelligenceResult(payload: rawPayload)

                let pushResult = await DeviceIntelligenceManager.shared.pushIntelligenceDataAndAwait(
                    rawPayload: rawPayload,
                    params: params
                )
                let publicResponse: IntelligenceApiResponse?
                if let pushResult, let dfrId = pushResult.dfrId, !dfrId.isEmpty {
                    publicResponse = IntelligenceApiResponse(
                        dfrId: dfrId,
                        intelligenceResponse: pushResult.rawResponse["intelligenceResponse"] as? [String: Any]
                    )
                    IntelligenceEvents.requestIntelligenceResult(success: true)
                } else {
                    publicResponse = nil
                    IntelligenceEvents.requestIntelligenceResult(success: false)
                }

                completion(response, nil, publicResponse)
            } else if let sdkError {
                OTPlessLogger.log("IdentityFraud error — requestId: \(sdkError.requestId), message: \(sdkError.errorMessage)", level: .error)
                IntelligenceEvents.fetchPlayIntelligenceError(
                    requestId: sdkError.requestId,
                    message: sdkError.errorMessage
                )
                DeviceIntelligenceManager.shared.pushIntelligenceDataToServerWithIntelligenceError(
                    error: sdkError,
                    params: params
                )
                IntelligenceEvents.requestIntelligenceResult(success: false)
                completion(nil, sdkError, nil)
            } else {
                IntelligenceEvents.requestIntelligenceResult(success: false)
                completion(nil, nil, nil)
            }
        }
    }

    /// Map our public `UpdateInfo` onto IdentityFraud's `UpdateOption` builder
    /// using its typed setters (not the additionalAttributes catch-all).
    ///
    /// `setUserId(_:)`, `setPhoneNumber(_:)`, and `setMerchantId(_:)` take
    /// `String?` in IdentityFraud's swiftinterface and are gated behind the
    /// `$NonescapableTypes` Swift feature. To avoid forcing every consumer to
    /// enable that experimental flag, we invoke those three via the ObjC
    /// runtime (the methods are `@objc` and present in the binary).
    @available(iOS 15.0, *)
    private func applyUpdateOptions(_ updateInfo: UpdateInfo?) {
        guard let updateInfo else { return }
        let builder = UpdateOption.UpdateOptionBuilder()
        if let phoneInput = updateInfo.phoneInputType {
            builder.setPhoneInputType(phoneInput.identityFraudValue)
        }
        if let otpInput = updateInfo.otpInputType {
            builder.setOtpInputType(otpInput.identityFraudValue)
        }
        if let userEvent = updateInfo.userEventType {
            builder.setUserEventType(userEvent.identityFraudValue)
        }
        if let attrs = updateInfo.additionalInput, !attrs.isEmpty {
            _ = builder.setAdditionalAttributes(attrs)
        }
        IdentitySDK.getInstance().updateOptions(updateOption: builder.build())
    }

    // MARK: - Request Body Builder

    private func getRequestMap(
        params: [String: String]?
    ) -> [String: Any] {
        var requestData: [String: Any] = [
            "tsId": OtplessEventIO.shared.trackingIds.sessionId,
            "inId": OtplessEventIO.shared.trackingIds.installationId,
            "platform": "IOS",
            "appId": OTPlessIntelligence.shared.merchantAppId
        ]

        // Generic pass-through of caller-supplied params (mirrors Android).
        // Reserved keys are SDK-controlled and cannot be overridden by the host.
        if let params {
            for (key, value) in params
            where !value.isEmpty && !Self.reservedParamKeys.contains(key) {
                requestData[key] = value
            }
        }
        return requestData
    }

    /// Keys the SDK manages itself — `params` entries with these names are ignored
    /// rather than overwriting the SDK-set values. Matches the Android reserved set
    /// (`data`, `status`, `requestId`, `message`) plus iOS's own SDK-controlled keys.
    private static let reservedParamKeys: Set<String> = ["data", "status", "requestId", "message", "tsId", "inId", "platform", "appId"]

    // MARK: - Push to Backend

    private func pushIntelligenceDataToServerWithIntelligenceError(
        error: IntelligenceError,
        params: [String: String]?
    ) {
        var requestMap = getRequestMap(params: params)
        requestMap["data"] = ["requestId": error.requestId, "errorMessage": error.errorMessage]
        postIntelligencData(data: requestMap)
    }

    private func pushIntelligenceDataAndAwait(
        rawPayload: [String: Any],
        params: [String: String]?
    ) async -> IntelligencePushResult? {
        OTPlessLogger.log("Pushing intelligence data")
        var requestMap = getRequestMap(params: params)
        requestMap["data"] = rawPayload
        return await sendIntelligenceDataWithRetry(data: requestMap)
    }

    private func buildRawJSON(from response: IntelligenceResponse) -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard
            let data = try? encoder.encode(response),
            let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return ["message": "Failed to encode IntelligenceResponse"]
        }
        return dict
    }

    private struct IntelligencePayload: @unchecked Sendable {
        let data: [String: Any]
    }

    private func postIntelligencData(data: [String: Any]) {
        currentIntelligenceTask?.cancel()
        let payload = IntelligencePayload(data: data)
        currentIntelligenceTask = Task { [weak self, payload] in
            await self?.sendIntelligenceDataWithRetry(data: payload.data)
        }
    }

    // Retry schedule: BackoffTimer (500ms base, exponential, 4 max attempts).
    // Matches Android Veritaserum SDK exactly.
    @discardableResult
    private func sendIntelligenceDataWithRetry(data: [String: Any]) async -> IntelligencePushResult? {
        var backoff = BackoffTimer(baseDelayMs: 500, maxAttempts: 4)

        while true {
            guard !Task.isCancelled else { return nil }

            IntelligenceEvents.pushIntelligenceStart()
            let attemptNum = backoff.attemptsMade + 1
            OTPlessLogger.log("Intelligence push attempt \(attemptNum)")
            let response = await intelligenceDataUseCase.invoke(bodyParams: data)

            switch response {
            case .success(let resp):
                if let dfrId = resp?.dfrId, !dfrId.isEmpty {
                    OTPlessLogger.log("Intelligence push succeeded — dfrId: \(dfrId)")
                    self.dfrID = dfrId
                    let publicResponse = IntelligenceApiResponse(
                        dfrId: dfrId,
                        intelligenceResponse: resp?.rawResponse["intelligenceResponse"] as? [String: Any]
                    )
                    IntelligenceEvents.pushIntelligenceSuccess(response: publicResponse)
                    return resp
                }
                OTPlessLogger.log("Intelligence push returned success but dfrId is missing (attempt \(attemptNum))", level: .error)

                guard let delayMs = backoff.nextDelayMs() else {
                    IntelligenceEvents.pushIntelligenceFailed()
                    return nil
                }
                IntelligenceEvents.pushIntelligenceRetry(delayMs: delayMs, statusCode: nil)
                try? await Task.sleep(nanoseconds: delayMs * 1_000_000)

            case .error(let error):
                OTPlessLogger.log("Intelligence push failed (attempt \(attemptNum)) — \(error.message)", level: .error)
                guard let delayMs = backoff.nextDelayMs() else {
                    IntelligenceEvents.pushIntelligenceFailed()
                    return nil
                }
                IntelligenceEvents.pushIntelligenceRetry(
                    delayMs: delayMs,
                    statusCode: error.statusCode == 0 ? nil : error.statusCode
                )
                try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
            }
        }
    }

    private static func currentTimeMs() -> Int {
        Int(Date().timeIntervalSince1970 * 1000)
    }

    @available(iOS 15.0, *)
    private func runEngineWithRetry() async -> SDKCallbackResult {
        var backoff = BackoffTimer(baseDelayMs: 500, maxAttempts: 4)
        var lastResult = SDKCallbackResult(response: nil, error: nil)

        while true {
            let result = await withCheckedContinuation { (continuation: CheckedContinuation<SDKCallbackResult, Never>) in
                IdentitySDK.getInstance().getIntelligence(
                    listener: BridgeListener { r, e in
                        continuation.resume(returning: SDKCallbackResult(response: r, error: e))
                    }
                )
            }

            if result.response != nil {
                return result
            }

            lastResult = result

            guard let delayMs = backoff.nextDelayMs() else {
                return lastResult
            }

            IntelligenceEvents.fetchIntelligenceRetry(delayMs: delayMs)
            OTPlessLogger.log("Engine retry in \(delayMs)ms…")

            do {
                try await Task.sleep(nanoseconds: delayMs * 1_000_000)
            } catch {
                return lastResult
            }
        }
    }
}

// MARK: - SDKCallbackResult
// @unchecked Sendable wrapper so IntelligenceResponse / IntelligenceError
// (NSObject subclasses from an @_implementationOnly import) can be safely
// passed through CheckedContinuation.resume(returning:) which requires Sendable.
private struct SDKCallbackResult: @unchecked Sendable {
    let response: IntelligenceResponse?
    let error: IntelligenceError?
}

// MARK: - BridgeListener
// Simple callback-only listener — no Task creation.
// withCheckedContinuation in getScore properly bridges the async boundary.
private final class BridgeListener: NSObject, IntelligenceResponseListener {

    private let handler: @Sendable (IntelligenceResponse?, IntelligenceError?) -> Void

    init(handler: @escaping @Sendable (IntelligenceResponse?, IntelligenceError?) -> Void) {
        self.handler = handler
    }

    func onSuccess(response: IntelligenceResponse) {
        handler(response, nil)
    }

    func onError(error: IntelligenceError) {
        handler(nil, error)
    }
}
