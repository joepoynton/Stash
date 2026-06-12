//
//  StoreKitManager.swift
//  Stash
//
//  Manages Stash Pro purchase state via StoreKit 2.
//  Inject as an environment object from StashApp. Read isPro and featureFlags
//  from any view via @Environment(StoreKitManager.self).
//

import StoreKit
import Observation

@Observable
final class StoreKitManager {

    // MARK: - Constants

    static let productID = "com.poynt.stash.pro"
    private static let userDefaultsKey = "stashProPurchased"

    // MARK: - Published state

    /// True when the user has purchased Stash Pro. Backed by UserDefaults so
    /// the app works correctly while StoreKit finishes loading on cold start.
    private(set) var isPro: Bool

    /// The fetched product (used for live price display in UpgradePromptSheet).
    private(set) var product: Product?

    /// Set when a purchase or restore attempt fails.
    private(set) var purchaseError: String?

    /// Informational (non-error) status, e.g. a purchase awaiting Ask to Buy
    /// approval. Shown in UpgradePromptSheet in a neutral style.
    private(set) var purchaseMessage: String?

    /// Lifetime listener for Transaction.updates (Ask to Buy approvals,
    /// purchases on other devices, refunds). Held so deinit can cancel it.
    private var updatesTask: Task<Void, Never>?

    // MARK: - Derived

    var featureFlags: FeatureFlags { FeatureFlags(isPro: isPro) }

    // MARK: - Init

    init() {
        #if DEBUG
        isPro = true
        #else
        isPro = UserDefaults.standard.bool(forKey: Self.userDefaultsKey)
        Task { await loadProduct() }
        Task { await verifyCurrentEntitlements() }
        #endif
        updatesTask = listenForTransactionUpdates()
    }

    deinit {
        updatesTask?.cancel()
    }

    // MARK: - Purchase

    func purchase() async {
        purchaseError = nil
        purchaseMessage = nil
        guard let product else {
            purchaseError = "Product unavailable. Check your connection and try again."
            return
        }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                setProStatus(true)
            case .userCancelled:
                break
            case .pending:
                // e.g. Ask to Buy — the transaction will arrive later via
                // Transaction.updates, which unlocks Pro automatically.
                purchaseMessage = "Purchase pending approval. Pro will unlock automatically once it's approved."
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Restore

    func restorePurchases() async {
        purchaseError = nil
        do {
            try await AppStore.sync()
            await verifyCurrentEntitlements()
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Private

    /// Detached lifetime task observing Transaction.updates. Without this,
    /// Ask to Buy approvals, refunds, and purchases made on other devices
    /// are never applied (and never finished) while the app is running.
    private func listenForTransactionUpdates() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let manager = self else { return }
                await manager.handle(updatedTransaction: result)
            }
        }
    }

    @MainActor
    private func handle(updatedTransaction result: VerificationResult<Transaction>) async {
        guard let transaction = try? checkVerified(result) else { return }
        if transaction.productID == Self.productID {
            setProStatus(transaction.revocationDate == nil)
        }
        await transaction.finish()
    }

    private func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.productID])
            product = products.first
        } catch {
            // Silently fail — price will show placeholder text in UI
        }
    }

    private func verifyCurrentEntitlements() async {
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if transaction.productID == Self.productID {
                setProStatus(true)
                return
            }
        }
        // No active entitlement found. Don't revoke access — UserDefaults is
        // the authoritative fallback while StoreKit is slow/offline. The next
        // successful sync will correct any discrepancy.
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified: throw StoreKitError.failedVerification
        case .verified(let value): return value
        }
    }

    private func setProStatus(_ pro: Bool) {
        isPro = pro
        UserDefaults.standard.set(pro, forKey: Self.userDefaultsKey)
    }

    enum StoreKitError: Error {
        case failedVerification
    }
}
