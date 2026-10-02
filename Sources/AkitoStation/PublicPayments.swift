import SwiftUI
import Combine
import Security
import AkitoStationCore

@MainActor final class PremiumStore: ObservableObject {
    static let shared = PremiumStore()
    @Published private(set) var offers: [PaymentOffer] = []
    @Published private(set) var busy = false
    @Published private(set) var message = "Sign in to become a PRO Member or restore your membership."
    var state: EntitlementState { manager.state }
    @Published private(set) var signedIn = false
    let manager = EntitlementManager()
    private var observation: AnyCancellable?
    private init() {
        observation = manager.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }
    // Only the public service URL is bundled. Tokens are stored in the macOS Keychain.
    private let api = try? PaymentAPI(baseURL: Bundle.main.object(forInfoDictionaryKey: "AKITO_API_BASE_URL") as? String ?? "")
    private var token = ""
    private var monitor: Task<Void, Never>?
    private var started = false
    private var checkoutMonitor: Task<Void, Never>?
    private var refreshInFlight = false
    var configured: Bool { api != nil }
    func allows(_ feature: PremiumFeature) -> Bool { manager.current.allowsPro() }
    func start() async {
        guard !started else { return }
        started = true
        guard let api else { manager.markUnavailable(); message = "Network/backend unavailable: payment service is not configured."; return }
        token = PaymentSession.load() ?? ""
        signedIn = !token.isEmpty
        if signedIn { await refresh() }
        do { offers = try await api.request("offers") } catch { fail(error) }
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self else { return }
                if self.signedIn && !self.busy { await self.refresh() }
            }
        }
    }
    func signIn() async { await runJourney(offer: nil) }
    func signOut() { checkoutMonitor?.cancel(); PaymentSession.clear(); token = ""; signedIn = false; manager.clear(); message = "Signed out." }
    func refresh(action: String = "entitlement") async {
        guard let api, signedIn, !refreshInFlight else { return }
        refreshInFlight = true; defer { refreshInFlight = false }
        do {
            try await manager.refresh(using: api, token: token, action: action)
            switch state {
            case .signedOut: message = "Sign in to restore or purchase PRO."
            case .free: message = "Become a PRO Member"
            case .pro: message = "PRO Member — thank you for supporting development."
            case .subscriptionActive: message = "Subscription active"
            case .subscriptionExpired: message = "Subscription expired"
            case .paymentPending: message = "Payment processing — refresh after completing checkout."
            case .unavailable: message = "Network/backend unavailable"
            }
        } catch { fail(error) }
    }
    func purchase(_ offer: PaymentOffer) async { await runJourney(offer: offer) }
    private func runJourney(offer: PaymentOffer?) async {
        guard let api, !busy else { return }
        busy = true; defer { busy = false }
        do {
            let opened = try await PaymentJourney(api: api, manager: manager).run(
                offer: offer, token: token,
                saveSession: { token in
                    try PaymentSession.save(token)
                    self.token = token; self.signedIn = true
                }, open: open, status: { self.message = $0 })
            guard opened else {
                message = manager.current.allowsPro() ? "PRO Member — thank you for supporting development." : "Signed in. Select your membership offer to continue."
                return
            }
            message = "Payment processing. Complete checkout in your browser; PRO will refresh automatically."
            checkoutMonitor?.cancel()
            checkoutMonitor = Task { [weak self] in
                for _ in 0..<60 {
                    do { try await Task.sleep(for: .seconds(5)) } catch { return }
                    guard let self, self.signedIn else { return }
                    await self.refresh()
                    if self.manager.current.allowsPro() { return }
                }
                self?.manager.finishWaiting()
                self?.message = "Payment is not yet confirmed. Restore / Refresh PRO to check again, or retry checkout."
            }
        } catch { fail(error) }
    }
    func restore() async {
        guard !busy else { return }
        if !signedIn { await signIn(); return }
        busy = true; defer { busy = false }
        await refresh(action: "restore")
        if let api { offers = (try? await api.request("offers")) ?? offers }
    }
    func manage() async {
        guard let api, signedIn, !busy else { return }
        busy = true; defer { busy = false }
        do { let result: Checkout = try await api.request("manage", token: token, body: [:]); try open(result.url) }
        catch { fail(error) }
    }
    private func open(_ url: URL) throws {
        guard url.scheme == "https", url.host != nil, url.user == nil, url.password == nil, NSWorkspace.shared.open(url) else { throw PaymentError.invalidResponse }
    }
    private func fail(_ error: Error) {
        if (error as? PaymentError)?.statusCode == 401 { signOut() }
        message = error.localizedDescription
    }

}

