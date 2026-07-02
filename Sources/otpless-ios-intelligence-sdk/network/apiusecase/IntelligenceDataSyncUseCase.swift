import Foundation

class IntelligenceDataSyncUseCase {
    func invoke(bodyParams: [String: Any]) async -> ApiResponse<IntelligencePushResult> {
        let result = await ApiRepository.shared.pushIntelligenceData(bodyParams: bodyParams)
        switch result {
        case .success(let response):
            return .success(data: response)

        case .failure(let error):
            let apiError = (error as? ApiError)
                ?? ApiError(message: error.localizedDescription)
            return .error(error: apiError)
        }
    }
}
