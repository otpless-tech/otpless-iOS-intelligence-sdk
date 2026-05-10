import Foundation
import IdentityFraud
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

    var dfrID = ""

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

    func requestStateForDeviceIfNil(onFetch: @escaping @Sendable (String?) -> Void) {
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
        completion: @escaping (_ response: IntelligenceResponse?, _ error: IntelligenceError?) -> Void
    ) {
        DeviceIntelligenceManager.shared.dfrID = ""
        let state = SessionMgr.shared.getState() ?? ""

        if state.isEmpty {
            requestStateForDeviceIfNil { newState in
                guard let newState = newState, !newState.isEmpty else { return }
                SessionMgr.shared.setState(newState)
            }
        }

        guard #available(iOS 15.0, *) else {
            let error = IntelligenceError(
                requestId: SessionMgr.shared.getTsid(),
                errorMessage: "Unsupported iOS version"
            )
            completion(nil, error)
            return
        }

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

        if !DeviceIntelligenceManager.shared.dfrID.isEmpty {
            requestData["dfrId"] = DeviceIntelligenceManager.shared.dfrID
        }

        if let token = authMap["token"], !token.isEmpty {
            requestData["token"] = token
        }

        return requestData
    }

    // MARK: - Push to Backend

    func pushIntelligenceDataToServerWithIntelligenceError(error: IntelligenceError) {
        var requestMap = getRequestMap(authMap: [:])
        requestMap["data"] = ["requestId": error.requestId, "errorMessage": error.errorMessage]
        postIntelligencData(data: requestMap)
    }

    func pushIntelligenceDataToServerWithIntelligenceData(response: IntelligenceResponse) {
        var requestMap = getRequestMap(authMap: [:])
        requestMap["data"] = buildRawJSON(from: response)
        postIntelligencData(data: requestMap)
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

    internal func postIntelligencData(data: [String: Any]) {
        currentIntelligenceTask?.cancel()
        let payload = IntelligencePayload(data: data)
        currentIntelligenceTask = Task { [weak self, payload] in
            await self?.sendIntelligenceDataWithRetry(data: payload.data)
        }
    }

    private func sendIntelligenceDataWithRetry(
        data: [String: Any],
        maxAttempts: Int = 5,
        initialDelayMs: UInt64 = 100
    ) async {
        var attempt = 1
        var delayMs = initialDelayMs

        while !Task.isCancelled && attempt <= maxAttempts {
            let response = await intelligenceDataUseCase.invoke(bodyParams: data)

            switch response {
            case .success(let resp):
                if let dfrID = resp?.dfrId {
                    DeviceIntelligenceManager.shared.dfrID = dfrID
                }
                return

            case .error:
                if attempt == maxAttempts { return }
                do {
                    try await Task.sleep(nanoseconds: delayMs * 1_000_000)
                } catch {
                    return
                }
                delayMs *= 2
                attempt += 1
            }
        }
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

    private let completion: (IntelligenceResponse?, IntelligenceError?) -> Void

    init(completion: @escaping (IntelligenceResponse?, IntelligenceError?) -> Void) {
        self.completion = completion
    }

    func onSuccess(response: IntelligenceResponse) {
        DeviceIntelligenceManager.shared.pushIntelligenceDataToServerWithIntelligenceData(response: response)
        completion(response, nil)
    }

    func onError(error: IntelligenceError) {
        DeviceIntelligenceManager.shared.pushIntelligenceDataToServerWithIntelligenceError(error: error)
        completion(nil, error)
    }
}
