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
@MainActor final class AppleCoinCounter: NSObject, ObservableObject, SKProductsRequestDelegate, SKPaymentTransactionObserver {
    @Published private(set) var products: [SKProduct] = []
    @Published private(set) var busy = false
    @Published private(set) var status = "Purchases are temporarily unavailable."
    @Published private(set) var unresolved = false
    // Enable only after the server verifier, cancellation/reconciliation and Apple sandbox are verified.
    let checkoutAvailable = false
    private var started = false
    private var store: CoffeeHouse?
    private var productRequest: SKProductsRequest?
    private var productContinuation: CheckedContinuation<SKProduct?, Error>?
    private var requestedProductID: String?
    private var processing: Set<String> = []
    private var retryTask:Task<Void,Never>?
    private var retryCount=0

    func start(store:CoffeeHouse) {
        guard !started else {return}
        started=true;self.store=store
        SKPaymentQueue.default().add(self)
        Task {await recover()}
    }

    func displayPrice(for id:String)->String? {
        guard let product=products.first(where:{$0.productIdentifier==id}) else{return nil}
        let formatter=NumberFormatter();formatter.numberStyle = .currency;formatter.locale=product.priceLocale
        return formatter.string(from:product.price)
    }

    private func requestProduct(_ id:String) async throws -> SKProduct? {
        try await withCheckedThrowingContinuation {continuation in
            productContinuation=continuation;requestedProductID=id
            let request=SKProductsRequest(productIdentifiers:[id]);productRequest=request;request.delegate=self;request.start()
        }
    }
    nonisolated func productsRequest(_ request:SKProductsRequest,didReceive response:SKProductsResponse) {
        Task { @MainActor in
            guard self.productRequest === request,let continuation=self.productContinuation else{return}
            let product=response.products.first(where:{$0.productIdentifier==self.requestedProductID})
            self.productContinuation=nil;self.productRequest=nil;self.requestedProductID=nil
            continuation.resume(returning:product)
        }
    }
    nonisolated func request(_ request:SKRequest,didFailWithError error:Error) {
        Task { @MainActor in
            guard self.productRequest === request,let continuation=self.productContinuation else{return}
            self.productContinuation=nil;self.productRequest=nil;self.requestedProductID=nil
            continuation.resume(throwing:error)
        }
    }

    func buy(_ pack:CoinPack,canPresent:@MainActor ()->Bool) async {
        guard checkoutAvailable else {fail("Purchases are temporarily unavailable.");return}
        guard !busy,let store,store.state.signedIn,let account=store.state.cloudAccountID,canPresent() else{return}
        guard SKPaymentQueue.canMakePayments() else {fail("Purchases are not available on this device.");return}
        guard !unresolved,store.state.purchaseIntents.isEmpty,store.state.activePurchaseToken==nil else {
            fail("A purchase needs attention. Use Recover purchases before trying again.");return
        }
        guard store.beginCheckout() else{return}
        busy=true;defer {busy=false;store.endCheckout()}
        status="Asking Apple for this product…"
        do {
            guard let product=try await requestProduct(pack.id) else {fail("This product is not available from Apple. Please try again later.");return}
            products.removeAll{$0.productIdentifier==product.productIdentifier};products.append(product)
            guard canPresent(),store.state.signedIn,store.state.cloudAccountID==account,
                  !unresolved,store.state.purchaseIntents.isEmpty,store.state.activePurchaseToken==nil else{return}
            let terms=CoinPurchaseTerms(token:UUID(),owner:account,productID:pack.id,coins:pack.coins)
            guard store.commit({
                $0.purchaseIntents[pack.id]=account;$0.activePurchaseToken=terms.token
                if $0.coinPurchaseTerms==nil {$0.coinPurchaseTerms=[]};$0.coinPurchaseTerms?.append(terms)
            }) else{return}
            // Keep the order identity on disk before any remote request or Apple payment.
            try await CoffeeCloud.shared.createPurchaseOrder(id:terms.token,productID:pack.id,account:account)
            guard canPresent(),store.state.signedIn,store.state.cloudAccountID==account,
                  store.state.activePurchaseToken==terms.token else {
                unresolved=true;fail("The saved order needs reconciliation before another purchase.");return
            }
            let payment=SKMutablePayment(product:product)
            payment.applicationUsername=terms.token.uuidString.lowercased()
            SKPaymentQueue.default().add(payment)
            status="Confirm your purchase with Apple."
        } catch {
            if store.state.activePurchaseToken != nil {unresolved=true;fail("The saved order needs reconciliation before another purchase.")}
            else {fail("Apple could not load this product. No purchase was started. Please try again.")}
        }
    }

