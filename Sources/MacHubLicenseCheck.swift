import Foundation
import CryptoKit
import Security

/// MacHub Pro licensing. Structurally a direct port of mac-cleanup's
/// `MacGroomLicenseCheck.swift` (the DESIGN-SYSTEM.md-mandated template) —
/// same Polar.sh customer-portal License Keys API, same Keychain-backed
/// tamper-evident cache, same `VerifyLock` serialization. NOT a shared
/// package: MacHub is a separate Lemon-Squeezy-era-name-but-now-Polar
/// product from MacGroom, with its own organization ID and its own
/// Keychain service name, so this file is intentionally a standalone copy
/// rather than a dependency on `macgroom-license-check` (that package is
/// stale/unmaintained — see its own note — and mac-cleanup no longer uses
/// Lemon Squeezy at all).
///
/// ============================================================
/// TODO — Lemon Squeezy dashboard / Polar setup, before this ships:
/// ============================================================
/// 1. Create a "MacHub Pro" product in Polar.sh (polar.sh/dashboard) —
///    a separate product from MacGroom Pro, since this is a separate app.
/// 2. Configure it with a License Keys benefit (Settings → Benefits →
///    License Keys), same as MacGroom Pro's. Leave "Limit Activations" and
///    "Limit Usage" off, matching MacGroom's — this integration assumes no
///    `/activate` step, just repeated `/validate` calls (see
///    `LicenseChecker.verify` below).
/// 3. Copy the new product's organization ID and replace
///    `MacHubLicenseConfig.organizationId` below (currently a placeholder,
///    NOT a real ID — every verify() call will 404 until this is filled in).
/// 4. Set `MacHubLicenseConfig.purchaseURL` to the real Polar checkout
///    link for MacHub Pro once the product/price is published.
/// 5. Smoke-test end-to-end with a real test-mode key, the same way
///    MacGroom's integration was verified live (2026-09-05) before trusting
///    this in production — see this file's `validateRemote` doc comment.
enum MacHubLicenseConfig {
    /// TODO: replace with MacHub Pro's real Polar.sh organization ID once
    /// that product exists. This placeholder will 404 on every check.
    static let organizationId = "TODO_POLAR_ORG_ID_MACHUB_PRO"

    /// TODO: replace with the real Polar checkout URL for MacHub Pro.
    static let purchaseURL = "https://TODO-polar-checkout-url-for-machub-pro"

    /// Bundle-id-scoped `@AppStorage` key for the stored license key —
    /// matches `com.rajeshsood.machub` from Info.plist/build.sh.
    static let licenseKeyStorageKey = "com.rajeshsood.machub.licenseKey"

    /// False until both TODOs above are filled in with real values. Checked
    /// before every verify attempt and before offering the purchase link,
    /// so a not-yet-configured product fails with a distinct, honest
    /// message ("isn't available for purchase yet") instead of the normal
    /// "invalid license key" a real customer's real key would otherwise
    /// see once this org exists but is still misconfigured — see
    /// `LicenseCheckError.notYetConfigured`.
    static var isConfigured: Bool {
        !organizationId.hasPrefix("TODO") && !purchaseURL.contains("TODO")
    }
}

/// Local, tamper-evident cache for verified license state. See
/// mac-cleanup's `SecureLicenseCache` doc comment for the full threat-model
/// writeup this mirrors: Keychain instead of `UserDefaults` (not writable
/// via `defaults`/`plutil`), plus an HMAC-SHA256 tag over the cached
/// payload so a forged blob written by any means fails the tag check and
/// forces re-verification instead of being trusted.
private enum SecureLicenseCache {
    private static let licenseService = "com.rajeshsood.machub.license.cache.v1"

    /// Byte-masked so the real secret doesn't sit in the binary's strings
    /// table as plain readable text. This app's own key — deliberately
    /// distinct from MacGroom's, so a leak of one doesn't affect the other.
    private static var hmacKey: SymmetricKey {
        let masked: [UInt8] = [
            0x7a, 0x1c, 0x9e, 0x44, 0xd2, 0x6b, 0x83, 0x0f, 0x5a, 0xc7,
            0x91, 0x3d, 0x68, 0xbe, 0x27, 0xf4, 0x5c, 0x09, 0xa1, 0x76,
            0xe3, 0x4f, 0x88, 0x12, 0xd9
        ]
        let bytes = masked.enumerated().map { i, b in b ^ UInt8((i * 11 + 23) & 0xFF) }
        return SymmetricKey(data: Data(bytes))
    }

