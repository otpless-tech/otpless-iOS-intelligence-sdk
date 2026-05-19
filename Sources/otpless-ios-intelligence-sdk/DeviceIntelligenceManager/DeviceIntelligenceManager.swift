import Foundation
@_implementationOnly import IdentityFraud

internal final class DeviceIntelligenceManager: @unchecked Sendable {

    static let shared = DeviceIntelligenceManager()
    private init() {}

    internal private(set) var sdkInitialized: Bool = false
    internal let apiRepository = ApiRepository(userAuthApiTimeout: 30.0)
    private var currentIntelligenceTask: Task<Void, Never>?

    private lazy var intelligenceDataUseCase: IntelligenceDataUseCase = {
        return IntelligenceDataUseCase()
    }()

    private lazy var getStateUseCase: GetState = {
        return GetState()
    }()

    private lazy var getConfigUseCase: GetConfig = {
        return GetConfig()
    }()

    private var dfrID = ""

    // MARK: - Initialize

    // completion is @Sendable so it can be safely captured in the Task closure (Swift 6).
    internal func initialize(completion: @escaping @Sendable (Bool) -> Void) {
        guard #available(iOS 15.0, *) else {
            OTPlessLogger.log("configure() requires iOS 15.0 or later", level: .error)
            completion(false)
            return
        }

        OTPlessLogger.log("Initialising — appId: \(OTPlessIntelligence.shared.merchantAppId), bundle: \(Bundle.main.bundleIdentifier ?? "unknown")")

