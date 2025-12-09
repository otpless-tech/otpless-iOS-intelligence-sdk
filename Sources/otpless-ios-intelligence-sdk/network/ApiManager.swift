
import Foundation

final class ApiManager: Sendable {
    private let userAuthTimeout: TimeInterval
    private let baseURLUserAuth = "https://user-auth.otpless.app"
    // MARK: Paths for APIs
    static let GET_STATE_PATH = "/v2/state"
    static let INTELLIGENCE_DATA_PUSH_PATH = "/v3/device/device-fingerprint"
    static let INTELLIGENCE_SERVER_PATH = "https://fingerprint.otpless.com/"
    
    init(
        userAuthTimeout: TimeInterval = 20.0
    ) {
        self.userAuthTimeout = userAuthTimeout
    }
    
    // MARK: - User Auth API Request
    func performUserAuthRequest(
        state: String?,
        path: String,
        method: String,
        body: [String: Any]? = nil,
        queryParameters: [String: Any]? = nil
    ) async throws -> Data {
        var newPath = path
        if let state = state { newPath = path.replacingOccurrences(of: "{state}", with: state) }

        let url = constructURL(baseURL: baseURLUserAuth, path: newPath, queryParameters: queryParameters, method: method)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = userAuthTimeout
        
        if method.uppercased() == "POST" {

            request.httpBody = try? JSONSerialization.data(withJSONObject: body!, options: [])
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }


        do {
            let (data, response) = try await URLSession.shared.data(for: request)

//            if enableLogging {
//                var sentBodyDict: [String: Any]? = nil
//                if let hb = request.httpBody,
//                   let obj = try? JSONSerialization.jsonObject(with: hb) as? [String: Any] {
//                    sentBodyDict = obj
//                }
//                logRequestAndResponse(request, body: sentBodyDict, response, data: data)
//            }

            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }


            if !(200..<300).contains(http.statusCode) {

                let errorBody = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
                throw ApiError(
                    message: errorBody["message"] as? String ?? "Unexpected error occurred",
                    statusCode: http.statusCode,
                    responseJson: errorBody
                )
            }

//            // success tracking (if you still want it)
//             if shouldTrackSuccess(path: newPath, method: method, statusCode: http.statusCode, data: data) {
//                 sendApiEvent(event: .SUCCESS_API_RESPONSE, path: newPath, method: method, statusCode: http.statusCode,
//                              startedAt: startedAt, xRequestId: xRequestId, data: nil)
//             }

            return data
        } catch {
            // normalize
            let apiError: ApiError
            if let e = error as? ApiError {
                apiError = e
            } else if let urlError = error as? URLError {
                apiError = handleURLError(urlError)   // make sure this does NOT emit
            } else {
                apiError = ApiError(message: error.localizedDescription, statusCode: 500, responseJson: [
                    "errorCode": "500", "errorMessage": "Something Went Wrong!"
                ])
            }

//            // single, centralized emit (uses stashed HTTP data/status if available)
//            sendApiEvent(
//                event: .ERROR_API_RESPONSE,
//                path: newPath,
//                method: method,
//                statusCode: pendingStatusCode ?? apiError.statusCode,
//                startedAt: startedAt,
//                xRequestId: xRequestId,
//                data: pendingErrorData,           // includes api_response when we had one
//                apiError: apiError
//            )

            throw apiError
        }
    }

    
    // MARK: - Helpers
    private func constructURL(
        baseURL: String,
        path: String,
        queryParameters: [String: Any]?,
        method: String
    ) -> URL {
        var urlComponents = URLComponents(string: baseURL + path)!
        
        if method.uppercased() == "POST" {
            return urlComponents.url!
        }
        
        let extraQueryParams = [
            URLQueryItem(name: "origin", value: "https://otpless.com"),
            URLQueryItem(name: "tsId", value: SessionMgr.shared.getTsid()),
            URLQueryItem(name: "inId", value: SessionMgr.shared.getInid()),
            URLQueryItem(name: "version", value: "V4"),
            URLQueryItem(name: "isHeadless", value: "true"),
            URLQueryItem(name: "platform", value: "iOS"),
            URLQueryItem(name: "isLoginPage", value: "false"),
            URLQueryItem(name: "appId", value: OTPlessIntelligence.shared.merchantAppId)
        ]
        
             
        if let queryParameters = queryParameters {
            urlComponents.queryItems = queryParameters.map { URLQueryItem(name: $0.key, value: ($0.value as? String ?? "")) }
        }
        
        for queryItem in extraQueryParams {
            urlComponents.queryItems?.append(queryItem)
        }
        
        return urlComponents.url!
    }
    
