import XCTest
@testable import AkitoStationCore

final class FeatureAccessTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1000)
    let products: [String: Set<PremiumFeature>] = ["subscription": Set(PremiumFeature.allCases), "theme-only": [.consoleThemes]]
    func testFreeAndUnknownProductsStayLocked() {
        for feature in PremiumFeature.allCases {
            XCTAssertFalse(FeatureAccess.allows(feature, grants: [], products: products, now: now))
            XCTAssertFalse(FeatureAccess.allows(feature, grants: [PremiumGrant(productID: "unknown", expiration: nil)], products: products, now: now))
        }
    }
    func testExpirationRevocationAndRenewal() {
        for grant in [PremiumGrant(productID: "subscription", expiration: now), PremiumGrant(productID: "subscription", expiration: now.addingTimeInterval(-1)), PremiumGrant(productID: "subscription", expiration: nil, revoked: true)] {
            XCTAssertFalse(FeatureAccess.allows(.wallpapers, grants: [grant], products: products, now: now))
        }
        let renewed = PremiumGrant(productID: "subscription", expiration: now.addingTimeInterval(60))
        for feature in PremiumFeature.allCases {
            XCTAssertTrue(FeatureAccess.allows(feature, grants: [renewed], products: products, now: now))
        }
    }
    func testFeatureSpecificAndLifetimeGrants() {
        let grant = PremiumGrant(productID: "theme-only", expiration: nil)
        XCTAssertTrue(FeatureAccess.allows(.consoleThemes, grants: [grant], products: products, now: now))
        XCTAssertFalse(FeatureAccess.allows(.onlineProfile, grants: [grant], products: products, now: now))
    }
}
