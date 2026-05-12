import Foundation
import IdentityFraud

// MARK: - OTPlessSessionContext

/// Optional session identifiers that the host app or OTPless Auth SDK can supply
/// at configure time. Any value provided here overrides the SDK's auto-generated
/// or persisted equivalent. Values not provided are filled in automatically.
@objcMembers
public class OTPlessSessionContext: NSObject {
    /// Request/session identifier from an upstream flow (e.g. OTPless Auth SDK).
    public let rsId: String?
    /// Installation identifier. Stable across sessions for a given device install.
    public let inId: String?
    /// Tracking session identifier. Ties intelligence events to a single user session.
    public let tsId: String?
    /// Server-issued state token for request correlation.
    public let state: String?

    public init(
        rsId: String? = nil,
        inId: String? = nil,
        tsId: String? = nil,
        state: String? = nil
    ) {
        self.rsId = rsId
        self.inId = inId
        self.tsId = tsId
        self.state = state
        super.init()
    }

    public override var description: String {
        "OTPlessSessionContext(rsId=\(rsId ?? "nil"), inId=\(inId ?? "nil"), tsId=\(tsId ?? "nil"), state=\(state ?? "nil"))"
    }
}

// MARK: - Public Error Type

public enum OTPlessIntelligenceError: Error {
    /// `configure(appID:)` was never successfully called
    case notConfigured

    /// SDK returned an error
    case intelligenceError(requestId: String, message: String)

    /// Unexpected nil / inconsistent state
    case unknown
}

// MARK: - GPSLocation log helper

extension GPSLocation {
    @objc public var logDescription: String {
        "GPSLocation(lat=\(latitude ?? -1), lon=\(longitude ?? -1), alt=\(altitude ?? -1))"
    }
}

// MARK: - IPDetails log helper

extension IPDetails {
    @objc public var logDescription: String {
        """
        IPDetails(
          ipCity=\(city ?? "nil"),
          ipRegion=\(region ?? "nil"),
          ipCountry=\(country ?? "nil"),
          isp=\(isp ?? "nil"),
          asn=\(asn ?? "nil"),
          lat=\(latitude ?? -1),
          lon=\(longitude ?? -1),
          fraudScore=\(fraudScore ?? -1)
        )
        """
    }
}

// MARK: - DeviceMeta log helper

extension DeviceMeta {
    @objc public var logDescription: String {
        """
        DeviceMeta(
          brand=\(brand ?? "nil"),
          model=\(model ?? "nil"),
          product=\(product ?? "nil"),
          cpuType=\(cpuType ?? "nil"),
          iOSVersion=\(iOSVersion ?? "nil"),
          screenResolution=\(screenResolution ?? "nil"),
          totalRAM=\(totalRAM ?? "nil"),
          storageAvailable=\(storageAvailable ?? "nil"),
          storageTotal=\(storageTotal ?? "nil")
        )
        """
    }
}

// MARK: - AppAnalytics log helper

extension AppAnalytics {
    @objc public var logDescription: String {
        let topAffinities: String
        if let affinity, !affinity.isEmpty {
            let sorted = affinity.sorted { $0.value > $1.value }.prefix(5)
            topAffinities = sorted
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ", ")
        } else {
            topAffinities = "none"
        }
        return "AppAnalytics(affinity=[\(topAffinities)])"
    }
}

// MARK: - OTPlessRuleAction

/// Server-side rule decision returned alongside the intelligence response.
/// Tells the app what action to take (e.g. block, challenge) and why.
@objcMembers
public class OTPlessRuleAction: NSObject, Codable {
    public let action: String?
    public let name: String?
    public let ruleDescription: String?
    public let message: String?

    public init(
        action: String?,
        name: String?,
        ruleDescription: String?,
        message: String?
    ) {
        self.action = action
        self.name = name
        self.ruleDescription = ruleDescription
        self.message = message
        super.init()
    }