struct PublicPaymentSettings: View {
    @ObservedObject var premium: PremiumStore
    @State private var selectedOffer = ""
    private var offer: PaymentOffer? { premium.offers.first { $0.id == selectedOffer } ?? premium.offers.first }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Akito Station PRO").font(.title2.bold())
            Text("Support continued development of Akito Station. Membership enables the available console themes and wallpaper controls. Early-access delivery and online profiles are unavailable.")
            Text("The standard public version of Akito Station remains available separately.").font(.caption).foregroundStyle(.secondary)
            Label(status, systemImage: premium.allows(.premiumCustomization) ? "checkmark.seal.fill" : "heart")
                .foregroundStyle(IceTheme.cyan)
            if !premium.offers.isEmpty && !premium.allows(.premiumCustomization) {
                Picker("PRO Membership", selection: Binding(get: { offer?.id ?? "" }, set: { selectedOffer = $0 })) {
                    ForEach(premium.offers) { option in
                        Text("\(option.provider == "stripe" ? "Stripe" : "PayPal") · \(option.label)").tag(option.id)
                    }
                }.disabled(premium.busy || premium.allows(.premiumCustomization))
            } else if !premium.allows(.premiumCustomization) {
                Text("Stripe and PayPal membership options will appear when the service is available and pricing is enabled.").font(.caption)
            }
            if !premium.allows(.premiumCustomization) {
                Button(premium.signedIn ? (premium.state == .paymentPending ? "Resume checkout" : "Become a PRO Member") : "Sign in · Become a PRO Member") {
                    Task { if let offer { await premium.purchase(offer) } }
                }.buttonStyle(.borderedProminent)
                    .disabled(!premium.configured || premium.busy || offer == nil)
            }
            HStack {
                Button("Restore / Refresh PRO") { Task { if premium.signedIn { await premium.restore() } else { await premium.signIn() } } }
                if premium.signedIn && [.subscriptionActive, .subscriptionExpired].contains(premium.manager.current.state) {
                    Button("Manage Membership") { Task { await premium.manage() } }
                }
            }.disabled(!premium.configured || premium.busy)
            if premium.signedIn { Button("Sign out") { premium.signOut() }.disabled(premium.busy) }
            if premium.busy { ProgressView().controlSize(.small) }
            Text(premium.message).font(.caption).textSelection(.enabled)
            Text("Early Access supports Akito Station development. Membership does not include games, ROMs, BIOS, firmware, keys, console software, PKG files, emulator binaries, or third-party proprietary content.")
                .font(.caption).foregroundStyle(.secondary)
        }.task { await premium.start() }
    }
    private var status: String {
        switch premium.state {
        case .signedOut: return "Sign in to your Akito account"
        case .free: return "Support Development"
        case .pro: return "PRO Member"
        case .subscriptionActive: return "PRO Membership active"
        case .subscriptionExpired: return "Membership expired · reactivate below"
        case .paymentPending: return "Payment processing"
        case .unavailable: return "Membership verification unavailable"
        }
    }
}

struct PROMembershipControl: View {
    @ObservedObject private var premium = PremiumStore.shared
    @State private var showingMembership = false
    var body: some View {
        Button { showingMembership = true } label: {
            HStack(spacing: 10) {
                Text(premium.allows(.premiumCustomization) ? "PRO ✓" : "PRO")
                    .font(.system(size: 28, weight: .black, design: .rounded)).tracking(2)
                if premium.state == .paymentPending { ProgressView().controlSize(.small).tint(IceTheme.gold) }
            }
            .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.91, blue: 0.57), IceTheme.gold], startPoint: .top, endPoint: .bottom))
            .padding(.horizontal, 22).padding(.vertical, 10)
            .background(IceTheme.gold.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(IceTheme.gold.opacity(0.8), lineWidth: 1.5))
        }.buttonStyle(.plain).help("Akito Station PRO Membership")
            .accessibilityLabel("Akito Station PRO Membership")
            .sheet(isPresented: $showingMembership) { PROMembershipSheet() }
    }
}
private struct PROMembershipSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .trailing) {
            Button("Done") { dismiss() }
            ScrollView { PublicPaymentSettings(premium: .shared).frame(maxWidth: .infinity, alignment: .leading) }
        }.padding(24).frame(width: 620, height: 520)
            .background(IceBackdrop()).preferredColorScheme(.dark).tint(IceTheme.cyan)
    }
}
private enum PaymentSession {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "app.akitostation.public.session",
         kSecAttrAccount as String: Bundle.main.object(forInfoDictionaryKey: "AKITO_API_BASE_URL") as? String ?? ""]
    }
    static func load() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ token: String) throws {
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8),
                                       kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let updated = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw PaymentError.invalidResponse }
        let added = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        guard added == errSecSuccess else { throw PaymentError.invalidResponse }
    }
    static func clear() { SecItemDelete(query as CFDictionary) }
}
