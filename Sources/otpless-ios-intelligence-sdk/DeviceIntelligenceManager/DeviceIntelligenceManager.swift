import Foundation
import IdentityFraud

internal final class DeviceIntelligenceManager {

    static let shared = DeviceIntelligenceManager()
    private init() {}

    internal private(set) var sdkInitialized: Bool = false

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
            .setBaseUrl("https://fingerprint.otpless.com/")
            .setEnvironment(.PROD)      // fixed PROD

        let options = builder.build()

        IdentitySDK.getInstance().initAsync(options: options) { [weak self] initialized in
            self?.sdkInitialized = initialized
            completion(initialized)
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
        guard #available(iOS 15.0, *) else {
            let error = IntelligenceError(
                requestId: "NA",
                errorMessage: "Unsupported iOS version"
            )
            completion(nil, error)
            return
        }

        let listener = ScoreListener(completion: completion)
        IdentitySDK.getInstance().getIntelligence(listener: listener)
    }
}

internal final class ScoreListener: NSObject, IntelligenceResponseListener {

    private let completion: (IntelligenceResponse?, IntelligenceError?) -> Void

    init(completion: @escaping (IntelligenceResponse?, IntelligenceError?) -> Void) {
        self.completion = completion
    }

    func onSuccess(response: IntelligenceResponse) {
        completion(response, nil)
    }

    func onError(error: IntelligenceError) {
        completion(nil, error)
    }
}