//    private func logRequestAndResponse(_ request: URLRequest, body: [String: Any]?, _ response: URLResponse?, data: Data) {
//        let urlStr = request.url?.absoluteString
//        let method = request.httpMethod
//        var logBody: [String: Any] = [:]
//        if let body = body {
//            logBody = body
//        }
//        
//        var statusCode = -1
//        
//        if let httpResponse = response as? HTTPURLResponse {
//            statusCode = httpResponse.statusCode
//        }
//    }
    
    private func handleURLError(_ urlError: URLError) -> ApiError {
        let code = urlError.errorCode
        let errorBody = urlError.errorUserInfo
        
        switch urlError.code {
        case .timedOut:
            return ApiError(message: "Request timeout", statusCode: 9100, responseJson: [
                "errorCode": "9100",
                "errorMessage": "Request timeout"
            ])
        case .networkConnectionLost:
            return ApiError(message: "Network connection was lost", statusCode: 9101, responseJson: [
                "errorCode": "9101",
                "errorMessage": "Network connection was lost"
            ])
        case .dnsLookupFailed:
            return ApiError(message: "DNS lookup failed", statusCode: 9102, responseJson: [
                "errorCode": "9102",
                "errorMessage": "DNS lookup failed"
            ])
        case .cannotConnectToHost:
            return ApiError(message: "Cannot connect to the server", statusCode: 9103, responseJson: [
                "errorCode": "9103",
                "errorMessage": "Cannot connect to the server"
            ])
        case .notConnectedToInternet:
            return ApiError(message: "No internet connection", statusCode: 9104, responseJson: [
                "errorCode": "9104",
                "errorMessage": "No internet connection"
            ])
        case .secureConnectionFailed:
            return ApiError(message: "Secure connection failed (SSL issue)", statusCode: 9105, responseJson: [
                "errorCode": "9105",
                "errorMessage": "Secure connection failed (SSL issue)"
            ])
        case .cancelled:
            return ApiError(message: "Otpless authentication request cancelled", statusCode: 9110, responseJson: [
                "errorCode": "9110",
                "errorMessage": "Otpless authentication request cancelled"
            ])
        default:
            let errorMessage = errorBody["message"] as? String ?? "Something Went Wrong!"
            return ApiError(message: errorMessage, statusCode: code, responseJson: errorBody)
        }
    }
}

internal enum ApiResponse<T> {
    case success(data: T?)
    case error(error: ApiError)
}

internal final class ApiError: Error, @unchecked Sendable {
    let message: String
    let statusCode: Int
    let responseJson: [String: Any]?

    init(message: String, statusCode: Int = 0, responseJson: [String: Any]? = nil) {
        self.message = message
        self.statusCode = statusCode
        self.responseJson = responseJson
    }

    var description: String {
        return "message: \(message)\nstatusCode: \(statusCode)\(responseJson != nil ? "\n\(responseJson!)" : "")"
    }
    
    func getResponse() -> [String: String] {
        let errorCode = responseJson?["errorCode"] as? String ?? String(statusCode)
        
        return [
            "errorCode": errorCode,
            "errorMessage": responseJson?["description"] as? String ?? message
        ]
    }
}
