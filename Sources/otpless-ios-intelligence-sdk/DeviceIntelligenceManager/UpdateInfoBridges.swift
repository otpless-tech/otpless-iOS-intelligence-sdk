import Foundation
@_implementationOnly import IdentityFraud

// MARK: - Public → IdentityFraud enum bridges
// IdentityFraud is `@_implementationOnly`, so callers see only the public
// enums in `UpdateInfo.swift`. These bridges convert each public case to its
// IdentityFraud counterpart at the point of use inside the manager — keeping
// IdentityFraud types out of every public signature.

internal extension PhoneInputType {
    var identityFraudValue: IdentityFraud.PhoneInputType {
        switch self {
        case .MANUAL:      return IdentityFraud.PhoneInputType.MANUAL
        case .COPY_PASTED: return IdentityFraud.PhoneInputType.COPY_PASTE
        case .GOOGLE_HINT: return IdentityFraud.PhoneInputType.GOOGLE_HINT
        }
    }
}

internal extension OtpInputType {
    var identityFraudValue: IdentityFraud.OtpInputType {
        switch self {
        case .MANUAL:      return IdentityFraud.OtpInputType.MANUAL
        case .COPY_PASTED: return IdentityFraud.OtpInputType.COPY_PASTED
        case .AUTO_FILLED: return IdentityFraud.OtpInputType.AUTO_FILLED
        }
    }
}

internal extension UserEventType {
    var identityFraudValue: IdentityFraud.UserEventType {
        switch self {
        case .LOGIN:       return IdentityFraud.UserEventType.LOGIN
        case .SIGNUP:      return IdentityFraud.UserEventType.SIGNUP
        case .TRANSACTION: return IdentityFraud.UserEventType.TRANSACTION
        case .OTHERS:      return IdentityFraud.UserEventType.OTHERS
        }
    }
}
