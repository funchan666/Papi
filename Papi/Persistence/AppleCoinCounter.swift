import Foundation
import Combine
import StoreKit

struct CoinPack: Identifiable {
    let id: String
    let coins: Int
    let referenceUSD: String
    // Reference prices are App Store Connect inputs, never an asserted live Apple price.
    static let all: [CoinPack] = [
        .init(id:"rkbybzkkqpeaxovi",coins:480,referenceUSD:"0.99"),
        .init(id:"yiyfivvjmkdiuqus",coins:1000,referenceUSD:"1.99"),
        .init(id:"mqtzlpvknayrxwce",coins:1600,referenceUSD:"2.99"),
        .init(id:"vguhlyrrsyfaswwv",coins:2800,referenceUSD:"4.99"),
        .init(id:"qqopbybcdridrsjl",coins:6000,referenceUSD:"9.99"),
        .init(id:"wspjnqfkxvmdlrya",coins:9600,referenceUSD:"14.99"),
        .init(id:"kokiljjwycwbpasa",coins:13200,referenceUSD:"19.99"),
        .init(id:"nylrtdzhiqgywsrh",coins:36000,referenceUSD:"49.99"),
        .init(id:"lkcdocdwdjjjmdfr",coins:78000,referenceUSD:"99.99")
    ]
    // Frozen delivery amounts for transactions from the previous catalog.
    static let legacyCoins = ["com.papi.coffee.coins100":100,"com.papi.coffee.coins300":300,
        "com.papi.coffee.coins600":600,"com.papi.coffee.coins1200":1200,
        "com.papi.coffee.coins2500":2500,"com.papi.coffee.coins6000":6000]
}
@MainActor final class AppleCoinCounter: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var busy = false
    @Published private(set) var status = "Apple is contacted only when you tap Buy. The Apple sheet confirms the local price."
    @Published private(set) var unresolved = false
    private var listener: Task<Void,Never>?
    private var store: CoffeeHouse?
    private var processing: Set<UInt64> = []
    private var unresolvedIDs: Set<UInt64> = []
    private var recovering = false
    private var recoveryRequested=false
    func start(store: CoffeeHouse) {
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
    func recover() async {
        guard let store,store.storageAvailable,store.accountAction==nil else{return}
        if recovering {recoveryRequested=true;return}
        recovering=true;defer {recovering=false}
        repeat {
            recoveryRequested=false
            for await result in Transaction.unfinished {await receive(result)}
        } while recoveryRequested && store.storageAvailable && store.accountAction==nil
    }
    func buy(_ pack: CoinPack, canPresent: @MainActor ()->Bool, purchase: @MainActor (Product, Set<Product.PurchaseOption>) async throws -> Product.PurchaseResult) async {
        guard !busy,let store,store.state.signedIn,canPresent() else{return}
        guard !unresolved, store.state.purchaseIntents.isEmpty, store.state.activePurchaseToken==nil else {
            store.inform("Purchase pending", "An existing purchase is awaiting approval or recovery. No second purchase has been started.");return
        }
        guard store.beginCheckout() else{return}
        busy=true
        defer {busy=false;store.endCheckout()}
        status="Asking Apple for this product…"
        let owner=store.state.passport.id
        let product:Product
        do {
            // This is the sole product request. No catalog request runs on launch or page entry.
            let availableProducts=try await Product.products(for:[pack.id])
            guard canPresent() else {status="Purchase cancelled. No coins were added.";return}
            guard let fetched=availableProducts.first(where:{$0.id==pack.id}), fetched.type == .consumable else {
                fail("This product is not available from Apple. Please try again later.");return
            }
            product=fetched
            products.removeAll{$0.id==pack.id};products.append(product)
        } catch {
            guard canPresent() else {status="Purchase cancelled. No coins were added.";return}
            fail("Apple could not load this product. No purchase was started. Please try again.");return
        }
        if product.priceFormatStyle.currencyCode == "USD", let expected=Decimal(string:pack.referenceUSD), product.price != expected {
            fail("Apple's USD price does not match this pack's configured price. No purchase was started.");return
        }
        // Recheck after suspension: recovery may have discovered an unresolved order meanwhile.
        guard !unresolved,store.state.signedIn,store.state.passport.id==owner,store.state.purchaseIntents.isEmpty else {
            fail("A purchase needs attention. Use Recover purchases before trying again.");return
        }
        let terms=CoinPurchaseTerms(token:UUID(),owner:owner,productID:pack.id,coins:pack.coins)
        guard store.commit({
            $0.purchaseIntents[pack.id]=owner
            $0.activePurchaseToken=terms.token
            if $0.coinPurchaseTerms==nil {$0.coinPurchaseTerms=[]}
            $0.coinPurchaseTerms?.append(terms)
        }) else{return}
        status="Confirm your purchase with Apple."
        do {
            let result=try await purchase(product,[.appAccountToken(terms.token)])
            switch result {
            case .success(let verified):await receive(verified)
            case .pending:
                status="Awaiting Apple's approval. Coins arrive only after a verified transaction."
                store.inform("Awaiting Apple approval",status)
            case .userCancelled:
                clearIntent(token:terms.token,productID:pack.id)
                status="Purchase cancelled. No coins were added."
            @unknown default:
                fail("Apple has not confirmed this purchase. Its owner and coin amount are saved for recovery.")
            }
        } catch is Product.PurchaseError {
            clearIntent(token:terms.token,productID:pack.id)
            fail("Apple could not complete this purchase. No coins were added. Please try again.")
        } catch {
            if let storeError=error as? StoreKitError, case .userCancelled=storeError {
                clearIntent(token:terms.token,productID:pack.id)
                status="Purchase cancelled. No coins were added."
            } else {
                // An uncertain result can still complete through updates. Do not start a second charge.
                fail("Purchase interrupted. Its owner and coin amount are saved. Use Recover purchases before trying again.")
                await recover()
            }
        }
    }
    private func clearIntent(token:UUID,productID:String) {
        guard let store,store.state.activePurchaseToken==token else{return}
        _ = store.commit {$0.activePurchaseToken=nil;$0.purchaseIntents.removeValue(forKey:productID)}
    }
    private func fail(_ message:String) {
        status=message
        if store?.notice==nil {store?.inform("Coffee reserve",message)}
    }
    private func hold(_ transaction:Transaction,_ message:String) {
        unresolvedIDs.insert(transaction.id);unresolved=true;status=message
    }
    private func receive(_ result: VerificationResult<Transaction>) async {
        guard let store,store.storageAvailable else{return}
        switch result {
        case .unverified(let transaction,_):
            hold(transaction,"An unverified transaction is waiting for review. It has not been credited or finished.")
        case .verified(let transaction):
            guard !processing.contains(transaction.id) else{return}
            processing.insert(transaction.id);defer {processing.remove(transaction.id)}
            let id=String(transaction.id)
            let terms=store.state.coinPurchaseTerms?.first(where:{$0.token==transaction.appAccountToken && $0.productID==transaction.productID})
            if let settledID=terms?.transactionID,settledID != id {
                hold(transaction,"This order is already linked to another Apple transaction. No coins were added; purchase recovery needs review.");return
            }
            if store.state.creditedTransactions.contains(id) {
                let needsRevocation=transaction.revocationDate != nil && !store.state.revokedTransactions.contains(id)
                let needsBinding=terms != nil && terms?.transactionID==nil
                var revokedCoins=0
                if needsRevocation {
                    // Refund the actual original delivery, never today's catalog amount.
                    guard let delivery=store.state.coinMovements.first(where:{$0.id=="apple-"+id}),delivery.delta>0 else {
                        hold(transaction,"The original delivery needs review before a refund adjustment can be saved.");return
                    }
                    guard !store.state.coinBalance.subtractingReportingOverflow(delivery.delta).overflow else {
                        hold(transaction,"This balance needs review before delivery can continue.");return
                    }
                    revokedCoins=delivery.delta
                }
                if needsRevocation || needsBinding {
                    guard store.commit({
                        if let token=terms?.token,let index=$0.coinPurchaseTerms?.firstIndex(where:{$0.token==token && $0.productID==transaction.productID}) {$0.coinPurchaseTerms?[index].transactionID=id}
                        if needsRevocation {
                            $0.coinBalance -= revokedCoins
                            $0.revokedTransactions.insert(id)
                            $0.coinMovements.insert(.init(id:"revocation-"+id,delta:-revokedCoins,reason:"Apple purchase revoked"),at:0)
                        }
                    }) else {hold(transaction,"Payment verification succeeded, but local delivery has not been saved. Recovery will retry.");return}
                }
                await transaction.finish()
                unresolvedIDs.remove(transaction.id);unresolved = !unresolvedIDs.isEmpty
                return
            }
            if store.state.historicalTransactionIDs.contains(id) {
                await transaction.finish()
                unresolvedIDs.remove(transaction.id);unresolved = !unresolvedIDs.isEmpty
                return
            }
            let legacyOwner=transaction.appAccountToken==store.state.passport.id ? transaction.appAccountToken:nil
            let owner=terms?.owner ?? legacyOwner
            let coins=terms?.coins ?? (legacyOwner != nil ? CoinPack.legacyCoins[transaction.productID]:nil)
            guard let owner,owner==store.state.passport.id,!store.state.retiredGuestIDs.contains(owner),
                  let coins,coins>0,transaction.productType == .consumable,transaction.purchasedQuantity==1 else {
                hold(transaction,"A transaction belongs to an unknown or previous guest, or needs review. No balance was changed and it remains unfinished.");return
            }
            let revoked=transaction.revocationDate != nil
            let addition=store.state.coinBalance.addingReportingOverflow(revoked ? 0:coins)
            guard !addition.overflow else {hold(transaction,"This balance needs review before delivery can continue.");return}
            guard store.commit({
                if let token=terms?.token,let index=$0.coinPurchaseTerms?.firstIndex(where:{$0.token==token && $0.productID==transaction.productID}) {$0.coinPurchaseTerms?[index].transactionID=id}
                $0.creditedTransactions.insert(id)
                if revoked {$0.revokedTransactions.insert(id)}
                else {
                    $0.coinBalance += coins
                    $0.coinMovements.insert(.init(id:"apple-"+id,delta:coins,reason:"Apple purchase"),at:0)
                }
                if let token=terms?.token,$0.activePurchaseToken==token {
                    $0.activePurchaseToken=nil;$0.purchaseIntents.removeValue(forKey:transaction.productID)
                } else if terms==nil,$0.activePurchaseToken==nil,$0.purchaseIntents[transaction.productID]==owner {
                    $0.purchaseIntents.removeValue(forKey:transaction.productID)
                }
            }) else {hold(transaction,"Payment verification succeeded, but local delivery has not been saved. Recovery will retry.");return}
            // Keychain write + readback includes balance, immutable order terms and transaction ID.
            await transaction.finish()
            unresolvedIDs.remove(transaction.id);unresolved = !unresolvedIDs.isEmpty
            status=revoked ? "This transaction was revoked. No coins were added.":"\(coins) coins added to your local wallet."
            if store.state.signedIn,store.notice==nil {
                store.notice = .init(title:revoked ? "Purchase revoked":"Your coffee reserve is topped up",message:status,kind:.purchase)
            }
        }
    }
    func sync() async {
        guard !busy,let store,store.beginCheckout() else{return}
        busy=true;defer {busy=false;store.endCheckout()}
        status="Checking unfinished purchases with Apple…"
        do {
            try await AppStore.sync();await recover()
            if !unresolved {
                status=store.state.purchaseIntents.isEmpty ? "Apple sync complete. Saved deliveries are never credited twice. Finished consumable coins cannot be restored to a new guest.":"An order is still awaiting Apple's result. No second purchase has been started."
            }
        } catch {fail("Apple purchase sync did not complete. Try again later.")}
    }
}
