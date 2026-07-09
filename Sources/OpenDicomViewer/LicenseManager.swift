// LicenseManager.swift
// OpenDicomViewer
//
// Brainok Store activation, 30-day trial state, and offline Keychain storage.
// Licensed under the MIT License. See LICENSE for details.

import AppKit
import CryptoKit
import Foundation
import Security

enum LicenseStatus: Equatable {
    case trial(daysRemaining: Int)
    case activated(plan: String?)
    case expired
}

struct BrainokActivationPayload: Codable {
    let licenseCode: String
    let licenseId: String?
    let plan: String?
    let deviceId: String
    let activatedAt: String
    let source: String
}

private struct SignedLicensePayload: Codable {
    let productId: String
    let licenseId: String
    let licenseType: String
    let issuedAt: Date
    let expiresAt: Date?
    let ownerName: String?
    let ownerEmail: String?
    let deviceId: String?

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date() > expiresAt
    }
}

@MainActor
final class LicenseManager: ObservableObject {
    static let appId = "smart-dicom-viewer"
    static let appName = "Smart DICOM Viewer"

    private static let signedCodePrefix = "BRAINOK-SMART-DICOM-VIEWER-V1"
    private static let publicKeyBase64 = "0eLIkWCRo9QjgP3PTgwWFk7lK05o8SrG1gzUhNp9xpA="
    private static let activationURL = URL(string: "https://asia-northeast3-braionk-lab.cloudfunctions.net/activateBrainokLicense")!
    private static let trialDays = 30
    private static let firstLaunchKey = "brainok.firstLaunchDate"
    nonisolated private static let deviceIdCacheKey = "brainok.deviceIdCache"
    private static let supportEmail = "brainok777@gmail.com"
    private static let legacyOfflineCodes: Set<String> = [
        "BRAINOK-SEVERANCE-2026",
        "XJD2-FBYT-F6QA"
    ]

    @Published private(set) var status: LicenseStatus = .trial(daysRemaining: LicenseManager.trialDays)
    @Published private(set) var deviceId: String = ""
    @Published var showActivation = false
    @Published var activationError: String?
    @Published var isActivating = false
    private var refreshTask: Task<Void, Never>?

    var isActivated: Bool {
        if case .activated = status { return true }
        return false
    }

    var requiresActivation: Bool {
        status == .expired
    }

    var statusText: String {
        switch status {
        case .activated(let plan):
            if let plan, !plan.isEmpty {
                return "Activated (\(plan))"
            }
            return "Activated"
        case .trial(let daysRemaining):
            return "Trial active: \(daysRemaining) day\(daysRemaining == 1 ? "" : "s") remaining"
        case .expired:
            return "Trial expired. Activation is required."
        }
    }

    init() {
        deviceId = UserDefaults.standard.string(forKey: Self.deviceIdCacheKey) ?? ""
        ensureFirstLaunchDate()
        refresh()
    }

