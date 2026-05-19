//
//  IntelligenceSync.swift
//  otpless-ios-intelligence-sdk
//
//  Created by Shail Gupta on 08/12/25.
//






import Foundation

struct IntelligenceApiResponse {
    let dfrId: String?
    let rawResponse: [String: Any]
}

class IntelligenceDataUseCase {
    func invoke(bodyParams: [String: Any]) async -> ApiResponse<IntelligenceApiResponse> {
        let result = await DeviceIntelligenceManager.shared.apiRepository
            .pushIntelligenceData(bodyParams: bodyParams)

        switch result {
        case .success(let response):
            return .success(data: response)

        case .failure(let error):
            // Map Swift Error → ApiError
            let apiError = (error as? ApiError)
                ?? ApiError(message: error.localizedDescription)
            return .error(error: apiError)
        }
    }
}


