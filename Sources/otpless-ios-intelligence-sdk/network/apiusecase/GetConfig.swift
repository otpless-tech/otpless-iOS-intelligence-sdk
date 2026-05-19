import Foundation

class GetConfig {
    private var retryCount = 0

    func invoke(isRetry: Bool = false) async -> ConfigResponse? {
        if !isRetry { retryCount = 0 }

        OTPlessLogger.log("Config fetch attempt \(retryCount + 1)")
        let result = await DeviceIntelligenceManager.shared.apiRepository.getConfig()

        switch result {
        case .success(let config):
            OTPlessLogger.log("Config fetch succeeded")
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
