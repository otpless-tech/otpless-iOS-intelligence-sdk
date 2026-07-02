import Foundation

final internal class ApiManager: Sendable {
    private let apiTimeout: TimeInterval

    // MARK: - Base URLs
    static let PLATFORM_BASE_URL = "https://platform.otpless.app"

    // MARK: - Paths
    static let GET_CONFIG_PATH = "/sdk/v1/device-fingerprint/config"
    static let PUSH_INTELLIGENCE_PATH = "/sdk/v1/device-fingerprint"

    // Base URL used to initialise IdentityFraud SDK
    static let INTELLIGENCE_SERVER_PATH = "https://fingerprint.otpless.com/"

    init(apiTimeout: TimeInterval = 20.0) {
        self.apiTimeout = apiTimeout
    }

    // MARK: - Platform API Request (platform.otpless.app)
    // Used for config fetch and intelligence data push.
    // appId is sent as an HTTP header.
    func performPlatformRequest(
        appId: String,
        path: String,
        method: String,
        body: [String: Any]? = nil,
        queryParameters: [String: Any]? = nil
    ) async throws -> Data {
        var urlComponents = URLComponents(string: ApiManager.PLATFORM_BASE_URL + path)!

        if method.uppercased() == "GET", let queryParameters = queryParameters {
            urlComponents.queryItems = queryParameters.map {
                URLQueryItem(name: $0.key, value: $0.value as? String ?? "")
            }
        }

        guard let url = urlComponents.url else {
            throw ApiError(message: "Invalid URL", statusCode: 0)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = apiTimeout
        request.setValue(appId, forHTTPHeaderField: "appId")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if method.uppercased() == "POST", let body = body {
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }

        let startMs = Self.currentTimeMs()
        OTPlessLogger.verboseLog(Self.formatRequestLog(request: request, body: body))

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let elapsedMs = Self.currentTimeMs() - startMs

            guard let http = response as? HTTPURLResponse else {
                OTPlessLogger.verboseLog("<-- HTTP FAILED: Bad server response (\(elapsedMs)ms)", level: .error)
                throw URLError(.badServerResponse)
            }

            OTPlessLogger.verboseLog(Self.formatResponseLog(http: http, url: url, data: data, elapsedMs: elapsedMs))

            if !(200..<300).contains(http.statusCode) {
                let errorBody = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
                throw ApiError(
                    message: errorBody["message"] as? String ?? "Unexpected error occurred",
                    statusCode: http.statusCode,
                    responseJson: errorBody
                )
            }

            return data
        } catch {
            let apiError: ApiError
            if let e = error as? ApiError {
                // HTTP response already logged above; rethrow as-is.
                apiError = e
            } else if let urlError = error as? URLError {
                let elapsedMs = Self.currentTimeMs() - startMs
                OTPlessLogger.verboseLog("<-- HTTP FAILED: \(urlError.code.rawValue) \(urlError.localizedDescription) (\(elapsedMs)ms)", level: .error)
                apiError = handleURLError(urlError)
            } else {
                let elapsedMs = Self.currentTimeMs() - startMs
                OTPlessLogger.verboseLog("<-- HTTP FAILED: \(error.localizedDescription) (\(elapsedMs)ms)", level: .error)
                apiError = ApiError(message: error.localizedDescription, statusCode: 500, responseJson: [
                    "errorCode": "500", "errorMessage": "Something Went Wrong!"
                ])
            }
            throw apiError
        }
    }

    // MARK: - OkHttp-style request/response logging
    // All formatters are invoked through OTPlessLogger.verboseLog(@autoclosure),
    // so when OTPLESS_DEBUG is undefined they are never called and pay zero cost.

    private static func formatRequestLog(request: URLRequest, body: [String: Any]?) -> String {
        let method = request.httpMethod ?? "GET"
        let urlString = request.url?.absoluteString ?? "<no-url>"
        var lines: [String] = ["--> \(method) \(urlString)"]
        if let fields = request.allHTTPHeaderFields {
            for (key, value) in fields.sorted(by: { $0.key < $1.key }) {
                lines.append("\(key): \(value)")
            }
        }
        if let body {
            lines.append(Utils.convertDictionaryToString(body))
        }
        let byteCount = request.httpBody?.count ?? 0
        lines.append("--> END \(method) (\(byteCount)-byte body)")
        return lines.joined(separator: "\n")
    }

    private static func formatResponseLog(http: HTTPURLResponse, url: URL, data: Data, elapsedMs: Int) -> String {
        var lines: [String] = ["<-- \(http.statusCode) \(url.absoluteString) (\(elapsedMs)ms)"]
        if let pretty = prettyJsonString(data) {
            lines.append(pretty)
        } else if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
            lines.append(raw)
        }
        lines.append("<-- END HTTP")
        return lines.joined(separator: "\n")
    }

    private static func prettyJsonString(_ data: Data) -> String? {
        guard
            let obj = try? JSONSerialization.jsonObject(with: data),
            let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]),
            let str = String(data: pretty, encoding: .utf8)
        else { return nil }
        return str
    }

    private static func currentTimeMs() -> Int {
        Int(Date().timeIntervalSince1970 * 1000)
    }

    // MARK: - Helpers

    private func handleURLError(_ urlError: URLError) -> ApiError {
        let code = urlError.errorCode
        let errorBody = urlError.errorUserInfo

        switch urlError.code {
        case .timedOut:
            return ApiError(message: "Request timeout", statusCode: 9100, responseJson: [
                "errorCode": "9100", "errorMessage": "Request timeout"
            ])
        case .networkConnectionLost:
            return ApiError(message: "Network connection was lost", statusCode: 9101, responseJson: [
                "errorCode": "9101", "errorMessage": "Network connection was lost"
            ])
        case .dnsLookupFailed:
            return ApiError(message: "DNS lookup failed", statusCode: 9102, responseJson: [
                "errorCode": "9102", "errorMessage": "DNS lookup failed"
            ])
        case .cannotConnectToHost:
            return ApiError(message: "Cannot connect to the server", statusCode: 9103, responseJson: [
                "errorCode": "9103", "errorMessage": "Cannot connect to the server"
            ])
        case .notConnectedToInternet:
            return ApiError(message: "No internet connection", statusCode: 9104, responseJson: [
                "errorCode": "9104", "errorMessage": "No internet connection"
            ])
        case .secureConnectionFailed:
            return ApiError(message: "Secure connection failed (SSL issue)", statusCode: 9105, responseJson: [
                "errorCode": "9105", "errorMessage": "Secure connection failed (SSL issue)"
            ])
        case .cancelled:
            return ApiError(message: "Otpless authentication request cancelled", statusCode: 9110, responseJson: [
                "errorCode": "9110", "errorMessage": "Otpless authentication request cancelled"
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
