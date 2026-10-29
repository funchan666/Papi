import SwiftUI
import StoreKit

struct CollectibleCounterView:View {
    @ScaledMetric(relativeTo:.body) private var giftColumnWidth:CGFloat=96
    @ScaledMetric(relativeTo:.body) private var compactHeight:CGFloat=550
    var context:String
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.verticalSizeClass) private var heightClass
    @State private var selected="love"
    @State private var quantity=1
    @State private var confirmCollect=false
    private var gift:CoffeeCollectible? {CoffeeCollectible.all.first{$0.id==selected} ?? CoffeeCollectible.all.first}
    var body:some View {
        Group {
        if (!store.usesCloudWallet || store.cloudGiftsReady),let gift {
        PapiScreen {
            GeometryReader {viewport in
                let width=max(0,min(680,viewport.size.width)-32)
                let columns=typeSize.isAccessibilitySize ? 1:(width >= giftColumnWidth*3+16 ? 3:(width >= giftColumnWidth*2+8 ? 2:1))
                let inlineActions=typeSize.isAccessibilitySize || heightClass == .compact || viewport.size.height<compactHeight || width<240
                VStack(spacing:0) {
                    PapiHeader(context=="backpack" ? "Collect a gift":"Gifts")
                    ScrollView {
                        VStack(alignment:.leading,spacing:14) {
                            giftIntroduction
                            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:8),count:columns),spacing:8) {
                                ForEach(CoffeeCollectible.all) {item in
                                    Button {selected=item.id} label:{giftTile(item)}.buttonStyle(.plain).disabled(store.state.pendingCloudCollectible != nil)
                                        .accessibilityAddTraits(selected==item.id ? .isSelected:[])
                                }
                            }
                            if inlineActions {giftActions(gift)}
                        }.padding(.horizontal,16).padding(.top,10).padding(.bottom,16).frame(maxWidth:680).frame(maxWidth:.infinity)
                    }
                    if !inlineActions {giftActions(gift).padding(.horizontal,16).padding(.bottom,10).frame(maxWidth:680).frame(maxWidth:.infinity)}
                }
            }.overlay {
                if confirmCollect {
                    PapiDialog(title:"Collect \(gift.name)?",message:"Spend \(gift.cost*quantity) coins to add \(quantity) to your backpack. You can display an owned gift on your profile.",confirm:"Collect",cancel:"Cancel",action:{let selectedGift=gift;let selectedQuantity=quantity;confirmCollect=false;if store.usesCloudWallet {Task {await store.cloudCollect(selectedGift,quantity:selectedQuantity)}} else if store.collect(selectedGift,quantity:selectedQuantity){store.inform("Added to your backpack","\(selectedGift.name) × \(selectedQuantity) is saved to this guest's collection.")}},dismiss:{confirmCollect=false})
                }
            }
        }
        } else {
            PapiScreen {VStack(spacing:16) {PapiHeader("Gifts");PapiText(store.cloudSocialBusy ? "Loading gifts…":"Gifts unavailable");PapiTextButton("Retry"){Task {await store.refreshCloudSocial()}}.disabled(store.cloudSocialBusy);Spacer()}}
        }
        }.onAppear {
            if let pending=store.state.pendingCloudCollectible,pending.accountID==store.state.cloudAccountID {
                selected=pending.item;quantity=pending.quantity
            }
        }
    }
    private var giftIntroduction:some View {
        HStack(spacing:12) {
            VStack(alignment:.leading,spacing:6) {
                PapiText("Collect a gift").font(CoffeeType.display(.title2,weight:.bold))
                PapiTextButton("Open wallet"){router.openWallet()}.font(CoffeeType.face(.caption,weight:.bold))
                    .padding(.horizontal,12).frame(minHeight:44).background(Color.cream.opacity(0.9),in:Capsule())
            }.frame(maxWidth:.infinity,alignment:.leading)
            VStack(alignment:.trailing,spacing:4) {
                PapiArtworkFit(asset:"giftCounterArt").frame(width:72,height:60)
                CoffeeCurrentBalance().font(CoffeeType.face(.subheadline,weight:.bold))
                PapiText("My coins").font(CoffeeType.face(.caption2)).foregroundStyle(Color.mutedCoffee)
            }
        }.padding(.horizontal,16).padding(.vertical,12).frame(maxWidth:.infinity)
            .background(Color.cream.opacity(0.85),in:RoundedRectangle(cornerRadius:20)).papiAvoidReserved()
    }
    private func giftTile(_ item:CoffeeCollectible)->some View {
        let isSelected=selected==item.id
        return VStack(spacing:5) {
            PapiArtworkFit(asset:item.asset).frame(height:62)
            PapiText(item.name).font(CoffeeType.face(.caption,weight:.semibold)).multilineTextAlignment(.center).lineLimit(2).frame(maxWidth:.infinity,minHeight:34)
            CoinLabel(value:item.cost).font(CoffeeType.face(.caption2,weight:.semibold))
            PapiText(isSelected ? "Selected":" ").font(CoffeeType.face(.caption2,weight:.bold)).foregroundStyle(Color.coffee)
        }.padding(.horizontal,6).padding(.vertical,10).frame(maxWidth:.infinity,minHeight:144)
            .background(isSelected ? Color.butter:Color.cream.opacity(0.9),in:RoundedRectangle(cornerRadius:16))
            .overlay(RoundedRectangle(cornerRadius:16).stroke(isSelected ? Color.coffee.opacity(0.55):Color.clear,lineWidth:1.5))
            .contentShape(RoundedRectangle(cornerRadius:16)).papiAvoidReserved()
    }
    private func giftActions(_ gift:CoffeeCollectible)->some View {
        VStack(spacing:8) {
            HStack(spacing:8) {
                PapiTextButton("Less"){quantity=max(1,quantity-1)}.frame(minWidth:44,minHeight:44).disabled(quantity==1 || store.state.pendingCloudCollectible != nil)
                PapiText("Quantity \(quantity)").font(CoffeeType.face(.subheadline,weight:.semibold)).monospacedDigit().frame(maxWidth:.infinity)
                PapiTextButton("More"){quantity=min(99,quantity+1)}.frame(minWidth:44,minHeight:44).disabled(quantity==99 || store.state.pendingCloudCollectible != nil)
            }
            HStack(spacing:8) {
                PapiText(gift.name).font(CoffeeType.face(.caption,weight:.semibold)).lineLimit(2)
                Spacer(minLength:8)
                PapiText("Total").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
                CoinLabel(value:gift.cost*quantity).font(CoffeeType.face(.subheadline,weight:.bold))
            }
            PapiTextButton("Collect for my backpack"){confirmCollect=true}.buttonStyle(PapiButtonStyle(wide:true,cornerRadius:16)).disabled(store.usesCloudWallet && (store.cloudWallet==nil || store.cloudWalletBusy))
            if store.state.pendingCloudCollectible != nil {
                PapiText("Retry the saved selection to confirm your purchase.").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
            }
            if store.usesCloudWallet && store.cloudWallet==nil {
                PapiTextButton("Retry wallet"){Task {await store.refreshCloudWallet()}}.disabled(store.cloudWalletBusy)
            }
            if context != "backpack" {
                PapiTextButton("Save gift idea") {if store.usesCloudWallet {let selectedGift=gift;let selectedQuantity=quantity;Task {await store.saveCloudGiftIdea(selectedGift,quantity:selectedQuantity,context:context)}} else {store.previewGift(gift,quantity:quantity,context:context)}}
                    .font(CoffeeType.face(.subheadline,weight:.bold)).frame(maxWidth:.infinity,minHeight:44)
                    .disabled(store.usesCloudWallet && (store.cloudGiftIdeas==nil || store.cloudGiftIdeasBusy))
                if store.usesCloudWallet && store.cloudGiftIdeas==nil {PapiTextButton("Retry ideas"){Task {await store.refreshCloudGiftIdeas()}}.disabled(store.cloudGiftIdeasBusy)}
                PapiText("Gift ideas are not sent and do not cost coins.").font(CoffeeType.face(.caption2)).foregroundStyle(Color.mutedCoffee).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
            }
        }.padding(12).frame(maxWidth:.infinity).background(Color.cream.opacity(0.97),in:RoundedRectangle(cornerRadius:20)).papiAvoidReserved()
    }
}
struct CoffeeCollectionView:View {
    @ScaledMetric(relativeTo:.body) private var giftColumnWidth:CGFloat=150
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    var body:some View {
        PapiScreen {
            VStack(spacing:0) {
                PapiHeader(store.text("Backpack")) {PapiIconButton(asset:"plus",label:"Collect gifts"){router.go(.gifts("backpack"))}}
                ScrollView {
                    VStack(spacing:20) {
                        let owned=(!store.usesCloudWallet || store.cloudGiftsReady) ? CoffeeCollectible.all.filter{(store.collectedItems[$0.id] ?? 0)>0}:[]
                        CoffeeSectionIntro(artwork:"passportKeepsakeArt",title:"My backpack",detail:"Collect a keepsake with coins, then display your favourite on your coffee passport.")
                        if store.usesCloudWallet && !store.cloudGiftsReady {
                            PapiTextButton("Retry gifts"){Task {await store.refreshCloudSocial()}}.disabled(store.cloudSocialBusy)
                        } else if store.usesCloudWallet && store.cloudWallet==nil {
                            PapiTextButton("Retry wallet"){Task {await store.refreshCloudWallet()}}.disabled(store.cloudWalletBusy)
                        } else if owned.isEmpty {
                            PapiEmpty(title:"A little shelf of coffee keepsakes")
                            PapiTextButton("Explore gifts"){router.go(.gifts("backpack"))}.buttonStyle(PapiButtonStyle(wide:true,cornerRadius:16))
                        }
                        LazyVGrid(columns:[GridItem(.adaptive(minimum:giftColumnWidth),spacing:12)],spacing:12) {
                            ForEach(owned) {gift in
                                VStack(spacing:9) {
                                    PapiArtworkFit(asset:gift.asset).frame(height:110)
                                    PapiText(gift.name).font(CoffeeType.face(.headline))
                                    PapiText("×\(store.collectedItems[gift.id] ?? 0)").font(CoffeeType.face(.caption))
                                    let displayed=store.usesCloudWallet ? store.cloudDisplayedGift:store.state.displayedGift
                                    PapiTextButton(displayed==gift.id ? "Remove display":"Display on profile") {
                                        let next=displayed==gift.id ? nil:gift.id
                                        if store.usesCloudWallet {Task {await store.setCloudDisplayedGift(next)}} else {_ = store.commit{$0.displayedGift=next}}
                                    }.font(CoffeeType.face(.caption,weight:.semibold)).padding(10).background(Color.butter,in:Capsule())
                                        .disabled(store.usesCloudWallet && (!store.cloudDisplayedGiftReady || store.cloudDisplayedGiftBusy))
                                }.padding(15).frame(maxWidth:.infinity).background(Color.white.opacity(0.75),in:RoundedRectangle(cornerRadius:20))
                            }
                        }
                        if store.usesCloudWallet && !store.cloudDisplayedGiftReady {PapiTextButton("Retry display"){Task {await store.refreshCloudDisplayedGift()}}.disabled(store.cloudDisplayedGiftBusy)}
                        if store.usesCloudWallet && store.cloudGiftIdeas==nil {PapiTextButton("Retry ideas"){Task {await store.refreshCloudGiftIdeas()}}.disabled(store.cloudGiftIdeasBusy)}
                        if store.usesCloudWallet,store.cloudGiftsReady,let ideas=store.cloudGiftIdeas,!ideas.isEmpty {
                            PapiText("Gift ideas").font(CoffeeType.face(.headline)).frame(maxWidth:.infinity,alignment:.leading)
                            ForEach(ideas) {event in
                                if let gift=CoffeeCollectible.all.first(where:{$0.id==event.gift_id}) {giftIdeaRow(gift,quantity:event.quantity)}
                            }
                        } else if !store.usesCloudWallet && !store.state.giftHistory.isEmpty {
                            PapiText("Gift ideas").font(CoffeeType.face(.headline)).frame(maxWidth:.infinity,alignment:.leading)
                            ForEach(store.state.giftHistory.prefix(20)) {event in
                                if let gift=CoffeeCollectible.all.first(where:{$0.id==event.giftID}) {giftIdeaRow(gift,quantity:event.quantity)}
                            }
                        }
                    }.padding(20).frame(maxWidth:850).frame(maxWidth:.infinity)
                }
            }
        }
    }
    private func giftIdeaRow(_ gift:CoffeeCollectible,quantity:Int)->some View {
        HStack {Image(gift.asset).resizable().scaledToFit().frame(width:48,height:48);VStack(alignment:.leading){PapiText("\(gift.name) × \(quantity)");PapiText("Not sent · No coins spent").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)};Spacer()}.padding(12).background(Color.white,in:RoundedRectangle(cornerRadius:15))
    }
}
struct CoinReserveView:View {
    @ScaledMetric(relativeTo:.body) private var packColumnWidth:CGFloat=98
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var commerce:AppleCoinCounter
    @Environment(\.scenePhase) private var phase
    @State private var visible=false
    @State private var activeScene=false
    @State private var purchaseVisitID=UUID()
    @Environment(\.verticalSizeClass) private var heightClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.papiBounds) private var bounds
    @ScaledMetric(relativeTo:.body) private var purchaseViewportHeight:CGFloat=300
    private var inlinePurchase:Bool {heightClass == .compact || typeSize.isAccessibilitySize || (bounds.height>0 && bounds.height<purchaseViewportHeight)}
    @State private var selected=CoinPack.all[0].id
    private var pack:CoinPack {CoinPack.all.first{$0.id==selected} ?? CoinPack.all[0]}
    var body:some View {
        PapiScreen {
            GeometryReader {viewport in
                let contentWidth=max(0,min(680,viewport.size.width)-40)
                let columnCount=typeSize.isAccessibilitySize ? 1:(contentWidth >= packColumnWidth*3+20 ? 3:(contentWidth >= packColumnWidth*2+10 ? 2:1))
                VStack(spacing:0) {
                    PapiHeader("Recharge")
                    ScrollView {
                        VStack(alignment:.leading,spacing:18) {
                            let balanceLayout=typeSize.isAccessibilitySize || contentWidth<280 ? AnyLayout(VStackLayout(alignment:.leading,spacing:10)):AnyLayout(HStackLayout(spacing:12))
                            balanceLayout {
                                HStack(spacing:12) {
                                    Image("coin").resizable().scaledToFit().frame(width:34,height:34).accessibilityHidden(true)
                                    VStack(alignment:.leading,spacing:3) {
                                        PapiText("Coffee reserve").font(CoffeeType.face(.caption,weight:.semibold))
                                        if let balance=store.availableBalance {Text(balance,format:.number).font(CoffeeType.face(.title,weight:.heavy)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5).contentTransition(.numericText())}
                                        else {PapiText(store.cloudWalletBusy ? "Loading wallet…":"Wallet unavailable").font(CoffeeType.face(.subheadline))}
                                    }
                                }.frame(maxWidth:.infinity,alignment:.leading)
                                PapiArtworkFit(asset:"passportReserveArt").frame(width:typeSize.isAccessibilitySize ? 50:74,height:typeSize.isAccessibilitySize ? 50:74)
                            }.foregroundStyle(Color.cream).padding(16).frame(maxWidth:.infinity,alignment:.leading).background(Color.coffee,in:RoundedRectangle(cornerRadius:20)).papiAvoidReserved()
                            VStack(alignment:.leading,spacing:6) {
                                PapiText("Choose your next pour").font(CoffeeType.display(.title2,weight:.bold)).italic()
                                PapiText("Reference prices are in USD. Apple confirms your local price before payment.").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
                            }
                            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:10),count:columnCount),spacing:10) {
                                ForEach(CoinPack.all) {item in
                                    Button {selected=item.id} label:{packTile(item)}.buttonStyle(.plain).disabled(commerce.busy)
                                        .accessibilityAddTraits(selected==item.id ? .isSelected:[])
                                }
                            }
                            if inlinePurchase {purchasePanel}
                            PapiText(commerce.status).font(CoffeeType.face(.subheadline)).foregroundStyle(Color.mutedCoffee).accessibilityAddTraits(.updatesFrequently)
                            PapiTextButton("Recover purchases"){Task{await commerce.sync()}}.font(CoffeeType.face(.subheadline,weight:.bold)).frame(minHeight:44).disabled(commerce.busy || !store.storageAvailable)
                            spendingGuide
                            if store.usesCloudWallet {
                                if store.cloudWallet==nil {PapiTextButton("Retry wallet"){Task {await store.refreshCloudWallet()}}.disabled(store.cloudWalletBusy)}
                            } else {
                                PapiText("Coins do not sync between devices. Deleting your account removes its balance; purchase records are kept to prevent duplicate delivery.").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
                            }
                            VStack(alignment:.leading,spacing:12) {
                                PapiText("Wallet activity").font(CoffeeType.face(.headline))
                                if store.usesCloudWallet {
                                    if let wallet=store.cloudWallet {
                                        if wallet.movements.isEmpty {PapiEmpty(title:"No transactions yet",detail:"Daily check-in is a free way to start collecting coins.")}
                                        ForEach(wallet.movements) {entry in
                                            HStack(spacing:12) {
                                                VStack(alignment:.leading,spacing:3) {
                                                    PapiText(entry.reason).font(CoffeeType.face(.subheadline))
                                                    if let date=entry.date {Text(date,style:.date).font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)}
                                                }
                                                Spacer(minLength:4)
                                                Text(entry.delta,format:.number.sign(strategy:.always())).monospacedDigit().fontWeight(.semibold)
                                            }.padding(.vertical,12)
                                            Divider().overlay(Color.coffee.opacity(0.15))
                                        }
                                    }
                                } else if store.state.coinMovements.isEmpty {PapiEmpty(title:"No transactions yet",detail:"Daily check-in is a free way to start collecting coins.")}
                                ForEach(store.usesCloudWallet ? []:Array(store.state.coinMovements.prefix(40))) {entry in
                                    HStack(spacing:12) {
                                        VStack(alignment:.leading,spacing:3) {PapiText(entry.reason).font(CoffeeType.face(.subheadline));Text(entry.createdAt,style:.date).font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)}
                                        Spacer(minLength:4)
                                        Text(entry.delta,format:.number.sign(strategy:.always())).monospacedDigit().fontWeight(.semibold)
                                    }.padding(.vertical,12)
                                    Divider().overlay(Color.coffee.opacity(0.15))
                                }
                            }
                        }.padding(20).frame(maxWidth:680).frame(maxWidth:.infinity)
                    }
                    if !inlinePurchase {purchasePanel}
                }
            }
        }.onAppear{purchaseVisitID=UUID();visible=true;activeScene=phase == .active}
            .onDisappear{visible=false;purchaseVisitID=UUID()}
            .onChange(of:phase){_,value in activeScene=value == .active;if value != .active {purchaseVisitID=UUID()}}
    }
    private var purchasePanel:some View {
        VStack(spacing:8) {
            PapiTextButton(commerce.busy ? "Connecting to Apple…":"Buy \(pack.coins) coins") {
                let selectedPack=pack
                let visit=purchaseVisitID
                Task {await commerce.buy(selectedPack,canPresent:{visible && activeScene && purchaseVisitID==visit})}
            }.buttonStyle(PapiButtonStyle(wide:true)).disabled(!commerce.checkoutAvailable || commerce.busy || commerce.unresolved || !store.storageAvailable || !store.usesCloudWallet || !store.state.purchaseIntents.isEmpty || store.state.activePurchaseToken != nil)
            PapiText("Apple confirms the price · No coins before verified payment").font(CoffeeType.face(.caption2)).multilineTextAlignment(.center).foregroundStyle(Color.mutedCoffee)
        }.padding(.horizontal,20).padding(.vertical,12).frame(maxWidth:680).frame(maxWidth:.infinity).background(Color.cream).papiAvoidReserved()
    }
    private func packTile(_ item:CoinPack)->some View {
        VStack(alignment:.leading,spacing:6) {
            HStack {
                Image("coin").resizable().scaledToFit().frame(width:23,height:23).accessibilityHidden(true)
                Spacer(minLength:0)
                if selected==item.id {Image("check").resizable().scaledToFit().frame(width:16,height:16).accessibilityHidden(true)}
            }
            Text(item.coins,format:.number).font(CoffeeType.face(.title3,weight:.heavy)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            PapiText("coins").font(CoffeeType.face(.caption2))
            if let price=commerce.displayPrice(for:item.id) {
                Text(verbatim:price).font(CoffeeType.face(.subheadline,weight:.bold)).fixedSize(horizontal:false,vertical:true)
                PapiText("Price from Apple").font(CoffeeType.face(.caption2)).fixedSize(horizontal:false,vertical:true)
            } else {
                Text(verbatim:"$"+item.referenceUSD).font(CoffeeType.face(.subheadline,weight:.bold))
                PapiText("USD reference").font(CoffeeType.face(.caption2)).fixedSize(horizontal:false,vertical:true)
            }
        }.foregroundStyle(Color.coffee).frame(maxWidth:.infinity,alignment:.leading).padding(11).frame(maxWidth:.infinity,minHeight:132,alignment:.topLeading)
            .background(selected==item.id ? Color.butter:Color.white.opacity(0.85),in:RoundedRectangle(cornerRadius:16)).papiAvoidReserved()
    }
    private var spendingGuide:some View {
        VStack(alignment:.leading,spacing:16) {
            PapiText("Where your coins go").font(CoffeeType.display(.title2,weight:.bold))
            ForEach((!store.usesCloudWallet || store.cloudRecipesReady) ? BrewRecipe.collection.filter{$0.unlockCoins>0}:[]) {recipe in
                usage(recipe.title,cost:recipe.unlockCoins)
            }
            PapiText("Recipe unlocks are a one-time purchase for this account. Reusing recipes, saving brews and two-cup tastings are free.").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
            Divider()
            usage("Photo moment submission",cost:CoffeeEconomy.postCost(isVideo:false))
            usage("Video moment submission",cost:CoffeeEconomy.postCost(isVideo:true))
            PapiText("A submission saves a private coffee moment. It does not buy approval or public visibility; community review is not connected.").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
            Divider()
            ForEach((!store.usesCloudWallet || store.cloudGiftsReady) ? CoffeeCollectible.all:[]) {gift in
                HStack(spacing:12) {
                    Image(gift.asset).resizable().scaledToFit().frame(width:36,height:36).accessibilityHidden(true)
                    PapiText(gift.name).font(CoffeeType.face(.subheadline))
                    Spacer(minLength:4)
                    CoinLabel(value:gift.cost).font(CoffeeType.face(.subheadline))
                }
            }
            PapiText("Gifts are optional backpack collectibles. Displaying an owned gift and saving gift ideas are free.").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
            if store.usesCloudWallet && (!store.cloudRecipesReady || !store.cloudGiftsReady) {
                PapiTextButton("Retry prices"){Task {await store.refreshCloudSocial()}}.disabled(store.cloudSocialBusy)
            }
            VStack(alignment:.leading,spacing:7) {
                PapiText("Conversation is always free").font(CoffeeType.face(.headline))
                PapiText("Text, photos, voice messages, video calls, follows and friend requests never cost coins. Mutual consent still applies.").font(CoffeeType.face(.subheadline))
            }.padding(16).frame(maxWidth:.infinity,alignment:.leading).background(Color.butter,in:RoundedRectangle(cornerRadius:16))
            PapiText("Daily check-in is free and adds coins to this balance.").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
        }
    }
    private func usage(_ name:String,cost:Int)->some View {
        HStack {PapiText(name).font(CoffeeType.face(.subheadline));Spacer(minLength:4);CoinLabel(value:cost).font(CoffeeType.face(.subheadline))}
    }
}
struct WelcomeCoinsView:View {
    var close:()->Void
    @EnvironmentObject private var store:CoffeeHouse
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared=false
    var body:some View {
        CoffeeModal(maximumWidth:390,maximumHeight:690,shade:Color.coffee.opacity(0.72)) {
            VStack(alignment:.leading,spacing:20) {
                HStack(alignment:.top) {
                    VStack(alignment:.leading,spacing:5) {
                        PapiText("Papi").font(CoffeeType.display(size:32,weight:.bold)).italic()
                        PapiText("FIRST BREW / WELCOME TICKET").font(CoffeeType.face(.caption,weight:.bold)).tracking(1)
                    }
                    Spacer(minLength:4)
                    Image("brandMark").resizable().scaledToFit().frame(width:76,height:76).clipShape(RoundedRectangle(cornerRadius:20)).rotationEffect(.degrees(appeared || reduceMotion ? 5:-8)).scaleEffect(appeared || reduceMotion ? 1:0.85).accessibilityHidden(true)
                }
                Divider().overlay(Color.coffee.opacity(0.3))
                PapiText("Your first brew is on Papi").font(CoffeeType.display(.largeTitle,weight:.heavy)).fixedSize(horizontal:false,vertical:true)
                HStack(alignment:.center,spacing:12) {
                    Image("coin").resizable().scaledToFit().frame(width:48,height:48).scaleEffect(appeared || reduceMotion ? 1:0.55).accessibilityHidden(true)
                    Text((store.state.welcomeGrant?.coins ?? 0),format:.number.sign(strategy:.always())).font(CoffeeType.counter(size:58,weight:.heavy)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.35)
                }
                PapiText("Welcome coins · Already added").font(CoffeeType.face(.subheadline,weight:.semibold))
                PapiText("A first cup, a few coffee moments, something for your collection. Make this corner yours.").font(CoffeeType.face(.body)).lineSpacing(4)
                HStack(spacing:10) {Image("check").resizable().scaledToFit().frame(width:20,height:20);PapiText("Saved to this guest · Once only").font(CoffeeType.face(.caption,weight:.bold))}
                PapiText("Chat, voice and video calls are always free.").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
                PapiTextButton("Start my coffee ritual",action:close).buttonStyle(PapiButtonStyle(wide:true,cornerRadius:14))
            }
        }.onAppear {withAnimation(reduceMotion ? nil:.spring(response:0.6,dampingFraction:0.68)){appeared=true}}
    }
}
struct DailyRitualView:View {
    @EnvironmentObject private var store:CoffeeHouse
    var body:some View {
        PapiScreen {
            VStack(spacing:0) {
                PapiHeader(store.text("Check in"))
                ScrollView {
                    VStack(spacing:20) {
                        CoffeeSectionIntro(artwork:"passportRitualArt",title:"Check in Rewards",detail:"A little reward for your daily ritual.")
                        let completed=store.checkedInToday && store.checkinCount>0 && store.checkinCount%7==0 ? 7:store.checkinCount%7
                        if !store.usesCloudWallet || store.cloudWallet != nil {
                            LazyVGrid(columns:[GridItem(.adaptive(minimum:70),spacing:8)],spacing:12) {
                                ForEach(0..<7) {i in
                                    VStack(spacing:12) {
                                        PapiText("Day \(i+1)").font(CoffeeType.face(.caption2))
                                        Image("coin").resizable().scaledToFit().frame(width:30,height:30)
                                        PapiText("\((i+1)*10)").font(CoffeeType.face(.headline))
                                        if i < completed {Image("check").resizable().scaledToFit().frame(width:15,height:15)}
                                    }.padding(.vertical,15).frame(maxWidth:.infinity).background(!store.checkedInToday && i==completed ? Color.butter:Color.white,in:RoundedRectangle(cornerRadius:15))
                                }
                            }
                        }
                        PapiText("Seven check-ins complete a reward cycle. Each day starts at 00:00 UTC; missed days do not reset your collection.").font(CoffeeType.face(.caption)).multilineTextAlignment(.center).foregroundStyle(Color.mutedCoffee)
                        if store.usesCloudWallet && store.cloudWallet==nil {
                            PapiTextButton("Retry wallet"){Task {await store.refreshCloudWallet()}}.disabled(store.cloudWalletBusy)
                        } else {
                            PapiTextButton(store.checkedInToday ? "Checked in today":"Check in · \(store.nextCheckinReward) coins"){if store.usesCloudWallet {Task {await store.cloudCheckIn()}} else {store.checkIn()}}.buttonStyle(PapiButtonStyle(wide:true,cornerRadius:16)).disabled(store.checkedInToday || store.cloudWalletBusy)
                            PapiText("\(store.checkinCount) days collected").font(CoffeeType.face(.caption))
                        }
                    }.padding(22).frame(maxWidth:600).frame(maxWidth:.infinity)
                }
            }
        }
    }
}
struct CoffeeJourneyView:View {
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    var body:some View {
        PapiScreen {
            VStack(spacing:22) {
                PapiHeader("My Level")
                ScrollView {
                    VStack(spacing:18) {
                        CoffeeSectionIntro(artwork:"passportBrewArt",title:"Your Coffee Journey",detail:"Your coffee journey stays with this account.").padding(.horizontal,20)
                        VStack(alignment:.leading,spacing:16) {
                            HStack {Avatar(name:store.visiblePassport.portraitReference,size:48);PapiText(verbatim:store.visiblePassport.name).font(CoffeeType.face(.title3,weight:.bold));Spacer()}
                            if let experience=store.currentExperience {
                                PapiText("Lv.\(experience/100+1)").font(CoffeeType.counter(size:32,weight:.heavy))
                                ProgressView(value:Double(experience%100),total:100).tint(.coffee)
                                PapiText("\(experience%100)/100 EXP").font(CoffeeType.face(.caption))
                            } else {PapiTextButton("Retry wallet"){Task {await store.refreshCloudWallet()}}.disabled(store.cloudWalletBusy)}
                        }.padding(24).frame(minHeight:205).background{PapiArtworkFill(asset:"levelCard")}.padding(.horizontal,20)
                        PapiText("Check in for 20 EXP. Save a coffee post for 10 EXP. Every 100 EXP brings a new level.").font(CoffeeType.face(.subheadline)).multilineTextAlignment(.leading).fixedSize(horizontal:false,vertical:true).padding(16).frame(maxWidth:.infinity,alignment:.leading).background(Color.white.opacity(0.9),in:RoundedRectangle(cornerRadius:18)).padding(.horizontal,20)
                        PapiTextButton("Open my brew book"){router.go(.brewArchive)}.buttonStyle(PapiButtonStyle(light:true,wide:true,cornerRadius:16)).padding(.horizontal,20)
                    }.padding(.bottom,20)
                }
            }.frame(maxWidth:650).frame(maxWidth:.infinity)
        }
    }
}
