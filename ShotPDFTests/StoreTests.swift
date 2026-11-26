import StoreKit
import StoreKitTest
import XCTest
@testable import ShotPDF

final class StoreTests: XCTestCase {
    func testVerifiedNonConsumableCanBeRestored() async throws {
        let configuration = try XCTUnwrap(Bundle(for: StoreTests.self).url(forResource: "ShotPDF", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: configuration)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }
        let products = try await Product.products(for: [Launch.proID])
        XCTAssertEqual(products.count, 1)
        XCTAssertEqual(products.first?.type, .nonConsumable)
        _ = try await session.buyProduct(identifier: Launch.proID, options: [])
        try await AppStore.sync()
        let latest = await StoreKit.Transaction.latest(for: Launch.proID)
        let restored = try XCTUnwrap(latest)
        guard case let .verified(transaction) = restored else { return XCTFail("No verified purchase") }
        XCTAssertEqual(transaction.productID, Launch.proID)
        XCTAssertNil(transaction.revocationDate)
        let entitlement = Entitlement(firstOpen: .distantPast, purchasedPro: transaction.revocationDate == nil)
        XCTAssertTrue(entitlement.hasPro(at: .now))
    }
}
