import Foundation

/// Stable identifiers shared by UI, billing and future server-side entitlement checks.
public enum PremiumFeature: String, CaseIterable, Sendable {
    case consoleThemes, wallpapers, onlineProfile, premiumCustomization
}

public struct PremiumGrant: Sendable {
    public let productID: String
    public let expiration: Date?
    public let revoked: Bool
    public init(productID: String, expiration: Date?, revoked: Bool = false) {
        self.productID = productID; self.expiration = expiration; self.revoked = revoked
    }
}

public enum FeatureAccess {
    /// Only pass grants produced by a trusted verification provider; never persist an unlock boolean.
    public static func allows(_ feature: PremiumFeature, grants: [PremiumGrant], products: [String: Set<PremiumFeature>], now: Date = Date()) -> Bool {
        grants.contains { !$0.revoked && ($0.expiration.map { $0 > now } ?? true) && products[$0.productID]?.contains(feature) == true }
    }
}