    private struct SignedPayload: Codable {
        let payload: Data
        let tag: Data
    }

    private struct CachedEnvelope: Codable {
        let cachedAt: Date
        let license: License
    }

    private static func computeTag(_ payload: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: payload, using: hmacKey))
    }

    static func readLicense(_ licenseKey: String) -> (Date, License)? {
        guard let data = keychainRead(service: licenseService, account: licenseKey) else { return nil }
        guard let signed = try? JSONDecoder().decode(SignedPayload.self, from: data) else { return nil }
        guard computeTag(signed.payload) == signed.tag else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let envelope = try? decoder.decode(CachedEnvelope.self, from: signed.payload) else { return nil }
        return (envelope.cachedAt, envelope.license)
    }

    static func writeLicense(_ licenseKey: String, _ license: License) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let payload = try? encoder.encode(CachedEnvelope(cachedAt: Date(), license: license)) else { return }
        let signed = SignedPayload(payload: payload, tag: computeTag(payload))
        guard let signedData = try? JSONEncoder().encode(signed) else { return }
        keychainWrite(service: licenseService, account: licenseKey, data: signedData)
    }

    static func clearLicense(_ licenseKey: String) {
        keychainDelete(service: licenseService, account: licenseKey)
    }

    static func clearAll() {
        keychainDeleteAll(service: licenseService)
    }

    // MARK: - Keychain primitives

    private static func keychainRead(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return data
    }

    private static func keychainWrite(service: String, account: String, data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard status == errSecItemNotFound else { return }
        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private static func keychainDelete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func keychainDeleteAll(service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Process-wide serialization for `LicenseChecker.verify()` calls, keyed
/// by license key — the main window and Settings each own an independent
/// `LicenseChecker` instance, so without this two concurrent `verify()`
/// calls for the same key would each independently hit the network.
private final class VerifyLock: @unchecked Sendable {
    static let shared = VerifyLock()

    private let lock = NSLock()
    private var inFlight: [String: Task<License, Error>] = [:]

    func run(key: String, _ operation: @escaping () async throws -> License) async throws -> License {
        let (task, isNew) = getOrCreate(key: key, operation: operation)
        defer { if isNew { clear(key) } }
        return try await task.value
    }

    private func getOrCreate(
        key: String,
        operation: @escaping () async throws -> License
    ) -> (task: Task<License, Error>, isNew: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if let existing = inFlight[key] {
            return (existing, false)
        }
        let task = Task { try await operation() }
        inFlight[key] = task
        return (task, true)
    }

    private func clear(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        inFlight[key] = nil
    }
}

/// Fire-and-forget telemetry for one `verify()` outcome — success or the
/// specific failure reason — reported to the same shared gogenops.com
/// backend MacGroom's checker uses (the endpoint takes no license key or
/// customer identity, just outcome/appVersion/os, so it's safe to reuse
/// across apps in the mac-apps line). Dispatched into a detached,
/// unawaited `Task` on a 3s timeout with any error silently discarded — a
/// failed or slow report must never be the reason a license check itself
/// appears to hang or throw.
private enum LicenseCheckOutcomeReporter {
    private struct Payload: Encodable {
        let outcome: String
        let appVersion: String
        let os: String
    }

    static func report(outcome: String) {
        guard let url = URL(string: "https://gogenops.com/api/license-check-outcome") else { return }

        let payload = Payload(
            outcome: outcome,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            os: ProcessInfo.processInfo.operatingSystemVersionString
        )
        guard let body = try? JSONEncoder().encode(payload) else { return }

        var mutableRequest = URLRequest(url: url)
        mutableRequest.httpMethod = "POST"
        mutableRequest.timeoutInterval = 3
        mutableRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        mutableRequest.httpBody = body
        let request = mutableRequest

        Task.detached {
            _ = try? await URLSession.shared.data(for: request)
        }
    }

    static func outcome(for error: Error) -> String {
        guard let licenseError = error as? LicenseCheckError else { return "unknown" }
        switch licenseError {
        case .invalidLicenseKey: return "invalidLicenseKey"
        case .networkError: return "networkError"
        case .invalidResponse: return "invalidResponse"
        case .licenseExpired: return "licenseExpired"
        case .licenseDisabled: return "licenseDisabled"
        case .activationLimitExceeded: return "activationLimitExceeded"
        case .activationFailed: return "activationFailed"
        case .codingError: return "codingError"
        case .unknown: return "unknown"
        case .wrongProduct: return "wrongProduct"
        case .notYetConfigured: return "notYetConfigured"
        }
    }
}

/// Error types for license verification.
enum LicenseCheckError: LocalizedError {
    case invalidLicenseKey
    case networkError(URLError)
    case invalidResponse
    case licenseExpired
    case licenseDisabled
    case activationLimitExceeded
    case activationFailed(String)
    case codingError(Error)
    case unknown(String)
    case wrongProduct
    case notYetConfigured

    var errorDescription: String? {
        switch self {
        case .notYetConfigured:
            return "MacHub Pro isn't available for purchase yet — check back soon."
        case .invalidLicenseKey:
            return "The license key is invalid or not recognized."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Received an invalid response from the license server."
        case .licenseExpired:
            return "This license has expired."
        case .licenseDisabled:
            return "This license has been disabled."
        case .activationLimitExceeded:
            return "This license has reached its activation limit."
        case .activationFailed(let message):
            return "Activation failed: \(message)"
        case .codingError(let error):
            return "Error processing license data: \(error.localizedDescription)"
        case .unknown(let message):
            return message
        case .wrongProduct:
            return "This license key isn't valid for MacHub."
        }
    }
}

/// Represents a verified license. `instanceId` is always nil under the
/// Polar integration — see mac-cleanup's `MacGroomLicenseCheck.swift` for
/// why (no per-device activation limits configured, so no activation step
/// to cache an instance from).
struct License: Codable, Equatable {
    let key: String
    let isValid: Bool
    let status: String?
    let expiresAt: Date?
    let activationLimit: Int?
    let activationUsage: Int?
    let instanceId: String?

    init(
        key: String,
        isValid: Bool,
        status: String? = nil,
        expiresAt: Date? = nil,
        activationLimit: Int? = nil,
        activationUsage: Int? = nil,
        instanceId: String? = nil
    ) {
        self.key = key
        self.isValid = isValid
        self.status = status
        self.expiresAt = expiresAt
        self.activationLimit = activationLimit
        self.activationUsage = activationUsage
        self.instanceId = instanceId
    }
}

/// MacHub Pro's license checking service.
///
/// Uses Polar.sh's customer-portal License Keys API
/// (`POST /v1/customer-portal/license-keys/validate`) — same endpoint
/// mac-cleanup's `LicenseChecker` uses for MacGroom Pro, confirmed there to
/// require no `Authorization` header: an unauthenticated request with a
/// well-formed body and a key that doesn't exist under the organization
/// returns `404`, not an auth error. That's by design (the client-safe
/// variant of the endpoint, meant to be called directly from an app like
/// this one) — embedding a real Polar API secret inside a distributed
/// macOS binary would be trivially extractable anyway.
///
/// MacHub Pro's license-key benefit is expected to have both "Limit
/// Activations" and "Limit Usage" turned off (see the TODO checklist at
/// the top of this file), so there's no `/activate` step and no
/// `activation_id`/`increment_usage` to track — every launch just
/// re-validates the raw key against the organization.
final class LicenseChecker {
    /// MacHub Pro's Polar.sh organization ID — see
    /// `MacHubLicenseConfig.organizationId` (TODO, currently a
    /// placeholder). Read from there rather than duplicated here so the
    /// one TODO comment at the top of this file is the single place to fix.
    private static var organizationId: String { MacHubLicenseConfig.organizationId }

    private let urlSession: URLSession

    init(urlSession: URLSession = URLSession.shared) {
        self.urlSession = urlSession
    }

    /// Verify a license key against Polar.
    func verify(
        licenseKey: String,
        useCache: Bool = true,
        cacheDuration: TimeInterval = 7 * 24 * 3600
    ) async throws -> License {
        // Fails distinctly and immediately, before touching the network or
        // the cache — see `MacHubLicenseConfig.isConfigured`'s doc comment.
        guard MacHubLicenseConfig.isConfigured else {
            throw LicenseCheckError.notYetConfigured
        }

        let trimmedKey = licenseKey.trimmingCharacters(in: .whitespaces)

        return try await VerifyLock.shared.run(key: trimmedKey) { [self] in
            if useCache, let cached = self.getCachedLicense(trimmedKey) {
                if Date().timeIntervalSince(cached.0) < cacheDuration {
                    return cached.1
                } else {
                    self.clearCache(trimmedKey)
                }
            }

            do {
                let license = try await self.validateRemote(trimmedKey)
                self.setCachedLicense(trimmedKey, license)
                LicenseCheckOutcomeReporter.report(outcome: "valid")
                return license
            } catch {
                LicenseCheckOutcomeReporter.report(outcome: LicenseCheckOutcomeReporter.outcome(for: error))
                throw error
            }
        }
    }

    /// Clear cached license for a key.
    func clearCache(_ licenseKey: String) {
        SecureLicenseCache.clearLicense(licenseKey)
    }

    /// Clear all cached licenses.
    func clearAllCache() {
        SecureLicenseCache.clearAll()
    }

    // MARK: - Private Methods

    private func validateRemote(_ licenseKey: String) async throws -> License {
        var request = URLRequest(url: URL(string: "https://api.polar.sh/v1/customer-portal/license-keys/validate")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "key": licenseKey,
            "organization_id": Self.organizationId
        ])

        let (data, httpResponse) = try await send(request)

        guard httpResponse.statusCode == 200 else {
            throw mapErrorResponse(status: httpResponse.statusCode, data: data)
        }

        struct PolarLicenseKeyResponse: Decodable {
            let key: String
            let status: String
            let limitActivations: Int?
            let usage: Int?
            let expiresAt: String?

            enum CodingKeys: String, CodingKey {
                case key, status, usage
                case limitActivations = "limit_activations"
                case expiresAt = "expires_at"
            }
        }

        let response = try decode(PolarLicenseKeyResponse.self, from: data)

        return License(
            key: response.key,
            isValid: true,
            status: response.status,
            expiresAt: response.expiresAt.flatMap { ISO8601DateFormatter().date(from: $0) },
            activationLimit: response.limitActivations,
            activationUsage: response.usage,
            instanceId: nil
        )
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw LicenseCheckError.invalidResponse
            }
            return (data, httpResponse)
        } catch let error as URLError {
            throw LicenseCheckError.networkError(error)
        } catch let error as LicenseCheckError {
            throw error
        } catch {
            throw LicenseCheckError.codingError(error)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw LicenseCheckError.codingError(error)
        }
    }

    /// Polar's error responses come in two shapes: a `404` with
    /// `{"error": "ResourceNotFound", "detail": "Not found"}` for a key
    /// that doesn't exist under this organization, and a `422` with
    /// `{"detail": [{"msg": "...", "loc": [...]}]}` for a malformed
    /// request.
    private func mapErrorResponse(status: Int, data: Data) -> LicenseCheckError {
        let message = errorMessage(from: data)
        switch status {
        case 404:
            return .invalidLicenseKey
        case 403, 401:
            return .licenseDisabled
        default:
            if let message {
                let lower = message.lowercased()
                if lower.contains("expired") {
                    return .licenseExpired
                } else if lower.contains("disabled") || lower.contains("revoked") {
                    return .licenseDisabled
                } else if lower.contains("activation limit") || lower.contains("usage limit") {
                    return .activationLimitExceeded
                }
            }
            return .unknown(message ?? "License check failed (HTTP \(status)).")
        }
    }

    private func errorMessage(from data: Data) -> String? {
        struct FlatError: Decodable { let error: String?; let detail: String? }
        struct ValidationDetail: Decodable { let msg: String }
        struct ValidationError: Decodable { let detail: [ValidationDetail] }

        if let flat = try? JSONDecoder().decode(FlatError.self, from: data) {
            return flat.detail ?? flat.error
        }
        if let validation = try? JSONDecoder().decode(ValidationError.self, from: data) {
            return validation.detail.map(\.msg).joined(separator: "; ")
        }
        return String(data: data, encoding: .utf8)
    }

    private func getCachedLicense(_ licenseKey: String) -> (Date, License)? {
        SecureLicenseCache.readLicense(licenseKey)
    }

    private func setCachedLicense(_ licenseKey: String, _ license: License) {
        SecureLicenseCache.writeLicense(licenseKey, license)
    }
}