    public required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.action = try c.decodeIfPresent(String.self, forKey: .action)
        self.name = try c.decodeIfPresent(String.self, forKey: .name)
        self.ruleDescription = try c.decodeIfPresent(String.self, forKey: .ruleDescription)
        self.message = try c.decodeIfPresent(String.self, forKey: .message)
        super.init()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(action, forKey: .action)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(ruleDescription, forKey: .ruleDescription)
        try c.encodeIfPresent(message, forKey: .message)
    }

    private enum CodingKeys: String, CodingKey {
        case action, name, ruleDescription, message
    }

    public override var description: String {
        "OTPlessRuleAction(action=\(action ?? "nil"), name=\(name ?? "nil"), message=\(message ?? "nil"))"
    }
}

// MARK: - OTPlessIntelligenceResponse

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

    public let gpsLocation: GPSLocation?
    public let ipDetails: IPDetails?
    public let deviceMeta: DeviceMeta?

    /// Server-side rule decision. Present only when the backend has rules configured.
    public let ruleAction: OTPlessRuleAction?

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
        deviceMeta: DeviceMeta?,
        ruleAction: OTPlessRuleAction?
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
        self.ruleAction = ruleAction
        super.init()
    }

    public required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.requestId = try c.decode(String.self, forKey: .requestId)
        self.deviceId = try c.decode(String.self, forKey: .deviceId)
        self.ip = try c.decode(String.self, forKey: .ip)
        self.simulator = try c.decode(Bool.self, forKey: .simulator)
        self.jailbroken = try c.decode(Bool.self, forKey: .jailbroken)
        self.vpn = try c.decode(Bool.self, forKey: .vpn)
        self.geoSpoofed = try c.decode(Bool.self, forKey: .geoSpoofed)
        self.appTampering = try c.decode(Bool.self, forKey: .appTampering)
        self.hooking = try c.decode(Bool.self, forKey: .hooking)
        self.proxy = try c.decode(Bool.self, forKey: .proxy)
        self.mirroredScreen = try c.decode(Bool.self, forKey: .mirroredScreen)
        self.cloned = try c.decode(Bool.self, forKey: .cloned)
        self.newDevice = try c.decode(Bool.self, forKey: .newDevice)
        self.factoryReset = try c.decode(Bool.self, forKey: .factoryReset)
        self.factoryResetTime = try c.decode(Int.self, forKey: .factoryResetTime)
        self.gpsLocation = try c.decodeIfPresent(GPSLocation.self, forKey: .gpsLocation)
        self.ipDetails = try c.decodeIfPresent(IPDetails.self, forKey: .ipDetails)
        self.deviceMeta = try c.decodeIfPresent(DeviceMeta.self, forKey: .deviceMeta)
        self.ruleAction = try c.decodeIfPresent(OTPlessRuleAction.self, forKey: .ruleAction)
        super.init()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(requestId, forKey: .requestId)
        try c.encode(deviceId, forKey: .deviceId)
        try c.encode(ip, forKey: .ip)
        try c.encode(simulator, forKey: .simulator)
        try c.encode(jailbroken, forKey: .jailbroken)
        try c.encode(vpn, forKey: .vpn)
        try c.encode(geoSpoofed, forKey: .geoSpoofed)
        try c.encode(appTampering, forKey: .appTampering)
        try c.encode(hooking, forKey: .hooking)
        try c.encode(proxy, forKey: .proxy)
        try c.encode(mirroredScreen, forKey: .mirroredScreen)
        try c.encode(cloned, forKey: .cloned)
        try c.encode(newDevice, forKey: .newDevice)
        try c.encode(factoryReset, forKey: .factoryReset)
        try c.encode(factoryResetTime, forKey: .factoryResetTime)
        try c.encodeIfPresent(gpsLocation, forKey: .gpsLocation)
        try c.encodeIfPresent(ipDetails, forKey: .ipDetails)
        try c.encodeIfPresent(deviceMeta, forKey: .deviceMeta)
        try c.encodeIfPresent(ruleAction, forKey: .ruleAction)
    }

    private enum CodingKeys: String, CodingKey {
        case requestId, deviceId, ip
        case simulator, jailbroken, vpn, geoSpoofed, appTampering
        case hooking, proxy, mirroredScreen, cloned, newDevice
        case factoryReset, factoryResetTime
        case gpsLocation, ipDetails, deviceMeta, ruleAction
    }

    public override var description: String {
        """
        OTPlessIntelligenceResponse(
          requestId=\(requestId),
          deviceId=\(deviceId),
          ip=\(ip),
          simulator=\(simulator),
          jailbroken=\(jailbroken),
          vpn=\(vpn),
          geoSpoofed=\(geoSpoofed),
          appTampering=\(appTampering),
          hooking=\(hooking),
          proxy=\(proxy),
          mirroredScreen=\(mirroredScreen),
          cloned=\(cloned),
          newDevice=\(newDevice),
          factoryReset=\(factoryReset),
          factoryResetTime=\(factoryResetTime),
          gpsLocation=\(gpsLocation?.logDescription ?? "nil"),
          ipDetails=\(ipDetails?.logDescription ?? "nil"),
          deviceMeta=\(deviceMeta?.logDescription ?? "nil"),
          ruleAction=\(ruleAction?.description ?? "nil")
        )
        """
    }
}

