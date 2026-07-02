import Foundation

internal enum EventNames {
    static let initializeCalled            = "afp_initialize_called"
    static let getIntelligenceCalled       = "afp_get_intelligence_called"
    static let getIntelligenceSdkCalled  = "afp_get_intelligence_sdk_called"

    static let requestIntelligence         = "afp_request_intelligence"
    static let requestIntelligenceResult   = "afp_request_intelligence_result"
    static let configCached                = "afp_config_cached"
    static let awaitingInit                = "afp_awaiting_init"
    static let fetchIntelligenceRetry      = "afp_fetch_intelligence_retry"

    static let initPlayIntelligence        = "afp_init_play_intelligence"
    static let fetchPlayIntelligenceResult = "afp_fetch_play_intelligence_result"
    static let fetchPlayIntelligenceError  = "afp_fetch_play_intelligence_error"

    static let pushIntelligence            = "afp_push_intelligence"
    static let pushIntelligenceRetry       = "afp_push_intelligence_retry"
    static let pushIntelligenceFailed      = "afp_push_intelligence_failed"

    static let initFailed                  = "afp_init_failed"
    static let getScoreFailed              = "afp_get_score_failed"
}
