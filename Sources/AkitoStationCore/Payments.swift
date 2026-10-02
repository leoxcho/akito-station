import Foundation
import Combine

public enum EntitlementState: String, Codable, Sendable {
    case free, pro, subscriptionActive, subscriptionExpired, paymentPending, unavailable, signedOut
}
public struct ServerEntitlement: Codable, Sendable {
    public let state: EntitlementState
    public let validUntil: Date?
    public init(state: EntitlementState, validUntil: Date? = nil) { self.state = state; self.validUntil = validUntil }
    public func allowsPro(now: Date = Date()) -> Bool {
        (state == .pro || state == .subscriptionActive) && validUntil.map { $0 > now } == true
    }
}
public struct PaymentOffer: Codable, Identifiable, Sendable {
    public let id: String
    public let provider: String
    public let model: String
    public let label: String
}
public struct Checkout: Codable, Sendable { public let id: String; public let url: URL }
public struct DeviceLogin: Codable, Sendable {
    public let deviceCode: String; public let userCode: String; public let verificationURL: URL
    public let interval: Int; public let expiresIn: Int
}
public struct LoginResult: Codable, Sendable { public let token: String?; public let interval: Int? }
public protocol PaymentBackend: Sendable {
    func entitlement(action: String, token: String) async throws -> ServerEntitlement
    func checkout(offer: String, token: String) async throws -> Checkout
}
public protocol PaymentProvider: Sendable {
    var id: String { get }
    func checkout(offer: PaymentOffer, backend: any PaymentBackend, token: String) async throws -> Checkout
}
public struct StripePaymentProvider: PaymentProvider {
    public let id = "stripe"
    public init() {}
}
public struct PayPalPaymentProvider: PaymentProvider {
    public let id = "paypal"
    public init() {}
}
public extension PaymentProvider {
    func checkout(offer: PaymentOffer, backend: any PaymentBackend, token: String) async throws -> Checkout {
        guard offer.provider == id else { throw PaymentError.invalidResponse }
        return try await backend.checkout(offer: offer.id, token: token)
    }
}
public enum PaymentError: Error, LocalizedError {
    case unconfigured, invalidResponse, rejected(Int), backend(Int, String), loginExpired
    public var statusCode: Int? {
        switch self { case .rejected(let code), .backend(let code, _): return code; default: return nil }
    }
    public var errorDescription: String? {
        switch self {
        case .unconfigured: return "Payment service is not configured."
        case .invalidResponse: return "The payment service returned an invalid response or browser URL."
        case .rejected(let code): return "Payment service request failed (HTTP \(code))."
        case .backend(let code, let detail): return "\(detail) (HTTP \(code))"
        case .loginExpired: return "Sign-in expired. Click Become a PRO Member to retry with your selected offer."
        }
    }
}
public struct PaymentAPI: PaymentBackend {
    private struct Failure: Decodable { let detail: String }
    private let base: URL
    private let testingSession: URLSession?
    public init(baseURL: String, session: URLSession? = nil) throws {
        guard let url = URL(string: baseURL), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { throw PaymentError.unconfigured }
        base = url
        testingSession = session
    }
    public func request<T: Decodable>(_ path: String, token: String = "", body: [String: String]? = nil) async throws -> T {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if !token.isEmpty { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        if let body { request.httpMethod = "POST"; request.httpBody = try JSONEncoder().encode(body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let configuration = URLSessionConfiguration.ephemeral
        let session = testingSession ?? URLSession(configuration: configuration, delegate: NoPaymentRedirects(), delegateQueue: nil)
        defer { if testingSession == nil { session.finishTasksAndInvalidate() } }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw PaymentError.invalidResponse }
        guard response.statusCode == 200 else {
            if let failure = try? JSONDecoder().decode(Failure.self, from: data) {
                throw PaymentError.backend(response.statusCode, failure.detail)
            }
            throw PaymentError.rejected(response.statusCode)
        }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }
    public func entitlement(action: String, token: String) async throws -> ServerEntitlement {
        guard ["entitlement", "restore", "verify", "subscription"].contains(action) else { throw PaymentError.invalidResponse }
        return try await request(action, token: token, body: action == "entitlement" ? nil : [:])
    }
    public func checkout(offer: String, token: String) async throws -> Checkout {
        try await request("checkout", token: token, body: ["offer": offer])
    }
}
private final class NoPaymentRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
@MainActor public final class EntitlementManager: ObservableObject {
    @Published public private(set) var current = ServerEntitlement(state: .signedOut)
    @Published public private(set) var unavailable = false
    @Published public private(set) var checkoutPending = false
    public var state: EntitlementState {
        if unavailable { return .unavailable }
        if current.allowsPro() { return current.state }
        if checkoutPending { return .paymentPending }
        if current.state == .subscriptionActive { return .subscriptionExpired }
        return current.state == .pro ? .unavailable : current.state
    }
    private var revision = 0
    public init() {}
    public func refresh(using backend: any PaymentBackend, token: String, action: String = "entitlement") async throws {
        guard !token.isEmpty else { clear(); throw PaymentError.rejected(401) }
        revision += 1
        let requestRevision = revision
        do {
            let verified = try await backend.entitlement(action: action, token: token)
            guard revision == requestRevision else { return }
            current = verified
            unavailable = false
            checkoutPending = current.state == .paymentPending || (checkoutPending && current.state == .free)
        } catch {
            if revision == requestRevision {
                if (error as? PaymentError)?.statusCode == 401 { clear() } else { unavailable = true }
            }
            throw error
        }
    }
    public func pending() { checkoutPending = true; unavailable = false }
    public func finishWaiting() { checkoutPending = false }
    public func markUnavailable() { unavailable = true }
    public func clear() { revision += 1; current = ServerEntitlement(state: .signedOut); unavailable = false; checkoutPending = false }
}

/// Owns the original offer throughout the browser round trip. No view lifetime or
/// catalog refresh can replace it. Device authorization is completed by polling,
/// not by the separate website authorization-code callback.
@MainActor public struct PaymentJourney {
    public let api: PaymentAPI
    public let manager: EntitlementManager
    public init(api: PaymentAPI, manager: EntitlementManager) { self.api = api; self.manager = manager }
    @discardableResult public func run(
        offer: PaymentOffer?, token existingToken: String,
        saveSession: (String) throws -> Void,
        open: (URL) throws -> Void,
        status: (String) -> Void,
        sleep: (Int) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    ) async throws -> Bool {
        var token = existingToken
        if token.isEmpty {
            let login: DeviceLogin = try await api.request("login/start", body: [:])
            status("Sign in in your browser. Code: \(login.userCode)")
            try open(login.verificationURL)
            let deadline = Date().addingTimeInterval(Double(min(login.expiresIn, 900)))
            var interval = max(login.interval, 5)
            while Date() < deadline {
                try await sleep(interval)
                try Task.checkCancellation()
                guard Date() < deadline else { break }
                let result: LoginResult
                do {
                    result = try await api.request("login/poll", body: ["deviceCode": login.deviceCode])
                } catch let error as URLError where [.timedOut, .networkConnectionLost, .notConnectedToInternet].contains(error.code) {
                    status("Waiting for sign-in; reconnecting to the payment service…")
                    continue
                }
                if let next = result.interval { interval = max(interval + 5, next) }
                if let authenticated = result.token, !authenticated.isEmpty {
                    try saveSession(authenticated)
                    token = authenticated
                    break
                }
            }
            guard !token.isEmpty else { throw PaymentError.loginExpired }
        }
        // Failure to verify must stop checkout, while preserving the saved session.
        try await manager.refresh(using: api, token: token, action: "restore")
        guard let offer, !manager.current.allowsPro() else { return false }
        let provider: any PaymentProvider
        switch offer.provider {
        case "paypal": provider = PayPalPaymentProvider()
        case "stripe": provider = StripePaymentProvider()
        default: throw PaymentError.invalidResponse
        }
        let checkout = try await provider.checkout(offer: offer, backend: api, token: token)
        try open(checkout.url)
        manager.pending()
        return true
    }
}
