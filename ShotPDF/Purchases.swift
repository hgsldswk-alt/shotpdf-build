import Combine
import Foundation
import Security
import StoreKit

struct PurchaseDisk {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.hgsldswk.shotpdf",
         kSecAttrAccount as String: "entitlement-v1"]
    }

    func load(clock: () -> Date = Date.init) throws -> Entitlement {
        var read = query
        read[kSecMatchLimit as String] = kSecMatchLimitOne
        read[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(read as CFDictionary, &result)
        if status == errSecItemNotFound {
            let now = clock()
            let value = Entitlement(firstOpen: now, proStartedAt: Launch.freePeriod ? nil : now)
            try save(value)
            return value
        }
        guard status == errSecSuccess, let data = result as? Data else { throw ShotError.storage }
        var value = try JSONDecoder().decode(Entitlement.self, from: data)
        if !Launch.freePeriod && value.proStartedAt == nil {
            value.proStartedAt = clock()
            try save(value)
        }
        return value
    }

    func save(_ value: Entitlement) throws {
        let data = try JSONEncoder().encode(value)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw ShotError.storage }
        } else if status != errSecSuccess {
            throw ShotError.storage
        }
    }
}

@MainActor
final class Purchases: ObservableObject {
    @Published private(set) var product: Product?
    @Published private(set) var busy = false
    @Published private(set) var notice: String?
    @Published private(set) var problem: String?
    private var listener: Task<Void, Never>?
    private var loading = false

    func start(accept: @escaping (StoreKit.Transaction) throws -> Void) async {
        guard !Launch.isTesting, !Launch.hostedTests, !Launch.freePeriod, listener == nil else { return }
        listener = Task { [weak self] in
            for await update in StoreKit.Transaction.updates {
                guard let self else { return }
                guard case let .verified(transaction) = update, transaction.productID == Launch.proID else { continue }
                do {
                    try accept(transaction)
                    await transaction.finish()
                } catch { self.problem = L.t("error.storage") }
            }
        }
        do {
            if case let .verified(transaction)? = await StoreKit.Transaction.latest(for: Launch.proID) {
                try accept(transaction)
            }
        } catch { problem = L.t("error.storage") }
    }

    func loadProduct() async {
        guard !Launch.isTesting, !Launch.freePeriod, product == nil, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            product = try await Product.products(for: [Launch.proID]).first
        } catch { problem = L.t("error.store") }
    }

    func buy(accept: (StoreKit.Transaction) throws -> Void) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        problem = nil
        notice = nil
        if product == nil { await loadProduct() }
        guard let product else { problem = L.t("error.store"); return }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                try accept(transaction)
                await transaction.finish()
                notice = L.t("purchase.active")
            case .success(.unverified): throw ShotError.store
            case .pending: notice = L.t("purchase.pending")
            case .userCancelled: break
            @unknown default: throw ShotError.store
            }
        } catch { problem = (error as? ShotError ?? .store).localizedDescription }
    }

    func restore(accept: (StoreKit.Transaction) throws -> Void) async {
        guard !busy else { return }
        busy = true
        problem = nil
        notice = nil
        defer { busy = false }
        do {
            try await AppStore.sync()
            if case let .verified(transaction)? = await StoreKit.Transaction.latest(for: Launch.proID) {
                try accept(transaction)
                if transaction.revocationDate == nil {
                    notice = L.t("purchase.restored")
                    return
                }
            }
            throw ShotError.noPurchase
        } catch { problem = (error as? ShotError ?? .store).localizedDescription }
    }
}
