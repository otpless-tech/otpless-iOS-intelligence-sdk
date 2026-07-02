import Foundation

internal class GetConfig {
    private var retryCount = 0
    private var config: ConfigResponse? = nil

    func invoke(isRetry: Bool = false) async -> ConfigResponse? {
        if let config = self.config {
            return config
        }
        if !isRetry { retryCount = 0 }
        OTPlessLogger.log("Config fetch attempt \(retryCount + 1)")
        let result = await ApiRepository.shared.getConfig()

        switch result {
        case .success(let config):
            OTPlessLogger.log("Config fetch succeeded")
            IntelligenceEvents.configCached(clientId: config.intelligenceClientId)
            self.config = config
            return config
        case .failure(let error):
            OTPlessLogger.log("Config fetch failed — \(error.localizedDescription)", level: .error)
            if retryCount >= 1 {
                OTPlessLogger.log("Config fetch exhausted retries", level: .error)
                retryCount = 0
                return nil
            }
            retryCount += 1
            OTPlessLogger.log("Retrying config fetch…")
            return await invoke(isRetry: true)
        }
    }
}
