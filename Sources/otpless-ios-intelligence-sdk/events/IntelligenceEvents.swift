import Foundation
import OtplessEventIO

internal enum IntelligenceEvents {

    /// Central sink — every event built in this file goes through here.
    /// Call sites stay one line: `IntelligenceEvents.initializeCalled()`.
    private static func trackEvent(_ event: OtplessTrackEvent) {
        OtplessEventIO.shared.push(event)
    }

    // MARK: - CLIENT_TO_SDK

    static func initializeCalled() {
        trackEvent(OtplessTrackEvent(
            eventType: .CLIENT_TO_SDK,
            action: .REQUEST,
            eventName: EventNames.initializeCalled
        ))
    }

    static func getIntelligenceCalled() {
        trackEvent(OtplessTrackEvent(
            eventType: .CLIENT_TO_SDK,
            action: .REQUEST,
            eventName: EventNames.getIntelligenceCalled
        ))
    }

    static func getIntelligenceSdkCalled() {
        trackEvent(OtplessTrackEvent(
            eventType: .CLIENT_TO_SDK,
            action: .REQUEST,
            eventName: EventNames.getIntelligenceSdkCalled
        ))
    }

    // MARK: - SDK (internal flow)

    static func requestIntelligenceStart() {
        trackEvent(OtplessTrackEvent(
            eventType: .SDK,
            action: .REQUEST,
            eventName: EventNames.requestIntelligence,
            data: ["start": "fresh"]
        ))
    }

    static func requestIntelligenceInitFailed() {
        trackEvent(OtplessTrackEvent(
            eventType: .SDK,
            action: .RESPONSE,
            eventName: EventNames.requestIntelligence,
            data: ["result": "failed", "reason": "init sdk failed"]
        ))
    }

    static func requestIntelligenceResult(success: Bool) {
        trackEvent(OtplessTrackEvent(
            eventType: .SDK,
            action: .RESPONSE,
            eventName: EventNames.requestIntelligenceResult,
            data: ["result": success ? "success" : "failure"]
        ))
    }

    static func configCached(clientId: String) {
        trackEvent(OtplessTrackEvent(
            eventType: .SDK,
            action: .RESPONSE,
            eventName: EventNames.configCached,
            data: ["clientId": clientId]
        ))
    }

    static func awaitingInit() {
        trackEvent(OtplessTrackEvent(
            eventType: .SDK,
            action: .RESPONSE,
            eventName: EventNames.awaitingInit
        ))
    }

    static func fetchIntelligenceRetry(delayMs: UInt64) {
        trackEvent(OtplessTrackEvent(
            eventType: .SDK,
            action: .RESPONSE,
            eventName: EventNames.fetchIntelligenceRetry,
            data: ["delay": delayMs]
        ))
    }

    // MARK: - IdentityFraud (Play) bridge

    static func initPlayIntelligence(result: Bool, responseTimeMs: Int) {
        trackEvent(OtplessTrackEvent(
            eventType: .SDK,
            action: .RESPONSE,
            eventName: EventNames.initPlayIntelligence,
            data: ["result": result, "responseTime": responseTimeMs]
        ))
    }

    static func fetchPlayIntelligenceResult(payload: [String: Any]) {
        trackEvent(OtplessTrackEvent(
            eventType: .SDK,
            action: .RESPONSE,
            eventName: EventNames.fetchPlayIntelligenceResult,
            data: payload
        ))
    }

    static func fetchPlayIntelligenceError(requestId: String, message: String) {
        trackEvent(OtplessTrackEvent(
            eventType: .SDK,
            action: .RESPONSE,
            eventName: EventNames.fetchPlayIntelligenceError,
            data: ["errorMessage": message, "requestId": requestId]
        ))
    }

    // MARK: - SDK_TO_OTPLESS (network)

    static func pushIntelligenceStart() {
        trackEvent(OtplessTrackEvent(
            eventType: .SDK_TO_OTPLESS,
            action: .REQUEST,
            eventName: EventNames.pushIntelligence
        ))
    }

    static func pushIntelligenceSuccess(response: IntelligenceApiResponse) {
        var payload: [String: Any] = ["dfrId": response.dfrId]
        if let inner = response.intelligenceResponse {
            payload["intelligenceResponse"] = inner
        }
        trackEvent(OtplessTrackEvent(
            eventType: .SDK_TO_OTPLESS,
            action: .RESPONSE,
            eventName: EventNames.pushIntelligence,
            data: payload
        ))
    }

    static func pushIntelligenceRetry(delayMs: UInt64, statusCode: Int?) {
        trackEvent(OtplessTrackEvent(
            eventType: .SDK_TO_OTPLESS,
            action: .RESPONSE,
            eventName: EventNames.pushIntelligenceRetry,
            statusCode: statusCode,
            data: ["delay": delayMs]
        ))
    }

    static func pushIntelligenceFailed() {
        trackEvent(OtplessTrackEvent(
            eventType: .SDK_TO_OTPLESS,
            action: .RESPONSE,
            eventName: EventNames.pushIntelligenceFailed
        ))
    }

    // MARK: - SDK-level failure events

    static func initFailed(reason: String) {
        trackEvent(OtplessTrackEvent(
            eventType: .SDK,
            action: .RESPONSE,
            eventName: EventNames.initFailed,
            data: ["reason": reason]
        ))
    }

    static func getScoreFailed(reason: String) {
        trackEvent(OtplessTrackEvent(
            eventType: .SDK,
            action: .RESPONSE,
            eventName: EventNames.getScoreFailed,
            data: ["reason": reason]
        ))
    }
}
