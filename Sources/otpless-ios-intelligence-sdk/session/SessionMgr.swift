import Foundation
import Security
import UIKit

internal final class SessionMgr: @unchecked Sendable {
    static let shared = SessionMgr()
    init() {}

    private var inid: String?
    private var rsid: String?
    private var state: String?
    private var tsid: String = ""
    private var token: String = ""
    private var asid: String = ""

    // Cached on initialize() which is always called from the main thread (app launch).
    // Avoids accessing UIDevice.current (main-actor isolated) from background threads.
    private(set) var vendorId: String = ""

    // MARK: - Initialize
    // Values in `context` take priority over auto-generated or persisted values.
    // Any ID absent from the context is filled in automatically.
    func initialize(from context: OTPlessSessionContext? = nil) {
        // Cache IDFV here — configure() is always called from the main thread.
        vendorId = UIDevice.current.identifierForVendor?.uuidString ?? ""

        // Apply external overrides first so generateTrackingId() skips filled fields.
        if let v = context?.inId, !v.isEmpty {
            self.inid = v
            SecureStorage.shared.saveToUserDefaults(key: Constants.INID_KEY, value: v)
        }
        if let v = context?.tsId, !v.isEmpty {
            self.tsid = v
        }
        if let v = context?.rsId, !v.isEmpty {
            self.rsid = v
        }

        // Fill any IDs not provided in context
        generateTrackingId()

        // State: context overrides Keychain; otherwise restore from Keychain
        if let v = context?.state, !v.isEmpty {
            self.state = v
            SecureStorage.shared.save(key: Constants.STATE_KEY, value: v)
        } else {
            initStateIfPresent()
        }
    }

    // MARK: - Getters / Setters

    func getTsid() -> String { tsid }
    func setTsid(_ tsid: String) { self.tsid = tsid }

    func getInid() -> String? { inid }

    func getRsid() -> String? { rsid }
    func setRsid(_ rsid: String) { self.rsid = rsid }

    func getState() -> String? { state }
    func setState(_ state: String) {
        self.state = state
        SecureStorage.shared.save(key: Constants.STATE_KEY, value: state)
    }

    func getToken() -> String { token }
    func setToken(_ token: String) { self.token = token }

    func getAsid() -> String { asid }
    func setasid(_ asid: String) { self.asid = asid }

    func getInstallationId() -> String? {
        if let inid { return inid }
        return SecureStorage.shared.getFromUserDefaults(key: Constants.INID_KEY, defaultValue: "")
    }

    // MARK: - Private helpers

    // Only fills fields that are still empty — does NOT overwrite externally set values.
    private func generateTrackingId() {
        // inId: restore from UserDefaults or generate new, only if not set externally
        if inid == nil || inid!.isEmpty {
            let saved: String = SecureStorage.shared.getFromUserDefaults(
                key: Constants.INID_KEY, defaultValue: ""
            )
            if !saved.isEmpty {
                self.inid = saved
            } else {
                let newInid = generateId(withTimeStamp: true)
                self.inid = newInid
                SecureStorage.shared.saveToUserDefaults(key: Constants.INID_KEY, value: newInid)
            }
        }

        // tsId: only generate if not set externally
        guard tsid.isEmpty else { return }

        // Try to reuse tsId from OTPless Auth SDK (OtplessBM) if present
        if let cls = NSClassFromString("OtplessBM.Otpless") as? NSObject.Type {
            let sharedSelector = NSSelectorFromString("shared")
            guard cls.responds(to: sharedSelector),
                  let sharedObj = cls.perform(sharedSelector)?.takeUnretainedValue() as? NSObject
            else {
                tsid = generateId(withTimeStamp: true)
                return
            }
            let gettsIDSelector = NSSelectorFromString("gettsID")
            if sharedObj.responds(to: gettsIDSelector),
               let tsidValue = sharedObj.perform(gettsIDSelector)?.takeUnretainedValue() as? String,
               !tsidValue.isEmpty {
                tsid = tsidValue
                return
            }
        }

        tsid = generateId(withTimeStamp: true)
    }

    private func initStateIfPresent() {
        if let saved = SecureStorage.shared.retrieve(key: Constants.STATE_KEY) {
            self.state = saved
        }
    }

    private func generateId(withTimeStamp: Bool) -> String {
        let uuid = UUID().uuidString
        guard withTimeStamp else { return uuid }
        return "\(uuid)-\(Int(Date().timeIntervalSince1970))"
    }
}

// MARK: - SecureStorage

internal final class SecureStorage: @unchecked Sendable {
    static let shared = SecureStorage()
    private let service = "com.otpless.bmum.secure"

    func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    func retrieve(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return nil }
        return value
    }

    func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    func clearAll() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service]
        SecItemDelete(query as CFDictionary)
    }

    func saveToUserDefaults<T>(key: String, value: T) {
        UserDefaults.standard.set(value, forKey: key)
    }

    func getFromUserDefaults<T>(key: String, defaultValue: T) -> T {
        return UserDefaults.standard.object(forKey: key) as? T ?? defaultValue
    }
}

// MARK: - Constants

internal struct Constants {
    static let STATE_KEY = "otpless_bm_state"
    static let INID_KEY  = "otpless_bm_inid"
}
