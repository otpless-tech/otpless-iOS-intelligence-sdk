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
        case .manual:     return IdentityFraud.PhoneInputType.MANUAL
        case .copyPasted: return IdentityFraud.PhoneInputType.COPY_PASTE
        case .googleHint: return IdentityFraud.PhoneInputType.GOOGLE_HINT
        }
    }
}

internal extension OtpInputType {
    var identityFraudValue: IdentityFraud.OtpInputType {
        switch self {
        case .manual:     return IdentityFraud.OtpInputType.MANUAL
        case .copyPasted: return IdentityFraud.OtpInputType.COPY_PASTED
        case .autoFilled: return IdentityFraud.OtpInputType.AUTO_FILLED
        }
    }
}

internal extension UserEventType {
    var identityFraudValue: IdentityFraud.UserEventType {
        switch self {
        case .login:       return IdentityFraud.UserEventType.LOGIN
        case .signup:      return IdentityFraud.UserEventType.SIGNUP
        case .transaction: return IdentityFraud.UserEventType.TRANSACTION
        case .others:      return IdentityFraud.UserEventType.OTHERS
        }
    }
}
