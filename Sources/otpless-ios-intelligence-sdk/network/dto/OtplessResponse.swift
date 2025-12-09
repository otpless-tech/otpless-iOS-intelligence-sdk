//
//  File.swift
//  otpless-ios-intelligence-sdk
//
//  Created by Shail Gupta on 09/12/25.
//

import Foundation

public struct OtplessResponse: @unchecked Sendable {
    public let response: [String: Any]?
    public let statusCode: Int
    
    public init(
      response: [String: Any]?,
      statusCode: Int
    ) {
      self.response = response
      self.statusCode = statusCode
    }
   
    internal func toJsonString() -> String {
        var dict: [String: Any] = [:]
        if let response = response {
            dict["response"] = response
        }
        dict["statusCode"] = statusCode
        return Utils.convertDictionaryToString(dict)
    }
    
    
    internal static func createUnauthorizedResponse(
        errorCode: String = "401",
        errorMessage: String = "UnAuthorized request!"
    ) -> OtplessResponse {
        let json: [String: Any] = [
            "errorMessage": errorMessage,
            "errorCode": errorCode
        ]
        return OtplessResponse(
            response: json,
            statusCode: 401
        )
    }
    
    internal static let failedToInitializeResponse = OtplessResponse( response: [
        "errorCode": "5003",
        "errorMessage": "Failed to initialize the SDK"
    ], statusCode: 5003)
    
    
    public func toString() -> String {
        return """
        Status Code: \(statusCode)\n
        Response: \(response ?? [:])
        """
    }
}
