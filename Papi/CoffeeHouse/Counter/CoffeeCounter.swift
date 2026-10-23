import SwiftUI
import StoreKit

struct CollectibleCounterView:View {
    var context:String
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    @State private var selected=CoffeeCollectible.all[0].id
    @State private var quantity=1
    @State private var confirmCollect=false
    private var gift:CoffeeCollectible {CoffeeCollectible.all.first{$0.id==selected} ?? CoffeeCollectible.all[0]}
    var body:some View {
        PapiScreen {
            VStack(spacing:0) {
                PapiHeader(context=="backpack" ? "Collect a gift":"Gifts")
                ScrollView {
                    VStack(spacing:18) {
                        HStack {PapiText("My coins").font(CoffeeType.face(.headline));Spacer();CoinLabel(value:store.state.coinBalance)}
                        LazyVGrid(columns:[GridItem(.adaptive(minimum:135),spacing:12)],spacing:12) {
                            ForEach(CoffeeCollectible.all) {item in
                                Button {selected=item.id} label:{
                                    VStack(spacing:8) {
                                        Image(item.asset).resizable().scaledToFit().frame(height:100)
                                        PapiText(item.name).font(CoffeeType.face(.subheadline)).lineLimit(2).frame(minHeight:38)
                                        CoinLabel(value:item.cost).font(CoffeeType.face(.caption))
                                        if selected==item.id {PapiText("Selected").font(CoffeeType.face(.caption,weight:.bold))} else {PapiText(" ").font(CoffeeType.face(.caption))}
                                    }.padding(12).frame(maxWidth:.infinity).background(selected==item.id ? Color.butter:Color.white.opacity(0.8),in:RoundedRectangle(cornerRadius:20))
                                }.buttonStyle(.plain)
                            }
                        }
                        HStack {
                            PapiTextButton("Less"){quantity=max(1,quantity-1)}.disabled(quantity==1)
                            Spacer();PapiText("Quantity \(quantity)").font(CoffeeType.face(.headline)).monospacedDigit();Spacer()
                            PapiTextButton("More"){quantity=min(99,quantity+1)}.disabled(quantity==99)
                        }.padding(15).background(Color.white,in:Capsule())
                        HStack {PapiText("Total");Spacer();CoinLabel(value:gift.cost*quantity)}
                        PapiTextButton("Collect for my backpack"){confirmCollect=true}.buttonStyle(PapiButtonStyle()).frame(maxWidth:.infinity)
                        if context != "backpack" {
                            PapiTextButton("Preview gift"){store.previewGift(gift,quantity:quantity,context:context)}.buttonStyle(PapiButtonStyle(light:true))
                            PapiText("No recipient is connected. Previewing a gift does not spend coins or send it to another person.").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee).multilineTextAlignment(.center)
                        }
                        PapiTextButton("Open wallet"){router.openWallet()}.font(CoffeeType.face(.subheadline,weight:.bold)).padding(12)
                    }.padding(20).frame(maxWidth:800).frame(maxWidth:.infinity)
                }
            }.overlay {
                if confirmCollect {
                    PapiDialog(title:"Collect \(gift.name)?",message:"Spend \(gift.cost*quantity) coins to add \(quantity) to your local backpack. You can display an owned gift on your profile.",confirm:"Collect",cancel:"Cancel",action:{confirmCollect=false;if store.collect(gift,quantity:quantity){store.inform("Added to your backpack","\(gift.name) × \(quantity) is saved to this guest's collection.")}},dismiss:{confirmCollect=false})
                }
            }
        }
    }
}
struct CoffeeCollectionView:View {
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    var body:some View {
        PapiScreen {
            VStack(spacing:0) {
                PapiHeader(store.text("Backpack")) {PapiIconButton(asset:"plus",label:"Collect gifts"){router.go(.gifts("backpack"))}}
                ScrollView {
                    VStack(spacing:20) {
                        let owned=CoffeeCollectible.all.filter{(store.state.collectiblesOwned[$0.id] ?? 0)>0}
                        if owned.isEmpty {
                            PapiEmpty(title:"A little shelf of coffee keepsakes",detail:"Collect a keepsake with coins, then display your favourite on your coffee passport.")
                            PapiTextButton("Explore gifts"){router.go(.gifts("backpack"))}.buttonStyle(PapiButtonStyle())
                        }
                        LazyVGrid(columns:[GridItem(.adaptive(minimum:150),spacing:12)],spacing:12) {
                            ForEach(owned) {gift in
                                VStack(spacing:9) {
                                    Image(gift.asset).resizable().scaledToFit().frame(height:110)
                                    PapiText(gift.name).font(CoffeeType.face(.headline))
                                    PapiText("×\(store.state.collectiblesOwned[gift.id] ?? 0)").font(CoffeeType.face(.caption))
                                    PapiTextButton(store.state.displayedGift==gift.id ? "Remove display":"Display on profile") {
                                        _ = store.commit{$0.displayedGift = $0.displayedGift==gift.id ? nil:gift.id}
                                    }.font(CoffeeType.face(.caption,weight:.semibold)).padding(10).background(Color.butter,in:Capsule())
                                }.padding(15).frame(maxWidth:.infinity).background(Color.white.opacity(0.75),in:RoundedRectangle(cornerRadius:20))
                            }
                        }
                        if !store.state.giftHistory.isEmpty {
                            PapiText("Gift previews").font(CoffeeType.face(.headline)).frame(maxWidth:.infinity,alignment:.leading)
                            ForEach(store.state.giftHistory.prefix(20)) {event in
                                if let gift=CoffeeCollectible.all.first(where:{$0.id==event.giftID}) {
                                    HStack {Image(gift.asset).resizable().scaledToFit().frame(width:48,height:48);VStack(alignment:.leading){PapiText("\(gift.name) × \(event.quantity)");PapiText("Not sent · No coins spent").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)};Spacer()}.padding(12).background(Color.white,in:RoundedRectangle(cornerRadius:15))
                                }
                            }
                        }
                    }.padding(20).frame(maxWidth:850).frame(maxWidth:.infinity)
                }
            }
        }
    }
}
struct CoinReserveView:View {
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var commerce:AppleCoinCounter
    @Environment(\.purchase) private var purchase
    @State private var selected=CoinPack.all[0].id
    private var pack:CoinPack {CoinPack.all.first{$0.id==selected} ?? CoinPack.all[0]}
    var body:some View {
        PapiScreen {
            VStack(spacing:0) {
                PapiHeader("Recharge")
                HStack(spacing:14) {
                    Image("coin").resizable().scaledToFit().frame(width:40,height:40).accessibilityHidden(true)
                    VStack(alignment:.leading,spacing:3) {
                        PapiText("Coffee reserve").font(CoffeeType.face(.caption,weight:.semibold))
                        Text(store.state.coinBalance,format:.number).font(CoffeeType.face(.largeTitle,weight:.heavy)).monospacedDigit().contentTransition(.numericText())
                    }
                    Spacer(minLength:4)
                    PapiText("Live balance").font(CoffeeType.face(.caption)).multilineTextAlignment(.trailing)
                }.foregroundStyle(Color.cream).padding(18).background(Color.coffee,in:RoundedRectangle(cornerRadius:22)).padding(.horizontal,20).padding(.bottom,12).papiAvoidReserved()
                ScrollView {
                    VStack(alignment:.leading,spacing:22) {
                        VStack(alignment:.leading,spacing:6) {
                            PapiText("Choose your next pour").font(CoffeeType.display(.title2,weight:.bold)).italic()
                            PapiText("Reference prices are in USD. Apple confirms your local price before payment.").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
                        }
                        LazyVGrid(columns:[GridItem(.adaptive(minimum:145),spacing:12)],spacing:12) {
                            ForEach(CoinPack.all) {item in
                                Button {selected=item.id} label:{packTile(item)}.buttonStyle(.plain).disabled(commerce.busy)
                                    .accessibilityAddTraits(selected==item.id ? .isSelected:[])
                            }
                        }
                        PapiText(commerce.status).font(CoffeeType.face(.subheadline)).foregroundStyle(Color.mutedCoffee).accessibilityAddTraits(.updatesFrequently)
                        PapiTextButton("Recover purchases"){Task{await commerce.sync()}}.font(CoffeeType.face(.subheadline,weight:.bold)).frame(minHeight:44).disabled(commerce.busy || !store.storageAvailable)
                        spendingGuide
                        PapiText("Consumable coins belong to this local guest. They do not sync between devices. Deleting the guest removes its spendable balance; purchase ownership records are kept to prevent duplicate delivery.").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
                        VStack(alignment:.leading,spacing:12) {
                            PapiText("Wallet activity").font(CoffeeType.face(.headline))
                            if store.state.coinMovements.isEmpty {PapiEmpty(title:"No transactions yet",detail:"Daily check-in is a free way to start collecting coins.")}
                            ForEach(store.state.coinMovements.prefix(40)) {entry in
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
                VStack(spacing:8) {
                    PapiTextButton(commerce.busy ? "Connecting to Apple…":"Buy \(pack.coins) coins") {
                        let selectedPack=pack
                        Task {await commerce.buy(selectedPack,purchase:{product,options in try await purchase(product,options:options)})}
                    }.buttonStyle(PapiButtonStyle(wide:true)).disabled(commerce.busy || commerce.unresolved || !store.storageAvailable || !store.state.purchaseIntents.isEmpty || store.state.activePurchaseToken != nil)
                    PapiText("Apple confirms the price · No coins before verified payment").font(CoffeeType.face(.caption2)).multilineTextAlignment(.center).foregroundStyle(Color.mutedCoffee)
                }.padding(.horizontal,20).padding(.vertical,12).frame(maxWidth:680).frame(maxWidth:.infinity).background(Color.cream).papiAvoidReserved()
            }
        }
    }
    private func packTile(_ item:CoinPack)->some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                Image("coin").resizable().scaledToFit().frame(width:28,height:28).accessibilityHidden(true)
                Spacer(minLength:0)
                if selected==item.id {Image("check").resizable().scaledToFit().frame(width:18,height:18).accessibilityHidden(true)}
            }
            Text(item.coins,format:.number).font(CoffeeType.face(.title2,weight:.heavy)).monospacedDigit()
            PapiText("coins").font(CoffeeType.face(.caption))
            if let product=commerce.products.first(where:{$0.id==item.id}) {
                Text(verbatim:product.displayPrice).font(CoffeeType.face(.headline))
                PapiText("Price from Apple").font(CoffeeType.face(.caption2))
            } else {
                PapiText("USD reference $\(item.referenceUSD)").font(CoffeeType.face(.subheadline,weight:.semibold))
            }
            PapiText(selected==item.id ? "Selected":"Select pack").font(CoffeeType.face(.caption,weight:.semibold))
        }.foregroundStyle(Color.coffee).frame(maxWidth:.infinity,alignment:.leading).padding(16)
            .background(selected==item.id ? Color.butter:Color.white.opacity(0.85),in:RoundedRectangle(cornerRadius:18)).papiAvoidReserved()
    }
    private var spendingGuide:some View {
        VStack(alignment:.leading,spacing:16) {
            PapiText("Where your coins go").font(CoffeeType.display(.title2,weight:.bold))
            ForEach(BrewRecipe.collection.filter{$0.unlockCoins>0}) {recipe in
                usage(recipe.title,cost:recipe.unlockCoins)
            }
            PapiText("Recipe unlocks are a one-time purchase for this account. Reusing recipes, saving brews and two-cup tastings are free.").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
            Divider()
            usage("Photo moment submission",cost:CoffeeEconomy.postCost(isVideo:false))
            usage("Video moment submission",cost:CoffeeEconomy.postCost(isVideo:true))
            PapiText("A submission saves a private coffee moment. It does not buy approval or public visibility; community review is not connected.").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
            Divider()
            ForEach(CoffeeCollectible.all) {gift in
                HStack(spacing:12) {
                    Image(gift.asset).resizable().scaledToFit().frame(width:36,height:36).accessibilityHidden(true)
                    PapiText(gift.name).font(CoffeeType.face(.subheadline))
                    Spacer(minLength:4)
                    CoinLabel(value:gift.cost).font(CoffeeType.face(.subheadline))
                }
            }
            PapiText("Gifts are optional backpack collectibles. Displaying an owned gift and gift previews are free.").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
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
    @Environment(\.papiRegions) private var regions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared=false
    var body:some View {
        GeometryReader {proxy in
            let origin=proxy.frame(in:.named("PapiContainer")).origin
            let rect=PapiRegionGeometry.largestArea(in:CGRect(origin:.zero,size:proxy.size),excluding:regions.map{$0.offsetBy(dx:-origin.x,dy:-origin.y)})
            ZStack {
                Color.coffee.opacity(0.72).ignoresSafeArea().onTapGesture{}
                ScrollView {
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
                            Text((store.state.welcomeGrant?.coins ?? 0),format:.number.sign(strategy:.always())).font(CoffeeType.counter(size:58,weight:.heavy)).monospacedDigit().minimumScaleFactor(0.7)
                        }
                        PapiText("Welcome coins · Already added").font(CoffeeType.face(.subheadline,weight:.semibold))
                        PapiText("A first cup, a few coffee moments, something for your collection. Make this corner yours.").font(CoffeeType.face(.body)).lineSpacing(4)
                        HStack(spacing:10) {Image("check").resizable().scaledToFit().frame(width:20,height:20);PapiText("Saved to this guest · Once only").font(CoffeeType.face(.caption,weight:.bold))}
                        PapiText("Chat, voice and video calls are always free.").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
                        PapiTextButton("Start my coffee ritual",action:close).buttonStyle(PapiButtonStyle(wide:true,cornerRadius:14))
                    }.padding(26).background{Image("dialogBackground").resizable()}
                }.frame(width:min(390,max(44,rect.width-24)),height:min(690,max(44,rect.height-24)))
                    .scaleEffect(appeared || reduceMotion ? 1:0.96).opacity(appeared || reduceMotion ? 1:0.7).position(x:rect.midX,y:rect.midY)
            }.foregroundStyle(Color.coffee)
        }.onAppear {withAnimation(reduceMotion ? nil:.spring(response:0.6,dampingFraction:0.68)){appeared=true}}
            .accessibilityAddTraits(.isModal)
    }
}
struct DailyRitualView:View {
    @EnvironmentObject private var store:CoffeeHouse
    var body:some View {
        PapiScreen {
            VStack(spacing:0) {
                PapiHeader(store.text("Check in"))
                ScrollView {
                    VStack(spacing:24) {
                        PapiText("Check in Rewards").font(CoffeeType.display(size:30,weight:.heavy)).italic()
                        PapiText("A little reward for your daily ritual.").font(CoffeeType.face(.subheadline))
                        LazyVGrid(columns:[GridItem(.adaptive(minimum:70),spacing:8)],spacing:12) {
                            ForEach(0..<7) {i in
                                VStack(spacing:12) {
                                    PapiText("Day \(i+1)").font(CoffeeType.face(.caption2))
                                    Image("coin").resizable().scaledToFit().frame(width:30,height:30)
                                    PapiText("\((i+1)*10)").font(CoffeeType.face(.headline))
                                    if i < store.state.checkinDays.count%7 {Image("check").resizable().scaledToFit().frame(width:15,height:15)}
                                }.padding(.vertical,15).frame(maxWidth:.infinity).background(i==store.state.checkinDays.count%7 ? Color.butter:Color.white,in:RoundedRectangle(cornerRadius:15))
                            }
                        }
                        PapiText("Seven check-ins complete a reward cycle. Each day starts at 00:00 UTC; missed days do not reset your collection.").font(CoffeeType.face(.caption)).multilineTextAlignment(.center).foregroundStyle(Color.mutedCoffee)
                        PapiTextButton(store.checkedInToday ? "Checked in today":"Check in · \(store.nextCheckinReward) coins"){store.checkIn()}.buttonStyle(PapiButtonStyle()).disabled(store.checkedInToday)
                        PapiText("\(store.state.checkinDays.count) days collected").font(CoffeeType.face(.caption))
                    }.padding(22).frame(maxWidth:600).frame(maxWidth:.infinity)
                }
            }
        }
    }
}
struct CoffeeJourneyView:View {
    @EnvironmentObject private var store:CoffeeHouse
    var body:some View {
        PapiScreen {
            VStack(spacing:22) {
                PapiHeader("My Level")
                VStack(alignment:.leading,spacing:16) {
                    HStack {Avatar(name:store.state.passport.avatar,size:48);PapiText(verbatim:store.state.passport.name).font(CoffeeType.face(.title3,weight:.bold));Spacer()}
                    PapiText("Lv.\(store.state.experience/100+1)").font(CoffeeType.counter(size:32,weight:.heavy))
                    ProgressView(value:Double(store.state.experience%100),total:100).tint(.coffee)
                    PapiText("\(store.state.experience%100)/100 EXP").font(CoffeeType.face(.caption))
                }.padding(24).frame(minHeight:205).background{Image("levelCard").resizable()}.padding(.horizontal,20)
                PapiText("Your Coffee Journey").font(CoffeeType.face(.title3,weight:.bold))
                PapiText("Check in for 20 EXP. Save a local coffee post for 10 EXP. Every 100 EXP brings a new level.").font(CoffeeType.face(.subheadline)).multilineTextAlignment(.center).padding(.horizontal,30)
                PapiText("Your coffee journey stays with this account.").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
                Spacer()
            }.frame(maxWidth:650).frame(maxWidth:.infinity)
        }
    }
}
