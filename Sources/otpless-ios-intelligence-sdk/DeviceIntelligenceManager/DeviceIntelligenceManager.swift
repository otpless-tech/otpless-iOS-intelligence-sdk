import Foundation
@_implementationOnly import IdentityFraud
import UIKit

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
    // Fetches intelligenceClientId + secret from the platform config API,
    // then initialises IdentitySDK with those credentials.
    internal func initialize(completion: @escaping (Bool) -> Void) {
        guard #available(iOS 15.0, *) else {
            OTPlessLogger.log("configure() requires iOS 15.0 or later", level: .error)
            completion(false)
            return
        }

        OTPlessLogger.log("Initialising — appId: \(OTPlessIntelligence.shared.merchantAppId), bundle: \(Bundle.main.bundleIdentifier ?? "unknown")")

        Task { [weak self] in
            // Step 1: fetch credentials from platform API
            guard let config = await self?.getConfigUseCase.invoke() else {
                OTPlessLogger.log("Initialisation failed: could not fetch config from platform API", level: .error)
                OTPlessLogger.log("Check: (1) appId is correct, (2) iOS intelligence is enabled for this app in the OTPless dashboard, (3) network connectivity", level: .error)
                completion(false)
                return
            }

            // Step 2: init IdentityFraud SDK with fetched credentials
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

        let updateOption = builder.build()
        IdentitySDK.getInstance().updateOptions(updateOption: updateOption)
    }

    // MARK: - Get Score
    internal func getScore(
        completion: @escaping (_ response: IntelligenceResponse?, _ error: IntelligenceError?, _ apiResponse: IntelligenceApiResponse?) -> Void
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
        let listener = ScoreListener(completion: completion)
        IdentitySDK.getInstance().getIntelligence(listener: listener)
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

        // Vendor identifier — iOS equivalent of Android gaId
        if let idfv = UIDevice.current.identifierForVendor?.uuidString {
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

    fileprivate func pushIntelligenceDataToServerWithIntelligenceError(error: IntelligenceError) {
        var requestMap = getRequestMap(authMap: [:])
        requestMap["data"] = ["requestId": error.requestId, "errorMessage": error.errorMessage]
        postIntelligencData(data: requestMap)
    }

    /// Awaitable push — waits for the backend response and returns it.
    /// Used by ScoreListener so fetchIntelligence() always carries the backend result.
    fileprivate func pushIntelligenceDataAndAwait(response: IntelligenceResponse) async -> IntelligenceApiResponse? {
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
    // Failure condition: API error OR dfrId missing/empty in success response
    @discardableResult
    private func sendIntelligenceDataWithRetry(
        data: [String: Any]
    ) async -> IntelligenceApiResponse? {
        let retryDelaysMs: [UInt64] = [3_000, 6_000]
        let maxAttempts = 3

        for attempt in 1...maxAttempts {
            guard !Task.isCancelled else { return nil }

            OTPlessLogger.log("Intelligence push attempt \(attempt)/\(maxAttempts)")
            let response = await intelligenceDataUseCase.invoke(bodyParams: data)

            switch response {
            case .success(let resp):
                if let dfrId = resp?.dfrId, !dfrId.isEmpty {
                    // Success — dfrId present
                    OTPlessLogger.log("Intelligence push succeeded — dfrId: \(dfrId), responseKeys: \(Array(resp?.rawResponse.keys ?? [:].keys))")
                    self.dfrID = dfrId
                    return resp
                } else {
                    // API returned 2xx but dfrId is missing — treat as failure
                    OTPlessLogger.log("Intelligence push returned success but dfrId is missing (attempt \(attempt)/\(maxAttempts))", level: .error)
                }

            case .error(let error):
                OTPlessLogger.log("Intelligence push failed (attempt \(attempt)/\(maxAttempts)) — \(error.message)", level: .error)
            }

            // Schedule retry or give up
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

// MARK: - ScoreListener

internal final class ScoreListener: NSObject, IntelligenceResponseListener {

    private let completion: (IntelligenceResponse?, IntelligenceError?, IntelligenceApiResponse?) -> Void

    init(completion: @escaping (IntelligenceResponse?, IntelligenceError?, IntelligenceApiResponse?) -> Void) {
        self.completion = completion
    }

    func onSuccess(response: IntelligenceResponse) {
        OTPlessLogger.log("IdentityFraud response received — requestId: \(response.requestId ?? "nil")")
        Task {
            let apiResponse = await DeviceIntelligenceManager.shared
                .pushIntelligenceDataAndAwait(response: response)
            completion(response, nil, apiResponse)
        }
    }

    func onError(error: IntelligenceError) {
        OTPlessLogger.log("IdentityFraud error — requestId: \(error.requestId), message: \(error.errorMessage)", level: .error)
        DeviceIntelligenceManager.shared.pushIntelligenceDataToServerWithIntelligenceError(error: error)
        completion(nil, error, nil)
    }
}
