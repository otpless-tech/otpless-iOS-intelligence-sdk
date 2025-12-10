import Foundation
import IdentityFraud

internal final class DeviceIntelligenceManager :@unchecked Sendable {

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

    var dfrID = ""

    // MARK: - Initialize

    internal func initialize(
        clientId: String,
        clientSecret: String,
        completion: @escaping (Bool) -> Void
    ) {
       
        guard #available(iOS 15.0, *) else {
            completion(false)
            return
        }

        let builder = Options.OptionBuilder()
            .setClientId(clientId)
            .setClientSecret(clientSecret)
            .setBaseUrl(ApiManager.INTELLIGENCE_SERVER_PATH)
            .setEnvironment(.PROD)

        let options = builder.build()

        IdentitySDK.getInstance().initAsync(options: options) { [weak self] initialized in
            self?.sdkInitialized = initialized
            completion(initialized)
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
                await MainActor.run(body: {
                    onFetch(state)
                })
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

        if let userId {
            _ = builder.setUserId(userId)
        }
        if let phoneNumber {
            _ = builder.setPhoneNumber(phoneNumber)
        }
        if let attrs = additionalAttributes {
            _ = builder.setAdditionalAttributes(attrs)
        }

        let updateOption = builder.build()
        IdentitySDK.getInstance().updateOptions(updateOption: updateOption)
    }

    // MARK: - Get Score (raw types)
    internal func getScore(
        completion: @escaping (_ response: IntelligenceResponse?, _ error: IntelligenceError?) -> Void
    ) {
        DeviceIntelligenceManager.shared.dfrID = ""
        let state = SessionMgr.shared.getState() ?? ""

        if state.isEmpty {
            requestStateForDeviceIfNil(onFetch: { newState in
                guard let newState = newState, !newState.isEmpty else { return }
                SessionMgr.shared.setState(newState)
            })
        }
    
        guard #available(iOS 15.0, *) else {
            let error = IntelligenceError(
                requestId: SessionMgr.shared.getTsid() ?? "NA",
                errorMessage: "Unsupported iOS version"
            )
            completion(nil, error)
            return
        }

        let listener = ScoreListener(completion: completion)
        IdentitySDK.getInstance().getIntelligence(listener: listener)
    }
    
    /// Full raw JSON from `IntelligenceResponse` as a dictionary (includes all fields/nested objects).
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

    
    private func getRequestMap(authMap: [String:String]) -> [String: Any] {
        var requestData: [String: Any] = ["tsId": SessionMgr.shared.getTsid()]
        
        requestData["inId"] = SessionMgr.shared.getInid()
        requestData["appId"] = OTPlessIntelligence.shared.merchantAppId
        
        if let state = SessionMgr.shared.getState(), !state.isEmpty {
            requestData["state"] = state
        }
        
        if let asid = authMap["asId"],!asid.isEmpty{
            requestData["asId"] = asid
        }
        
        if !DeviceIntelligenceManager.shared.dfrID.isEmpty {
            requestData["dfrId"] = DeviceIntelligenceManager.shared.dfrID
        }
        if let token = authMap["token"],!token.isEmpty{
            requestData["token"] = token
        }
        return requestData
    }
    
    func pushIntelligenceDataToServerWithIntelligenceError(error: IntelligenceError) {
        var requestMap = getRequestMap(authMap:[:])
        requestMap["data"] = ["requestId":error.requestId,"errorMessage":error.errorMessage]
        postIntelligencData(data: requestMap)
    }
    
    func pushIntelligenceDataToServerWithIntelligenceData(response: IntelligenceResponse) {
        var requestMap = getRequestMap(authMap:[:])
        requestMap["data"] = buildRawJSON(from: response)
        postIntelligencData(data: requestMap)
    }
    
    // Wrapper type to make the payload Sendable for Task closure capture
    private struct IntelligencePayload: @unchecked Sendable {
        let data: [String: Any]
    }
    
    internal func postIntelligencData(data: [String: Any]) {
        // Cancel any in-flight request
        currentIntelligenceTask?.cancel()
        
        let payload = IntelligencePayload(data: data)
        
        // Start a new task with Sendable payload + Sendable self
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

            case .error(_):
                // If we've exhausted attempts, stop
                if attempt == maxAttempts { return }

                do {
                    let nanos = delayMs * 1_000_000  // ms → ns
                    try await Task.sleep(nanoseconds: nanos)
                } catch {
                    // Task was cancelled while sleeping
                    return
                }

                // Next attempt
                delayMs *= 2
                attempt += 1
            }
        }
    }
    
    internal func updateAuthMap(authMap : [String:String]) {
        if !dfrID.isEmpty {
            var requestMap = getRequestMap(authMap: authMap)
            postIntelligencData(data: requestMap)
        }
    }

}

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

