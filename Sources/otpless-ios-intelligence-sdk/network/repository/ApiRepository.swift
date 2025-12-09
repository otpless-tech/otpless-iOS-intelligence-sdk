//
//  File.swift
//  otpless-ios-intelligence-sdk
//
//  Created by Shail Gupta on 09/12/25.
//

import Foundation


internal final class ApiRepository: @unchecked Sendable {
    private let apiManager: ApiManager
    
    init(userAuthApiTimeout: TimeInterval) {
        self.apiManager = ApiManager(userAuthTimeout: userAuthApiTimeout)
    }
    
    func getState(
        queryParams: [String: String]
    ) async -> Result<StateResponse, Error> {
        do {
            let data = try await self.apiManager.performUserAuthRequest(
                state: nil,
                path: ApiManager.GET_STATE_PATH,
                method: "GET",
                queryParameters: queryParams
            )
            return try Result.success(JSONDecoder().decode(StateResponse.self, from: data))
        } catch {
            return Result.failure(error)
        }
    }
    
    
    
    func pushIntelligenceData(bodyParams: [String: Any]) async -> Result<IntelligenceApiResponse, Error> {
        do {
            let data = try await self.apiManager.performUserAuthRequest(
                state: nil,
                path: ApiManager.INTELLIGENCE_DATA_PUSH_PATH,
                method: "POST",
                body: bodyParams
            )

            let decoded = try JSONDecoder().decode(IntelligenceApiResponse.self, from: data)
            return .success(decoded)
        } catch {
            return .failure(error)
        }
    }
    
}

extension ApiRepository {
    
    func handleResponse <T: Decodable> (
        response: Result<Data, Error>,
        onComplete: @escaping @Sendable (Result<T?, Error>) -> Void
    ) {
        switch response {
        case .success(let data):
            do {
                let response = try JSONDecoder().decode(T.self, from: data)
                onComplete(Result.success(response))
            } catch {
                onComplete(Result.failure(ApiError(message: "Could not decode response", statusCode: 500)))
            }
        case .failure(let error):
            if let error = error as? URLError {
                onComplete(Result.failure(error))
            }
        }
    }
}
