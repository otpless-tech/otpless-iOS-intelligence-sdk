//
//  File.swift
//  otpless-ios-intelligence-sdk
//
//  Created by Shail Gupta on 08/12/25.
//

import Foundation

import Security


internal final class SessionMgr : @unchecked Sendable {
    static let shared = SessionMgr()
    init() {}
    private var inid: String?
    private var state: String?
    private var tsid: String = ""
    private var token: String = ""
    private var asid: String = ""
    
    func initialize() {
        generateTrackingId()
        initStateIfPresent()
    }
    
    private func initStateIfPresent(){
        if let savedState: String = SecureStorage.shared.retrieve(key: Constants.STATE_KEY) {
            self.state = savedState
        }
    }
    
    func getState() -> String? {
        return state
    }
    
    func setTsid(_ tsid: String) {
        self.tsid = tsid
    }
    
    func setState(_ state: String) {
        self.state = state
        SecureStorage.shared.save(key: Constants.STATE_KEY, value: state)
    }
    
    func getTsid() -> String {
        return tsid
    }
    
    func getInid() -> String? {
        return inid
    }
    
    func getToken() -> String {
        return token
    }
    
    func setToken(_ token: String) {
        self.token = token
    }
    
    func getAsid() -> String {
        return asid
    }
    
    func setasid(_ asid: String) {
        self.asid = asid
    }
    
    func generateTrackingId() {
        if let savedInid: String = SecureStorage.shared.getFromUserDefaults(key: Constants.INID_KEY, defaultValue: "") {
            self.inid = savedInid
        } else {
            inid = generateId(withTimeStamp: true)
            if let inidValue = inid{
                SecureStorage.shared.saveToUserDefaults(key: Constants.INID_KEY, value: inid!)
            }
        }
        
        if tsid.isEmpty {
            if let cls = NSClassFromString("OtplessBM.Otpless") as? NSObject.Type {
                let sharedSelector = NSSelectorFromString("shared")

                guard cls.responds(to: sharedSelector),
                      let sharedObj = cls.perform(sharedSelector)?.takeUnretainedValue() as? NSObject
                else {
                    return
                }

                let gettsIDSelector = NSSelectorFromString("gettsID")

                if sharedObj.responds(to: gettsIDSelector),
                   let tsidValue = sharedObj.perform(gettsIDSelector)?.takeUnretainedValue() as? String {
                    tsid = !tsidValue.isEmpty ? tsidValue : generateId(withTimeStamp: true)
                    return
                }
            }

            tsid = generateId(withTimeStamp: true)
        }
    }
    
    private func generateId(withTimeStamp: Bool) -> String {
        let uuid = UUID().uuidString
        if !withTimeStamp {
            return uuid
        }
        let timestamp = Int(Date().timeIntervalSince1970)
        let uniqueString = "\(uuid)-\(timestamp)"
        return uniqueString
    }
    
    func getInstallationId() -> String? {
        if inid != nil {
            return inid
        }
        let savedInid: String = SecureStorage.shared.getFromUserDefaults(key: Constants.INID_KEY, defaultValue: "")
        return savedInid
    }

}

internal final class SecureStorage: @unchecked Sendable {
    static let shared = SecureStorage()
    private let service = "com.otpless.bmum.secure"
    
    func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else {
            return
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary) // Delete before adding a new entry
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
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            return nil
        }
        
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return value
    }
    
    func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            return
        }
    }
    
    func clearAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
    }
    
    func saveToUserDefaults<T>(key: String, value: T) {
        UserDefaults.standard.set(value, forKey: key)
    }
    
    func getFromUserDefaults<T>(key: String, defaultValue: T) -> T {
        return UserDefaults.standard.object(forKey: key) as? T ?? defaultValue
    }
}

internal struct Constants {
    // MARK: - Keychain & UserDefault keys
    static let STATE_KEY = "otpless_bm_state"
    static let INID_KEY = "otpless_bm_inid"
    
}
