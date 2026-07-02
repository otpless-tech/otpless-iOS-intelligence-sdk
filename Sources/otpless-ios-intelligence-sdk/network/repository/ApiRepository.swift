import Foundation

internal final class ApiRepository: @unchecked Sendable {
    private let apiManager: ApiManager
    static let shared = ApiRepository(apiTimeout: 10)
    private init(apiTimeout: TimeInterval) {
        self.apiManager = ApiManager(apiTimeout: apiTimeout)
    }

    // MARK: - Config

    /// Fetches intelligenceClientId + secret from the platform API.
    /// appId is read from OTPlessIntelligence.shared since it is already set before initialize() is called.
    func getConfig() async -> Result<ConfigResponse, Error> {
        let appId = OTPlessIntelligence.shared.merchantAppId
        let bundleId = Bundle.main.bundleIdentifier ?? ""
        let queryParams: [String: Any] = [
            "packageName": bundleId,
            "platform": "IOS"
        ]
        do {
            let data = try await apiManager.performPlatformRequest(
                appId: appId,
                path: ApiManager.GET_CONFIG_PATH,
                method: "GET",
                queryParameters: queryParams
            )
            return try .success(JSONDecoder().decode(ConfigResponse.self, from: data))
        } catch let apiError as ApiError {
            OTPlessLogger.log("Config API error — status: \(apiError.statusCode), message: \(apiError.message)", level: .error)
            if let body = apiError.responseJson {
                OTPlessLogger.log("Response body: \(body)", level: .error)
            }
            return .failure(apiError)
        } catch {
            OTPlessLogger.log("Config request error — \(error.localizedDescription)", level: .error)
            return .failure(error)
        }
    }

    // MARK: - Intelligence Push

    /// Posts device intelligence data to the platform API.
    /// appId is read from OTPlessIntelligence.shared (always available at call time).
    func pushIntelligenceData(bodyParams: [String: Any]) async -> Result<IntelligencePushResult, Error> {
        let appId = OTPlessIntelligence.shared.merchantAppId
        do {
            let data = try await apiManager.performPlatformRequest(
                appId: appId,
                path: ApiManager.PUSH_INTELLIGENCE_PATH,
                method: "POST",
                body: bodyParams
            )
            let rawResponse = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            let dfrId = rawResponse["dfrId"] as? String
            return .success(IntelligencePushResult(dfrId: dfrId, rawResponse: rawResponse))
        } catch let apiError as ApiError {
            OTPlessLogger.log("Intelligence push API error — status: \(apiError.statusCode), message: \(apiError.message)", level: .error)
            return .failure(apiError)
        } catch {
            OTPlessLogger.log("Intelligence push request error — \(error.localizedDescription)", level: .error)
            return .failure(error)
        }
    }
}

extension ApiRepository {

    func handleResponse<T: Decodable>(
        response: Result<Data, Error>,
        onComplete: @escaping @Sendable (Result<T?, Error>) -> Void
    ) {
        switch response {
        case .success(let data):
            do {
                let decoded = try JSONDecoder().decode(T.self, from: data)
                onComplete(.success(decoded))
            } catch {
                onComplete(.failure(ApiError(message: "Could not decode response", statusCode: 500)))
            }
        case .failure(let error):
            if let error = error as? URLError {
                onComplete(.failure(error))
            }
        }
    }
}