// MARK: - OTPlessIntelligenceResult

public struct OTPlessIntelligenceResult {
    public let response: OTPlessIntelligenceResponse

    public init(response: OTPlessIntelligenceResponse) {
        self.response = response
    }
}

// MARK: - OTPlessIntelligence (Public Facade)

@objc public final class OTPlessIntelligence: NSObject, @unchecked Sendable {

    @objc public static let shared = OTPlessIntelligence()
    var merchantAppId = ""
    override init() {}

    // MARK: - Configure

    /// Initialises the SDK.
    ///
    /// - `appID` is the only required parameter.
    /// - `sessionContext` is optional. Pass an `OTPlessSessionContext` when you already
    ///   have session identifiers (e.g. from the OTPless Auth SDK). Any ID provided
    ///   overrides the SDK's auto-generated or persisted value. IDs not provided are
    ///   filled in automatically.
    @available(iOS 15.0, *)
    public func configure(
        appID: String,
        sessionContext: OTPlessSessionContext? = nil,
        completion: @escaping (Bool) -> Void
    ) {
        guard !appID.isEmpty else {
            completion(false)
            return
        }
        merchantAppId = appID
        SessionMgr.shared.initialize(from: sessionContext)
        DeviceIntelligenceManager.shared.initialize(completion: completion)
    }

    // MARK: - Update Options

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

    // MARK: - Fetch Intelligence

    @available(iOS 15.0, *)
    public func fetchIntelligence(
        completion: @escaping (Result<OTPlessIntelligenceResult, OTPlessIntelligenceError>) -> Void
    ) {
        guard DeviceIntelligenceManager.shared.sdkInitialized else {
            completion(.failure(.intelligenceError(
                requestId: SessionMgr.shared.getTsid(),
                message: "OTPless Intelligence SDK is not configured"
            )))
            return
        }

        DeviceIntelligenceManager.shared.getScore { response, error in
            if let response {
                let dto = Self.mapToDTO(response)
                completion(.success(OTPlessIntelligenceResult(response: dto)))
            } else if let error {
                completion(.failure(.intelligenceError(
                    requestId: error.requestId,
                    message: error.errorMessage
                )))
            } else {
                completion(.failure(.intelligenceError(
                    requestId: SessionMgr.shared.getTsid(),
                    message: "Unknown intelligence error"
                )))
            }
        }
    }

    // MARK: - Auth Session Link

    @objc(updateAuthSessionWithIntelligence:)
    public func updateAuthSessionWithIntelligence(authMap: [String: String]) {
        DeviceIntelligenceManager.shared.updateAuthMap(authMap: authMap)
    }

    @objc public func gettsID() -> String {
        return SessionMgr.shared.getTsid()
    }

    // MARK: - Internal Mappers

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
            deviceMeta: convert(r.deviceMeta),
            ruleAction: convert(r.ruleAction)
        )
    }

    /// JSON round-trip converter: IdentityFraud type → OTPless public type
    private static func convert<Source: Encodable, Target: Decodable>(_ value: Source?) -> Target? {
        guard let value else { return nil }
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(Target.self, from: data)
    }
}