        Task { [weak self] in
            guard let config = await self?.getConfigUseCase.invoke() else {
                OTPlessLogger.log("Initialisation failed: could not fetch config from platform API", level: .error)
                OTPlessLogger.log("Check: (1) appId is correct, (2) iOS intelligence is enabled for this app in the OTPless dashboard, (3) network connectivity", level: .error)
                completion(false)
                return
            }

            OTPlessLogger.log("Initialising IdentityFraud SDK…")
            let builder = Options.OptionBuilder()
                .setClientId(config.intelligenceClientId)
                .setClientSecret(config.secret)
                .setBaseUrl(ApiManager.INTELLIGENCE_SERVER_PATH)
                .setSSLPinning(true)
                .setEnvironment(.PROD)

            let options = builder.build()

            IdentitySDK.getInstance().initAsync(options: options) { [weak self] initialized in
                if initialized {
                    OTPlessLogger.log("IdentityFraud SDK initialised successfully")
                } else {
                    OTPlessLogger.log("IdentityFraud SDK initialisation failed — check clientId/secret validity", level: .error)
                }
                self?.sdkInitialized = initialized
                completion(initialized)
            }
        }
    }

    private func requestStateForDeviceIfNil(onFetch: @escaping @Sendable (String?) -> Void) {
        if let savedState = SecureStorage.shared.retrieve(key: Constants.STATE_KEY),
           !savedState.isEmpty {
            onFetch(savedState)
        } else {
            Task(priority: .medium) { [weak self] in
                let stateResponse = await self?.getStateUseCase
                    .invoke(queryParams: [:], isRetry: false)
                let state = stateResponse?.0?.state
                await MainActor.run {
                    onFetch(state)
                }
            }
        }
    }

    internal func updateOptions(
        userId: String? = nil,
        phoneNumber: String? = nil,
        additionalAttributes: [String: String]? = nil
    ) {
        guard #available(iOS 15.0, *) else { return }

        let builder = UpdateOption.UpdateOptionBuilder()
        if let userId { _ = builder.setUserId(userId) }
        if let phoneNumber { _ = builder.setPhoneNumber(phoneNumber) }
        if let attrs = additionalAttributes { _ = builder.setAdditionalAttributes(attrs) }

        IdentitySDK.getInstance().updateOptions(updateOption: builder.build())
    }

    // MARK: - Get Score

    // Uses withCheckedContinuation to bridge IdentitySDK's callback to async/await.
    // This avoids capturing callback parameters (IntelligenceResponse) inside a Task,
    // which is a Swift 6 region-isolation violation.
    internal func getScore(
        completion: @escaping @Sendable (_ response: IntelligenceResponse?, _ error: IntelligenceError?, _ apiResponse: IntelligenceApiResponse?) -> Void
    ) {
        self.dfrID = ""
        let state = SessionMgr.shared.getState() ?? ""

        if state.isEmpty {
            requestStateForDeviceIfNil { newState in
                guard let newState = newState, !newState.isEmpty else { return }
                SessionMgr.shared.setState(newState)
            }
        }

        guard #available(iOS 15.0, *) else {
            OTPlessLogger.log("fetchIntelligence requires iOS 15.0 or later", level: .error)
            let error = IntelligenceError(
                requestId: SessionMgr.shared.getTsid(),
                errorMessage: "Unsupported iOS version"
            )
            completion(nil, error, nil)
            return
        }

        OTPlessLogger.log("Fetching device intelligence — tsId: \(SessionMgr.shared.getTsid())")

        Task {
            // Bridge the callback-based IdentitySDK API to async/await.
            // SDKCallbackResult is @unchecked Sendable so it can be safely passed through
            // withCheckedContinuation.resume(returning:) which requires a sending value.
            let result = await withCheckedContinuation { (continuation: CheckedContinuation<SDKCallbackResult, Never>) in
                IdentitySDK.getInstance().getIntelligence(
                    listener: BridgeListener { r, e in
                        continuation.resume(returning: SDKCallbackResult(response: r, error: e))
                    }
                )
            }

            let (response, sdkError) = (result.response, result.error)

            if let response {
                OTPlessLogger.log("IdentityFraud response received — requestId: \(response.requestId ?? "nil")")
                let apiResponse = await DeviceIntelligenceManager.shared.pushIntelligenceDataAndAwait(response: response)
                completion(response, nil, apiResponse)
            } else if let sdkError {
                OTPlessLogger.log("IdentityFraud error — requestId: \(sdkError.requestId), message: \(sdkError.errorMessage)", level: .error)
                DeviceIntelligenceManager.shared.pushIntelligenceDataToServerWithIntelligenceError(error: sdkError)
                completion(nil, sdkError, nil)
            } else {
                completion(nil, nil, nil)
            }
        }
    }

    // MARK: - Request Body Builder

    private func getRequestMap(authMap: [String: String]) -> [String: Any] {
        var requestData: [String: Any] = [
            "tsId": SessionMgr.shared.getTsid(),
            "platform": "IOS"
        ]

        requestData["inId"] = SessionMgr.shared.getInid()
        requestData["appId"] = OTPlessIntelligence.shared.merchantAppId

        if let rsId = SessionMgr.shared.getRsid(), !rsId.isEmpty {
            requestData["rsId"] = rsId
        }

        // Cached in SessionMgr.initialize() on the main thread to avoid main-actor isolation issues.
        let idfv = SessionMgr.shared.vendorId
        if !idfv.isEmpty {
            requestData["gaId"] = idfv
        }

        if let state = SessionMgr.shared.getState(), !state.isEmpty {
            requestData["state"] = state
        }

        if let asid = authMap["asId"], !asid.isEmpty {
            requestData["asId"] = asid
        }

        if !self.dfrID.isEmpty {
            requestData["dfrId"] = self.dfrID
        }

        if let token = authMap["token"], !token.isEmpty {
            requestData["token"] = token
        }

        return requestData
    }

    // MARK: - Push to Backend

    private func pushIntelligenceDataToServerWithIntelligenceError(error: IntelligenceError) {
        var requestMap = getRequestMap(authMap: [:])
        requestMap["data"] = ["requestId": error.requestId, "errorMessage": error.errorMessage]
        postIntelligencData(data: requestMap)
    }

    private func pushIntelligenceDataAndAwait(response: IntelligenceResponse) async -> IntelligenceApiResponse? {
        OTPlessLogger.log("Pushing intelligence data — requestId: \(response.requestId ?? "nil")")
        var requestMap = getRequestMap(authMap: [:])
        requestMap["data"] = buildRawJSON(from: response)
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

    // Retry schedule: attempt 1 → wait 3s → attempt 2 → wait 6s → attempt 3 → error
    @discardableResult
    private func sendIntelligenceDataWithRetry(data: [String: Any]) async -> IntelligenceApiResponse? {
        let retryDelaysMs: [UInt64] = [3_000, 6_000]
        let maxAttempts = 3

        for attempt in 1...maxAttempts {
            guard !Task.isCancelled else { return nil }

            OTPlessLogger.log("Intelligence push attempt \(attempt)/\(maxAttempts)")
            let response = await intelligenceDataUseCase.invoke(bodyParams: data)

            switch response {
            case .success(let resp):
                if let dfrId = resp?.dfrId, !dfrId.isEmpty {
                    OTPlessLogger.log("Intelligence push succeeded — dfrId: \(dfrId), responseKeys: \(Array(resp?.rawResponse.keys ?? [:].keys))")
                    self.dfrID = dfrId
                    return resp
                } else {
                    OTPlessLogger.log("Intelligence push returned success but dfrId is missing (attempt \(attempt)/\(maxAttempts))", level: .error)
                }
            case .error(let error):
                OTPlessLogger.log("Intelligence push failed (attempt \(attempt)/\(maxAttempts)) — \(error.message)", level: .error)
            }

            if attempt < maxAttempts {
                let delayMs = retryDelaysMs[attempt - 1]
                OTPlessLogger.log("Retrying intelligence push in \(delayMs / 1_000)s…")
                do {
                    try await Task.sleep(nanoseconds: delayMs * 1_000_000)
                } catch {
                    return nil
                }
            } else {
                OTPlessLogger.log("Intelligence push exhausted all \(maxAttempts) attempts", level: .error)
            }
        }
        return nil
    }

    internal func updateAuthMap(authMap: [String: String]) {
        if !dfrID.isEmpty {
            let requestMap = getRequestMap(authMap: authMap)
            postIntelligencData(data: requestMap)
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
