import Foundation
import Combine
import StoreKit

struct CoinPack: Identifiable {
    let id: String
    let coins: Int
    static let all = [CoinPack(id:"com.papi.coffee.coins100",coins:100),.init(id:"com.papi.coffee.coins300",coins:300),.init(id:"com.papi.coffee.coins600",coins:600),.init(id:"com.papi.coffee.coins1200",coins:1200),.init(id:"com.papi.coffee.coins2500",coins:2500),.init(id:"com.papi.coffee.coins6000",coins:6000)]
}
@MainActor final class PapiCommerce: ObservableObject {
    // Enable only after the final Bundle ID and the six products are configured in App Store Connect.
    static let purchasesConfigured = false
    @Published private(set) var products: [Product] = []
    @Published private(set) var busy = false
    @Published private(set) var status = "Purchases are not configured yet. Daily check-in is available."
    @Published private(set) var unresolved = false
    private var listener: Task<Void,Never>?
    private var store: PapiStore?
    private var processing: Set<UInt64> = []
    private var unresolvedIDs: Set<UInt64> = []
    func start(store: PapiStore) {
        guard listener == nil else { return }
        self.store = store
        listener = Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled else { return }
                await self?.receive(result)
            }
        }
        Task { await recover() }
    }
    func load() async {
        guard Self.purchasesConfigured else { return }
        do {
            products = try await Product.products(for:CoinPack.all.map(\.id))
            status = products.isEmpty ? "Products could not be loaded. Try again later." : "Prices are provided by Apple. Coins stay with this local guest."
        } catch { status = "Products could not be loaded. Please try again." }
    }
    func recover() async {
        guard store?.storageAvailable == true else { return }
        for await result in Transaction.unfinished { await receive(result) }
    }
    func buy(_ pack: CoinPack) async {
        guard Self.purchasesConfigured, !busy, !unresolved, let store, store.state.signedIn,
              let product = products.first(where:{$0.id == pack.id}) else { return }
        let owner = store.state.profile.id
        guard store.state.purchaseIntents.isEmpty else {
            store.inform("Purchase pending", "An existing purchase is awaiting approval or recovery. No second purchase has been started."); return
        }
        // Persist owner before invoking Apple. Never infer ownership from a SKU or the current screen.
        guard store.commit({ $0.purchaseIntents[pack.id] = owner }) else { return }
        busy = true; defer { busy = false }
        do {
            let result = try await product.purchase(options:[.appAccountToken(owner)])
            switch result {
            case .success(let verified): await receive(verified)
            case .pending: status = "Awaiting Apple's approval. Your original guest ownership has been saved."
            case .userCancelled:
                _ = store.commit { if $0.purchaseIntents[pack.id] == owner { $0.purchaseIntents.removeValue(forKey:pack.id) } }
                status = "Purchase cancelled."
            @unknown default: status = "The purchase needs review. Its original owner has been retained."
            }
        } catch {
            // An interrupted purchase may still complete later. Retain ownership and retry recovery.
            status = "Purchase interrupted. Ownership has been retained for recovery."
            await recover()
        }
    }
    private func receive(_ result: VerificationResult<Transaction>) async {
        guard let store else { return }
        switch result {
        case .unverified(let transaction, _):
            unresolvedIDs.insert(transaction.id); unresolved = true; status = "An unverified transaction is waiting for review. It has not been credited or finished."
        case .verified(let transaction):
            guard !processing.contains(transaction.id) else { return }
            processing.insert(transaction.id); defer { processing.remove(transaction.id) }
            let id = String(transaction.id)
            if transaction.revocationDate != nil, store.state.creditedTransactions.contains(id),
               !store.state.revokedTransactions.contains(id), let pack = CoinPack.all.first(where:{$0.id == transaction.productID}) {
                guard store.commit({
                    $0.coins -= pack.coins
                    $0.revokedTransactions.insert(id)
                    $0.wallet.insert(.init(id:"revocation-"+id,delta:-pack.coins,reason:"Apple purchase revoked"),at:0)
                }) else { unresolvedIDs.insert(transaction.id); unresolved = true; return }
            }
            if store.state.creditedTransactions.contains(id) || store.state.historicalTransactionIDs.contains(id) {
                await transaction.finish()
                unresolvedIDs.remove(transaction.id); unresolved = !unresolvedIDs.isEmpty
                return
            }
            guard transaction.revocationDate == nil, let owner = transaction.appAccountToken,
                  owner == store.state.profile.id, !store.state.retiredGuestIDs.contains(owner),
                  let pack = CoinPack.all.first(where: {$0.id == transaction.productID}) else {
                unresolvedIDs.insert(transaction.id); unresolved = true; status = "A transaction belongs to an unknown or previous guest, or needs review. No balance was changed and it remains unfinished."; return
            }
            let saved = store.commit {
                guard !$0.creditedTransactions.contains(id) else { return }
                $0.coins += pack.coins
                $0.creditedTransactions.insert(id)
                $0.wallet.insert(.init(id:"apple-"+id,delta:pack.coins,reason:"Apple purchase"),at:0)
                if $0.purchaseIntents[pack.id] == owner { $0.purchaseIntents.removeValue(forKey:pack.id) }
            }
            guard saved else { unresolvedIDs.insert(transaction.id); unresolved = true; status = "Payment verification succeeded, but local delivery has not been saved. Recovery will retry."; return }
            // commit writes and reads back the entire wallet and idempotency record before finish.
            await transaction.finish()
            unresolvedIDs.remove(transaction.id); unresolved = !unresolvedIDs.isEmpty
            status = "\(pack.coins) coins added to your local wallet."
        }
    }
    func sync() async {
        guard Self.purchasesConfigured, !busy else { return }
        busy = true; defer { busy = false }
        do { try await AppStore.sync(); await recover() }
        catch { status = "Apple purchase sync did not complete. Try again later." }
    }
}
