import Foundation
import IdentityFraud

// MARK: - Public Error Type (Swift only)

public enum OTPlessIntelligenceError: Error {
    /// `configure(clientId:clientSecret:)` was never successfully called
    case notConfigured

    ///  SDK returned an error
    case intelligenceError(requestId: String, message: String)

    /// Unexpected nil / inconsistent state
    case unknown
}

// MARK: - Public DTO (ObjC-compatible)

/// Structured, OTPless-facing intelligence response.
/// This is what the OTPless Auth SDK / end app will use.
///
/// ObjC can see this class and its properties because it is
/// an @objcMembers NSObject subclass.
@objcMembers
public class OTPlessIntelligenceResponse: NSObject, Codable {

    public let requestId: String
    public let deviceId: String
    public let ip: String

    public let simulator: Bool
    public let jailbroken: Bool
    public let vpn: Bool
    public let geoSpoofed: Bool
    public let appTampering: Bool
    public let hooking: Bool
    public let proxy: Bool
    public let mirroredScreen: Bool
    public let cloned: Bool
    public let newDevice: Bool
    public let factoryReset: Bool

    public let factoryResetTime: Int

    // New: OTPless DTOs (no IdentityFraud dependency here)
    public let gpsLocation: GPSLocation?
    public let ipDetails: IPDetails?
    public let deviceMeta: DeviceMeta?

    public init(
        requestId: String,
        deviceId: String,
        ip: String,
        simulator: Bool,
        jailbroken: Bool,
        vpn: Bool,
        geoSpoofed: Bool,
        appTampering: Bool,
        hooking: Bool,
        proxy: Bool,
        mirroredScreen: Bool,
        cloned: Bool,
        newDevice: Bool,
        factoryReset: Bool,
        factoryResetTime: Int,
        gpsLocation: GPSLocation?,
        ipDetails: IPDetails?,
        deviceMeta: DeviceMeta?
    ) {
        self.requestId = requestId
        self.deviceId = deviceId
        self.ip = ip
        self.simulator = simulator
        self.jailbroken = jailbroken
        self.vpn = vpn
        self.geoSpoofed = geoSpoofed
        self.appTampering = appTampering
        self.hooking = hooking
        self.proxy = proxy
        self.mirroredScreen = mirroredScreen
        self.cloned = cloned
        self.newDevice = newDevice
        self.factoryReset = factoryReset
        self.factoryResetTime = factoryResetTime
        self.gpsLocation = gpsLocation
        self.ipDetails = ipDetails
        self.deviceMeta = deviceMeta
        super.init()
    }

    // Required for Codable on NSObject subclasses
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.requestId = try container.decode(String.self, forKey: .requestId)
        self.deviceId = try container.decode(String.self, forKey: .deviceId)
        self.ip = try container.decode(String.self, forKey: .ip)

        self.simulator = try container.decode(Bool.self, forKey: .simulator)
        self.jailbroken = try container.decode(Bool.self, forKey: .jailbroken)
        self.vpn = try container.decode(Bool.self, forKey: .vpn)
        self.geoSpoofed = try container.decode(Bool.self, forKey: .geoSpoofed)
        self.appTampering = try container.decode(Bool.self, forKey: .appTampering)
        self.hooking = try container.decode(Bool.self, forKey: .hooking)
        self.proxy = try container.decode(Bool.self, forKey: .proxy)
        self.mirroredScreen = try container.decode(Bool.self, forKey: .mirroredScreen)
        self.cloned = try container.decode(Bool.self, forKey: .cloned)
        self.newDevice = try container.decode(Bool.self, forKey: .newDevice)
        self.factoryReset = try container.decode(Bool.self, forKey: .factoryReset)

        self.factoryResetTime = try container.decode(Int.self, forKey: .factoryResetTime)

        self.gpsLocation = try container.decodeIfPresent(GPSLocation.self, forKey: .gpsLocation)
        self.ipDetails = try container.decodeIfPresent(IPDetails.self, forKey: .ipDetails)
        self.deviceMeta = try container.decodeIfPresent(DeviceMeta.self, forKey: .deviceMeta)

        super.init()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(requestId, forKey: .requestId)
        try container.encode(deviceId, forKey: .deviceId)
        try container.encode(ip, forKey: .ip)

        try container.encode(simulator, forKey: .simulator)
        try container.encode(jailbroken, forKey: .jailbroken)
        try container.encode(vpn, forKey: .vpn)
        try container.encode(geoSpoofed, forKey: .geoSpoofed)
        try container.encode(appTampering, forKey: .appTampering)
        try container.encode(hooking, forKey: .hooking)
        try container.encode(proxy, forKey: .proxy)
        try container.encode(mirroredScreen, forKey: .mirroredScreen)
        try container.encode(cloned, forKey: .cloned)
        try container.encode(newDevice, forKey: .newDevice)
        try container.encode(factoryReset, forKey: .factoryReset)

        try container.encode(factoryResetTime, forKey: .factoryResetTime)

