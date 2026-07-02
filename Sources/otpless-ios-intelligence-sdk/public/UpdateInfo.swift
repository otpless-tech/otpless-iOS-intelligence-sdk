import Foundation

public enum PhoneInputType: String, Sendable {
    case manual = "MANUAL"
    case copyPasted = "COPY_PASTED"
    case googleHint = "GOOGLE_HINT"
}

public enum OtpInputType: String, Sendable {
    case manual = "MANUAL"
    case copyPasted = "COPY_PASTED"
    case autoFilled = "AUTO_FILLED"
}

public enum UserEventType: String, Sendable {
    case login = "LOGIN"
    case signup = "SIGNUP"
    case transaction = "TRANSACTION"
    case others = "OTHERS"
}

public struct UpdateInfo: Sendable {
    public let userId: String?
    public let phoneNumber: String?
    public let merchantId: String?
    public let phoneInputType: PhoneInputType?
    public let otpInputType: OtpInputType?
    public let userEventType: UserEventType?
    public let additionalInput: [String: String]?

    public init(
        userId: String? = nil,
        phoneNumber: String? = nil,
        merchantId: String? = nil,
        phoneInputType: PhoneInputType? = nil,
        otpInputType: OtpInputType? = nil,
        userEventType: UserEventType? = nil,
        additionalInput: [String: String]? = nil
    ) {
        self.userId = userId
        self.phoneNumber = phoneNumber
        self.merchantId = merchantId
        self.phoneInputType = phoneInputType
        self.otpInputType = otpInputType
        self.userEventType = userEventType
        self.additionalInput = additionalInput
    }
}

// Bridges an ObjC-friendly `[String: Any]` payload into the typed `UpdateInfo`
// so ObjC callers can invoke `fetchIntelligence` without touching Swift enums.
// Enum-typed fields expect raw-value strings matching the case names above
// (e.g. "MANUAL", "COPY_PASTED", "LOGIN"); unrecognised values are dropped.
internal extension UpdateInfo {
    static func from(dictionary dict: [String: Any]?) -> UpdateInfo? {
        guard let dict, !dict.isEmpty else { return nil }
        return UpdateInfo(
            userId: dict["userId"] as? String,
            phoneNumber: dict["phoneNumber"] as? String,
            merchantId: dict["merchantId"] as? String,
            phoneInputType: (dict["phoneInputType"] as? String).flatMap(PhoneInputType.init(rawValue:)),
            otpInputType: (dict["otpInputType"] as? String).flatMap(OtpInputType.init(rawValue:)),
            userEventType: (dict["userEventType"] as? String).flatMap(UserEventType.init(rawValue:)),
            additionalInput: dict["additionalInput"] as? [String: String]
        )
    }
}
