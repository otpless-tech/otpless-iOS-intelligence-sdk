import Foundation

internal enum LogLevel {
    case info, error
}

internal struct OTPlessLogger {
    static func log(_ message: String, level: LogLevel = .info) {
        #if DEBUG
        let prefix = level == .error ? "[OTPless][ERROR]" : "[OTPless]"
        print("\(prefix) \(message)")
        #endif
    }
}