        try container.encodeIfPresent(gpsLocation, forKey: .gpsLocation)
        try container.encodeIfPresent(ipDetails, forKey: .ipDetails)
        try container.encodeIfPresent(deviceMeta, forKey: .deviceMeta)
    }

    private enum CodingKeys: String, CodingKey {
        case requestId
        case deviceId
        case ip
        case simulator
        case jailbroken
        case vpn
        case geoSpoofed
        case appTampering
        case hooking
        case proxy
        case mirroredScreen
        case cloned
        case newDevice
        case factoryReset
        case factoryResetTime

        case gpsLocation
        case ipDetails
        case deviceMeta
    }
}

// MARK: - Wrapper for Swift API

/// Wrapper returned from Swift `getScore`:
/// - `response`  → structured DTO for app / SDK (ObjC compatible)
/// - `rawJson`  → full JSON of  IntelligenceResponse (all fields)
public struct OTPlessIntelligenceResult {
    public let response: OTPlessIntelligenceResponse
    public let rawJson: String

    public init(response: OTPlessIntelligenceResponse, rawJson: String) {
        self.response = response
        self.rawJson = rawJson
    }
}

// MARK: - Public Facade (Swift API)

public final class OTPlessIntelligence {

    public static let shared = OTPlessIntelligence()
    private init() {}

    // MARK: - Configure
    @available(iOS 15.0, *)
    public func configure(
        clientId: String,
        clientSecret: String,
        completion: @escaping (Bool) -> Void
    ) {
        DeviceIntelligenceManager.shared.initialize(
            clientId: clientId,
            clientSecret: clientSecret,
            completion: completion
        )
    }

    @available(iOS 15.0, *)
    public func updateOptions(
        userId: String? = nil,
        phoneNumber: String? = nil,
        additionalAttributes: [String: String]? = nil
    ) {
        DeviceIntelligenceManager.shared.updateOptions(
            userId: userId,
            phoneNumber: phoneNumber,
            additionalAttributes: additionalAttributes
        )
    }

    // MARK: - Get Score (DTO + raw JSON)

    /// Returns:
    /// - `OTPlessIntelligenceResponse` → structured view for OTPless Auth / app
    /// - `rawJson` → full encoded `IntelligenceResponse` (all fields)
    ///
    @available(iOS 15.0, *)
    public func getScore(
        completion: @escaping (Result<OTPlessIntelligenceResult, OTPlessIntelligenceError>) -> Void
    ) {
        guard DeviceIntelligenceManager.shared.sdkInitialized else {
            completion(.failure(.notConfigured))
            return
        }

        DeviceIntelligenceManager.shared.getScore { response, error in
            if let response {
                let dto = Self.mapToDTO(response)
                let rawJson = Self.buildRawJSON(from: response)
                let result = OTPlessIntelligenceResult(response: dto, rawJson: rawJson)
                completion(.success(result))
            } else if let error {
                completion(.failure(.intelligenceError(
                    requestId: error.requestId,
                    message: error.errorMessage
                )))
            } else {
                completion(.failure(.unknown))
            }
        }
    }

    // MARK: - Internal helpers

    /// Generic JSON round-trip: IdentityFraud.* -> OTPless DTO
    private static func convert<Source: Encodable, Target: Decodable>(
        _ value: Source?
    ) -> Target? {
        guard let value else { return nil }
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        guard let data = try? encoder.encode(value) else { return nil }
        return try? decoder.decode(Target.self, from: data)
    }

    // MARK: - Internal mappers

    private static func mapToDTO(_ r: IntelligenceResponse) -> OTPlessIntelligenceResponse {
        OTPlessIntelligenceResponse(
            requestId: r.requestId ?? "",
            deviceId: r.deviceId ?? "",
            ip: r.ip ?? "",
            simulator: r.simulator?.boolValue ?? false,
            jailbroken: r.jailbroken?.boolValue ?? false,
            vpn: r.vpn?.boolValue ?? false,
            geoSpoofed: r.geoSpoofed?.boolValue ?? false,
            appTampering: r.appTampering?.boolValue ?? false,
            hooking: r.hooking?.boolValue ?? false,
            proxy: r.proxy?.boolValue ?? false,
            mirroredScreen: r.mirroredScreen?.boolValue ?? false,
            cloned: r.cloned?.boolValue ?? false,
            newDevice: r.newDevice?.boolValue ?? false,
            factoryReset: r.factoryReset?.boolValue ?? false,
            factoryResetTime: r.factoryResetTime?.intValue ?? 0,
            gpsLocation: convert(r.gpsLocation),
            ipDetails: convert(r.ipDetails),
            deviceMeta: convert(r.deviceMeta)
        )
    }

    /// Full raw JSON from  `IntelligenceResponse` (includes all fields/nested objects).
    private static func buildRawJSON(from response: IntelligenceResponse) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]

        if let data = try? encoder.encode(response),
           let json = String(data: data, encoding: .utf8) {
            return json
        } else {
            return "{\"message\":\"Failed to encode IntelligenceResponse\"}"
        }
    }
}
