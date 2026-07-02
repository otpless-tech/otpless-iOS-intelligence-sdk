import Foundation

internal enum LogLevel {
    case info, error
}

internal struct OTPlessLogger {
    private static func prefix(for level: LogLevel) -> String {
        return level == .error ? "[OTPless][ERROR]" : "[OTPless][INFO]"
    }

    static func log(_ message: String, level: LogLevel = .info) {
        #if DEBUG
        print("\(prefix(for: level)) \(message)")
        #endif
    }

    /// Verbose logging, gated by the `OTPLESS_DEBUG` compile flag (separate from
    /// `DEBUG`). Use for high-volume diagnostics like request/response bodies that
    /// we don't want emitted even in standard debug builds, and that must never
    /// reach release versions or third-party SPM/CocoaPods consumers.
    ///
    /// `message` is `@autoclosure` so the expression is *only* evaluated when the
    /// flag is on — when `OTPLESS_DEBUG` is undefined, the message-building work
    /// (e.g. `Utils.convertDictionaryToString(...)`) is never executed.
    ///
    /// The flag is intentionally NOT defined in `Package.swift` or the podspec,
    /// so by default no consumer ever gets it. Internal test apps opt in via a
    /// CocoaPods `post_install` hook (see CLAUDE.md / README for the snippet).
    static func verboseLog(_ message: @autoclosure () -> String, level: LogLevel = .info) {
        #if OTPLESS_DEBUG
        print("\(prefix(for: level)) \(message())")
        #endif
    }
}
