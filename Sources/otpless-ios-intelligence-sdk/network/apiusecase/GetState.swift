//
//  File.swift
//  otpless-ios-intelligence-sdk
//
//  Created by Shail Gupta on 08/12/25.
//

import Foundation

class GetState {
    private var retryCount = 0
    
    func invoke(
        queryParams: [String: String],
        isRetry: Bool
    ) async -> (StateResponse?, OtplessResponse?) {
        if !isRetry {
            retryCount = 0
        }
        let response = await DeviceIntelligenceManager.shared.apiRepository
            .getState(queryParams: queryParams)
        
        switch response {
        case .success(let success):
            return (success, nil)
        case .failure(_):
            if retryCount == 1 {
                retryCount = 0
                return (nil, OtplessResponse.failedToInitializeResponse)
            } else {
                retryCount += 1
                return await invoke(queryParams: queryParams, isRetry: true)
            }
        }
    }
}

struct StateResponse: Codable {
    let state: String?
}


