import XCTest
@testable import AkitoStationCore

private struct MockBackend: PaymentBackend {
    var state: EntitlementState = .free
    var failure = false
    func entitlement(action: String, token: String) async throws -> ServerEntitlement {
        if failure { throw PaymentError.rejected(503) }
        return ServerEntitlement(state: state, validUntil: Date().addingTimeInterval(60))
    }
    func checkout(offer: String, token: String) async throws -> Checkout {
        if failure { throw PaymentError.rejected(402) }
        return try JSONDecoder().decode(Checkout.self, from: Data("{\"id\":\"test\",\"url\":\"https://example.com/checkout\"}".utf8))
    }
}
final class PaymentTests: XCTestCase {
    @MainActor func testFreePurchaseSubscriptionExpiredAndPending() async throws {
        let manager = EntitlementManager()
        for state in [EntitlementState.free, .pro, .subscriptionActive, .subscriptionExpired, .paymentPending] {
            try await manager.refresh(using: MockBackend(state: state), token: "test")
            XCTAssertEqual(manager.current.state, state)
            XCTAssertEqual(manager.current.allowsPro(), state == .pro || state == .subscriptionActive)
        }
    }
    @MainActor func testRestoreAndUnavailablePreservesVerifiedLease() async throws {
        let manager = EntitlementManager()
        try await manager.refresh(using: MockBackend(state: .pro), token: "test", action: "restore")
        XCTAssertTrue(manager.current.allowsPro())
        do { try await manager.refresh(using: MockBackend(failure: true), token: "test"); XCTFail() } catch {}
        XCTAssertEqual(manager.state, .unavailable)
        XCTAssertEqual(manager.current.state, .pro)
        XCTAssertTrue(manager.current.allowsPro())
        manager.clear(); XCTAssertEqual(manager.current.state, .signedOut)
    }
    func testMissingAndExpiredLeaseFailClosed() {
        XCTAssertFalse(ServerEntitlement(state: .pro).allowsPro())
        XCTAssertFalse(ServerEntitlement(state: .subscriptionActive, validUntil: Date().addingTimeInterval(-1)).allowsPro())
    }
    func testProvidersAndFailedPayment() async throws {
        for provider in [StripePaymentProvider() as any PaymentProvider, PayPalPaymentProvider()] {
            let offer = try JSONDecoder().decode(PaymentOffer.self, from: Data("{\"id\":\"test\",\"provider\":\"\(provider.id)\",\"model\":\"oneTime\",\"label\":\"Test\"}".utf8))
            let checkout = try await provider.checkout(offer: offer, backend: MockBackend(), token: "test")
            XCTAssertEqual(checkout.url.scheme, "https")
            do { _ = try await provider.checkout(offer: offer, backend: MockBackend(failure: true), token: "test"); XCTFail() } catch {}
        }
    }
    func testOnlyHTTPSBackendAccepted() {
        for url in ["", "http://example.com", "https://user:password@example.com", "https://example.com?token=secret"] { XCTAssertThrowsError(try PaymentAPI(baseURL: url)) }
        XCTAssertNoThrow(try PaymentAPI(baseURL: "https://example.com"))
    }
}

private struct UnauthorizedBackend: PaymentBackend {
    func entitlement(action: String, token: String) async throws -> ServerEntitlement { throw PaymentError.rejected(401) }
    func checkout(offer: String, token: String) async throws -> Checkout { throw PaymentError.rejected(401) }
}
private final class PaymentURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, String))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, body) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
extension PaymentTests {
    @MainActor func testSignedOutAndInvalidTokenClearAccess() async throws {
        let manager = EntitlementManager()
        XCTAssertEqual(manager.state, .signedOut)
        XCTAssertFalse(manager.current.allowsPro())
        try await manager.refresh(using: MockBackend(state: .pro), token: "fixture")
        do { try await manager.refresh(using: UnauthorizedBackend(), token: "expired"); XCTFail() } catch {}
        XCTAssertEqual(manager.state, .signedOut)
        XCTAssertFalse(manager.current.allowsPro())
    }
    @MainActor func testPendingSurvivesFreeUntilConfirmationOrTimeout() async throws {
        let manager = EntitlementManager()
        manager.pending()
        try await manager.refresh(using: MockBackend(), token: "fixture")
        XCTAssertEqual(manager.state, .paymentPending)
        manager.finishWaiting()
        XCTAssertEqual(manager.state, .free)
        manager.pending()
        try await manager.refresh(using: MockBackend(state: .pro), token: "fixture")
        XCTAssertEqual(manager.state, .pro)
        XCTAssertFalse(manager.checkoutPending)
    }
    func testDeviceLoginHTTPContract() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PaymentURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); PaymentURLProtocol.handler = nil }
        let api = try PaymentAPI(baseURL: "https://payments.example.test", session: session)
        PaymentURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            if request.url?.path == "/login/start" {
                return (200, #"{"deviceCode":"fixture-device","userCode":"fixture-code","verificationURL":"https://identity.example.test/verify","interval":5,"expiresIn":900}"#)
            }
            XCTAssertEqual(request.url?.path, "/login/poll")
            return (200, #"{"token":null,"interval":10}"#)
        }
        let login: DeviceLogin = try await api.request("login/start", body: [:])
        XCTAssertEqual(login.interval, 5)
        let pending: LoginResult = try await api.request("login/poll", body: ["deviceCode": login.deviceCode])
        XCTAssertNil(pending.token)
        XCTAssertEqual(pending.interval, 10)
    }
    func testHTTPCheckoutAndRestoreRequests() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PaymentURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); PaymentURLProtocol.handler = nil }
        let api = try PaymentAPI(baseURL: "https://payments.example.test", session: session)
        for provider in [StripePaymentProvider() as any PaymentProvider, PayPalPaymentProvider()] {
            PaymentURLProtocol.handler = { request in
                XCTAssertEqual(request.url?.path, "/checkout")
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture")
                let stream = request.httpBodyStream
                stream?.open(); defer { stream?.close() }
                var bytes = [UInt8](repeating: 0, count: 1024)
                let count = stream?.read(&bytes, maxLength: bytes.count) ?? 0
                let data = request.httpBody ?? Data(bytes.prefix(max(0, count)))
                let body = try JSONDecoder().decode([String: String].self, from: data)
                XCTAssertEqual(body["offer"], provider.id + ":oneTime")
                return (200, "{\"id\":\"fixture\",\"url\":\"https://checkout.example.test/pay\"}")
            }
            let data = Data("{\"id\":\"\(provider.id):oneTime\",\"provider\":\"\(provider.id)\",\"model\":\"oneTime\",\"label\":\"Fixture\"}".utf8)
            _ = try await provider.checkout(offer: JSONDecoder().decode(PaymentOffer.self, from: data), backend: api, token: "fixture")
        }
        PaymentURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/restore")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture")
            return (200, "{\"state\":\"pro\",\"validUntil\":\"2099-01-01T00:00:00Z\"}")
        }
        let restored = try await api.entitlement(action: "restore", token: "fixture")
        XCTAssertTrue(restored.allowsPro())
        PaymentURLProtocol.handler = { _ in (401, "{}") }
        do { _ = try await api.entitlement(action: "entitlement", token: "expired"); XCTFail() }
        catch PaymentError.rejected(let code) { XCTAssertEqual(code, 401) }
    }
}