    func refresh() {
        status = Self.currentTrialStatus()
        if status == .expired {
            showActivation = true
        }

        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            let (resolvedDeviceId, payload) = await Task.detached(priority: .utility) {
                (Self.loadOrCreateDeviceId(), Self.loadActivationPayload())
            }.value

            guard let self, !Task.isCancelled else { return }
            self.deviceId = resolvedDeviceId
            UserDefaults.standard.set(resolvedDeviceId, forKey: Self.deviceIdCacheKey)

            if let payload, payload.deviceId == resolvedDeviceId {
                self.status = .activated(plan: payload.plan)
                self.showActivation = false
                return
            }

            self.status = Self.currentTrialStatus()
            if self.status == .expired {
                self.showActivation = true
            }
        }
    }

    private static func currentTrialStatus() -> LicenseStatus {
        let firstLaunch = UserDefaults.standard.object(forKey: Self.firstLaunchKey) as? Date ?? Date()
        let elapsedDays = Calendar.current.dateComponents([.day], from: firstLaunch, to: Date()).day ?? 0
        let remaining = max(0, Self.trialDays - elapsedDays)
        return remaining > 0 ? .trial(daysRemaining: remaining) : .expired
    }

    func activate(code rawCode: String) async {
        let code = Self.normalizedCode(rawCode)
        guard !code.isEmpty else {
            activationError = "A valid Brainok license code is required."
            return
        }

        activationError = nil
        isActivating = true
        defer { isActivating = false }
        await resolveDeviceIdIfNeeded()

        if activateExistingOfflineCode(code) {
            publishLicenseStateChangeOnMainThread()
            return
        }

        do {
            if let payload = try activateExistingSignedCode(code) {
                try Self.saveActivationPayload(payload)
                publishLicenseStateChangeOnMainThread()
                return
            }
        } catch {
            activationError = error.localizedDescription
            return
        }

        do {
            let payload = try await activateBrainokLicenseWithFirebase(code: code)
            try Self.saveActivationPayload(payload)
            publishLicenseStateChangeOnMainThread()
        } catch {
            activationError = error.localizedDescription
        }
    }

    func copyDeviceIdToPasteboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(deviceId, forType: .string)
    }

    func openSupportEmail() {
        if let url = URL(string: "mailto:\(Self.supportEmail)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func activateExistingOfflineCode(_ code: String) -> Bool {
        guard Self.legacyOfflineCodes.contains(code) else { return false }
        let payload = BrainokActivationPayload(
            licenseCode: code,
            licenseId: nil,
            plan: "legacy",
            deviceId: deviceId,
            activatedAt: ISO8601DateFormatter().string(from: Date()),
            source: "legacy_offline_code"
        )
        do {
            try Self.saveActivationPayload(payload)
            return true
        } catch {
            activationError = error.localizedDescription
            return false
        }
    }

    private func activateExistingSignedCode(_ code: String) throws -> BrainokActivationPayload? {
        guard let signedPayload = try verifiedSignedPayload(from: code) else { return nil }
        guard signedPayload.productId == Self.appId else {
            throw ActivationError("This Activation Code is not for this app.")
        }
        guard !signedPayload.isExpired else {
            throw ActivationError("This Activation Code has expired.")
        }
        if let expectedDeviceId = signedPayload.deviceId, expectedDeviceId != deviceId {
            throw ActivationError("This code is not for this Mac. Required Device ID: \(expectedDeviceId)")
        }

        return BrainokActivationPayload(
            licenseCode: code,
            licenseId: signedPayload.licenseId,
            plan: signedPayload.licenseType,
            deviceId: deviceId,
            activatedAt: ISO8601DateFormatter().string(from: Date()),
            source: "signed_activation_code"
        )
    }

    private func activateBrainokLicenseWithFirebase(code: String) async throws -> BrainokActivationPayload {
        var request = URLRequest(url: Self.activationURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(CallableRequest(data: ActivationRequestData(
            licenseCode: code,
            deviceId: deviceId,
            deviceName: Host.current().localizedName ?? "Mac",
            appId: Self.appId,
            appName: Self.appName,
            os: "mac",
            appVersion: Self.appVersion
        )))

        let (data, _) = try await URLSession.shared.data(for: request)

        if let errorResponse = try? JSONDecoder().decode(CallableErrorResponse.self, from: data),
           let message = errorResponse.error?.message {
            throw ActivationError(message)
        }

        let response = try JSONDecoder().decode(CallableSuccessResponse.self, from: data)
        guard response.result.ok, response.result.activated else {
            throw ActivationError("Activation was not accepted.")
        }

        return BrainokActivationPayload(
            licenseCode: response.result.licenseCode ?? code,
            licenseId: response.result.licenseId,
            plan: response.result.plan,
            deviceId: response.result.deviceId ?? deviceId,
            activatedAt: response.result.activatedDate ?? ISO8601DateFormatter().string(from: Date()),
            source: "brainok_license"
        )
    }

    private func publishLicenseStateChangeOnMainThread() {
        refresh()
        showActivation = false
        NotificationCenter.default.post(name: .licenseStateDidChange, object: nil)
    }

    private func ensureFirstLaunchDate() {
        guard UserDefaults.standard.object(forKey: Self.firstLaunchKey) == nil else { return }
        UserDefaults.standard.set(Date(), forKey: Self.firstLaunchKey)
    }

    private func resolveDeviceIdIfNeeded() async {
        guard deviceId.isEmpty else { return }
        let resolved = await Task.detached(priority: .utility) {
            Self.loadOrCreateDeviceId()
        }.value
        deviceId = resolved
        UserDefaults.standard.set(resolved, forKey: Self.deviceIdCacheKey)
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0"
    }

    private static func normalizedCode(_ code: String) -> String {
        code
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .joined()
            .uppercased()
    }

    nonisolated private static func loadOrCreateDeviceId() -> String {
        if let data = Keychain.read(account: "device-id"),
           let value = String(data: data, encoding: .utf8),
           !value.isEmpty {
            UserDefaults.standard.set(value, forKey: deviceIdCacheKey)
            return value
        }

        let value = String(UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .prefix(12)
            .uppercased())
        try? Keychain.save(Data(value.utf8), account: "device-id")
        UserDefaults.standard.set(value, forKey: deviceIdCacheKey)
        return value
    }

    nonisolated private static func loadActivationPayload() -> BrainokActivationPayload? {
        guard let data = Keychain.read(account: "activation-payload") else { return nil }
        return try? JSONDecoder().decode(BrainokActivationPayload.self, from: data)
    }

    nonisolated private static func saveActivationPayload(_ payload: BrainokActivationPayload) throws {
        let data = try JSONEncoder().encode(payload)
        try Keychain.save(data, account: "activation-payload")
    }

    private func verifiedSignedPayload(from rawCode: String) throws -> SignedLicensePayload? {
        let parts = rawCode.components(separatedBy: ".")
        guard parts.count == 3 else { return nil }
        guard parts[0] == Self.signedCodePrefix else { return nil }

        let payloadToken = parts[1]
        let signatureToken = parts[2]
        guard let payloadData = Data(base64URLEncoded: payloadToken),
              let signature = Data(base64URLEncoded: signatureToken),
              let signingData = payloadToken.data(using: .utf8),
              let publicKeyData = Data(base64Encoded: Self.publicKeyBase64),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData) else {
            throw ActivationError("The Activation Code format is not valid.")
        }

        guard publicKey.isValidSignature(signature, for: signingData) else {
            throw ActivationError("The Activation Code is not valid.")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(SignedLicensePayload.self, from: payloadData) else {
            throw ActivationError("The Activation Code format is not valid.")
        }

        return payload
    }
}

extension Notification.Name {
    static let licenseStateDidChange = Notification.Name("brainokLicenseStateDidChange")
}

private struct CallableRequest: Encodable {
    let data: ActivationRequestData
}

private struct ActivationRequestData: Encodable {
    let licenseCode: String
    let deviceId: String
    let deviceName: String
    let appId: String
    let appName: String
    let os: String
    let appVersion: String
}

private struct CallableSuccessResponse: Decodable {
    let result: ActivationResult
}

private struct ActivationResult: Decodable {
    let ok: Bool
    let activated: Bool
    let activatedDate: String?
    let licenseId: String?
    let licenseCode: String?
    let plan: String?
    let deviceId: String?
}

private struct CallableErrorResponse: Decodable {
    let error: CallableError?
}

private struct CallableError: Decodable {
    let message: String
    let status: String?
}

private struct ActivationError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}

private enum Keychain {
    private static let service = "net.brainok.smart-dicom-viewer.activation"

    static func read(account: String) -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    static func save(_ data: Data, account: String) throws {
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw ActivationError("Could not save activation to Keychain (\(addStatus)).")
        }
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

private extension Data {
    init?(base64URLEncoded value: String) {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        base64.append(String(repeating: "=", count: padding))
        self.init(base64Encoded: base64)
    }
}