    nonisolated func paymentQueue(_ queue:SKPaymentQueue,updatedTransactions transactions:[SKPaymentTransaction]) {
        Task { @MainActor in for transaction in transactions {await self.receive(transaction)} }
    }
    private func receive(_ transaction:SKPaymentTransaction) async {
        guard let store else{return}
        switch transaction.transactionState {
        case .purchasing: status="Confirm your purchase with Apple."
        case .deferred: status="Awaiting Apple's approval. Coins arrive only after a verified transaction."
        case .failed:
            // Persist the terminal result before removing Apple's queue entry.
            guard store.storageAvailable,
                  let text=transaction.payment.applicationUsername,let token=UUID(uuidString:text),
                  let terms=store.state.coinPurchaseTerms?.first(where:{$0.token==token && $0.productID==transaction.payment.productIdentifier}),
                  store.commit({state in
                      if let index=state.coinPurchaseTerms?.firstIndex(where:{$0.token==token && $0.productID==terms.productID}) {
                          let recorded=state.coinPurchaseTerms?[index].failedAt
                          state.coinPurchaseTerms?[index].failedAt=recorded ?? Date()
                      }
                  }) else {
                unresolved=true;status="This purchase needs online recovery. It has not been finished or credited again.";return
            }
            SKPaymentQueue.default().finishTransaction(transaction)
            unresolved=true;fail("The saved order needs reconciliation before another purchase.")
        case .purchased, .restored:
            guard let id=transaction.transactionIdentifier,!id.isEmpty else {unresolved=true;return}
            guard !processing.contains(id) else{return}
            processing.insert(id);defer {processing.remove(id)}
            guard store.storageAvailable,store.state.signedIn,
                  let account=store.state.cloudAccountID,
                  let tokenString=transaction.payment.applicationUsername,let token=UUID(uuidString:tokenString),
                  let terms=store.state.coinPurchaseTerms?.first(where:{$0.token==token && $0.owner==account && $0.productID==transaction.payment.productIdentifier}),
                  terms.transactionID == nil || terms.transactionID == id else {
                unresolved=true;status="This purchase needs online recovery. It has not been finished or credited again.";return
            }
            do {
                guard let receiptURL=Bundle.main.appStoreReceiptURL,
                      let data=try? Data(contentsOf:receiptURL,options:.mappedIfSafe),
                      !data.isEmpty,data.count<=2_000_000 else {
                    unresolved=true;status="Purchase verification is pending. Use Recover purchases to try again."
                    scheduleRecovery();return
                }
                _ = try await CoffeeCloud.shared.verifyPurchase(orderID:token,transactionID:id,receiptData:data.base64EncodedString(),account:account)
                guard store.state.signedIn,store.state.cloudAccountID==account else {unresolved=true;return}
                guard store.commit({state in
                    if let index=state.coinPurchaseTerms?.firstIndex(where:{$0.token==token}) {state.coinPurchaseTerms?[index].transactionID=id}
                    if state.activePurchaseToken==token {state.activePurchaseToken=nil;state.purchaseIntents.removeValue(forKey:terms.productID)}
                }) else {unresolved=true;return}
                await store.refreshCloudWallet()
                SKPaymentQueue.default().finishTransaction(transaction)
                retryTask?.cancel();retryTask=nil;retryCount=0
                unresolved=store.state.activePurchaseToken != nil || SKPaymentQueue.default().transactions.contains(where:{$0 !== transaction})
                status="Your purchase was verified and added to your online wallet."
            } catch {unresolved=true;status="Purchase verification is pending. Use Recover purchases to try again.";scheduleRecovery()}
        @unknown default: unresolved=true
        }
    }
    func recover() async {
        guard let store,store.storageAvailable,store.accountAction==nil,!store.loginInProgress else{return}
        for transaction in SKPaymentQueue.default().transactions {await receive(transaction)}
        if store.state.activePurchaseToken != nil && SKPaymentQueue.default().transactions.isEmpty {
            unresolved=true
            status="The saved order needs reconciliation before another purchase."
        }
    }
    func sync() async {
        guard !busy,let store,store.beginCheckout() else{return}
        busy=true;defer {busy=false;store.endCheckout()}
        retryTask?.cancel();retryTask=nil;retryCount=0
        await recover()
        if SKPaymentQueue.default().transactions.isEmpty && store.state.activePurchaseToken==nil {
            status="No unfinished purchases were found."
        }
    }
    private func scheduleRecovery() {
        guard retryTask==nil,retryCount<6 else{return}
        retryCount+=1
        let delay=retryCount<3 ? 5:15
        retryTask=Task { [weak self] in
            do {try await Task.sleep(for:.seconds(delay))} catch {return}
            guard let self else{return}
            self.retryTask=nil
            await self.recover()
        }
    }
    private func fail(_ message:String) {status=message;if store?.notice==nil {store?.inform("Coffee reserve",message)}}
}
