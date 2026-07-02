import Foundation

public struct IntelligenceApiResponse: @unchecked Sendable {
    public let dfrId: String
    public let intelligenceResponse: [String: Any]?

    public init(dfrId: String, intelligenceResponse: [String: Any]?) {
        self.dfrId = dfrId
        self.intelligenceResponse = intelligenceResponse
    }
}
