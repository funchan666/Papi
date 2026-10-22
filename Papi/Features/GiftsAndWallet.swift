import SwiftUI

struct GiftShopView:View {
    var context:String
    @EnvironmentObject private var store:PapiStore
    @EnvironmentObject private var router:PapiRouter
    @State private var selected=Gift.all[0].id
    @State private var quantity=1
    @State private var confirmCollect=false
    private var gift:Gift {Gift.all.first{$0.id==selected} ?? Gift.all[0]}
    var body:some View {
        PapiScreen {
            VStack(spacing:0) {
                PapiHeader(context=="backpack" ? "Collect a gift":"Gifts")
                ScrollView {
                    VStack(spacing:18) {
                        HStack {PapiText("My coins").font(.headline);Spacer();CoinLabel(value:store.state.coins)}
                        LazyVGrid(columns:[GridItem(.adaptive(minimum:135),spacing:12)],spacing:12) {
                            ForEach(Gift.all) {item in
                                Button {selected=item.id} label:{
                                    VStack(spacing:8) {
                                        Image(item.asset).resizable().scaledToFit().frame(height:100)
                                        PapiText(item.name).font(.subheadline).lineLimit(2).frame(minHeight:38)
                                        CoinLabel(value:item.cost).font(.caption)
                                        if selected==item.id {PapiText("Selected").font(.caption.bold())} else {PapiText(" ").font(.caption)}
                                    }.padding(12).frame(maxWidth:.infinity).background(selected==item.id ? Color.butter:Color.white.opacity(0.8),in:RoundedRectangle(cornerRadius:20))
                                }.buttonStyle(.plain)
                            }
                        }
                        HStack {
                            PapiTextButton("Less"){quantity=max(1,quantity-1)}.disabled(quantity==1)
                            Spacer();PapiText("Quantity \(quantity)").font(.headline).monospacedDigit();Spacer()
                            PapiTextButton("More"){quantity=min(99,quantity+1)}.disabled(quantity==99)
                        }.padding(15).background(Color.white,in:Capsule())
                        HStack {PapiText("Total");Spacer();CoinLabel(value:gift.cost*quantity)}
                        PapiTextButton("Collect for my backpack"){confirmCollect=true}.buttonStyle(PapiButtonStyle()).frame(maxWidth:.infinity)
                        if context != "backpack" {
                            PapiTextButton("Preview gift"){store.previewGift(gift,quantity:quantity,context:context)}.buttonStyle(PapiButtonStyle(light:true))
                            PapiText("No recipient is connected. Previewing a gift does not spend coins or send it to another person.").font(.caption).foregroundStyle(Color.mutedCoffee).multilineTextAlignment(.center)
                        }
                        PapiTextButton("Open wallet"){router.sheet=nil;router.go(.wallet)}.font(.subheadline.bold()).padding(12)
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
struct BackpackView:View {
    @EnvironmentObject private var store:PapiStore
    @EnvironmentObject private var router:PapiRouter
    var body:some View {
        PapiScreen {
            VStack(spacing:0) {
                PapiHeader(store.text("Backpack")) {PapiIconButton(asset:"plus",label:"Collect gifts"){router.go(.gifts("backpack"))}}
                ScrollView {
                    VStack(spacing:20) {
                        let owned=Gift.all.filter{(store.state.inventory[$0.id] ?? 0)>0}
                        if owned.isEmpty {
                            PapiEmpty(title:"Your collection starts here",detail:"Collect gifts with coins and display a favorite on your local profile.")
                            PapiTextButton("Explore gifts"){router.go(.gifts("backpack"))}.buttonStyle(PapiButtonStyle())
                        }
                        LazyVGrid(columns:[GridItem(.adaptive(minimum:150),spacing:12)],spacing:12) {
                            ForEach(owned) {gift in
                                VStack(spacing:9) {
                                    Image(gift.asset).resizable().scaledToFit().frame(height:110)
                                    PapiText(gift.name).font(.headline)
                                    PapiText("×\(store.state.inventory[gift.id] ?? 0)").font(.caption)
                                    PapiTextButton(store.state.displayedGift==gift.id ? "Remove display":"Display on profile") {
                                        _ = store.commit{$0.displayedGift = $0.displayedGift==gift.id ? nil:gift.id}
                                    }.font(.caption.weight(.semibold)).padding(10).background(Color.butter,in:Capsule())
                                }.padding(15).frame(maxWidth:.infinity).background(Color.white.opacity(0.75),in:RoundedRectangle(cornerRadius:20))
                            }
                        }
                        if !store.state.giftHistory.isEmpty {
                            PapiText("Gift previews").font(.headline).frame(maxWidth:.infinity,alignment:.leading)
                            ForEach(store.state.giftHistory.prefix(20)) {event in
                                if let gift=Gift.all.first(where:{$0.id==event.giftID}) {
                                    HStack {Image(gift.asset).resizable().scaledToFit().frame(width:48,height:48);VStack(alignment:.leading){PapiText("\(gift.name) × \(event.quantity)");PapiText("Not sent · No coins spent").font(.caption).foregroundStyle(Color.mutedCoffee)};Spacer()}.padding(12).background(Color.white,in:RoundedRectangle(cornerRadius:15))
                                }
                            }
                        }
                    }.padding(20).frame(maxWidth:850).frame(maxWidth:.infinity)
                }
            }
        }
    }
}
struct WalletView:View {
    @EnvironmentObject private var store:PapiStore
    @EnvironmentObject private var commerce:PapiCommerce
    @State private var selected=CoinPack.all[0].id
    var body:some View {
        PapiScreen {
            VStack(spacing:0) {
                PapiHeader("Recharge")
                ScrollView {
                    VStack(spacing:18) {
                        HStack(alignment:.center) {
                            VStack(alignment:.leading,spacing:8) {PapiText("My coins:").font(.headline);Text(store.state.coins,format:.number).font(.system(size:35,weight:.heavy,design:.rounded)).monospacedDigit()}
                            Spacer()
                        }.padding(24).frame(minHeight:118).foregroundStyle(.white).background{Image("walletCard").resizable()}
                        PapiText("Coins can be used for your local posts and gift collection.").font(.caption).foregroundStyle(Color.mutedCoffee).multilineTextAlignment(.center)
                        ForEach(CoinPack.all) {pack in
                            Button {selected=pack.id} label:{
                                HStack(spacing:14) {
                                    Image("coin").resizable().scaledToFit().frame(width:32,height:32)
                                    VStack(alignment:.leading,spacing:4) {
                                        PapiText("\(pack.coins) coins").font(.title3.weight(.semibold))
                                        PapiText(commerce.products.first(where:{$0.id==pack.id})?.displayPrice ?? "Not available yet").font(.caption)
                                    }
                                    Spacer()
                                    PapiText(selected==pack.id ? "Selected":"GET").font(.caption.bold()).padding(.horizontal,15).padding(.vertical,10).background(Color.peach,in:Capsule())
                                }.padding(16).background(selected==pack.id ? Color.butter:Color.white,in:RoundedRectangle(cornerRadius:16))
                            }.buttonStyle(.plain)
                        }
                        PapiText(commerce.status).font(.subheadline).multilineTextAlignment(.center).foregroundStyle(Color.mutedCoffee)
                        PapiTextButton(commerce.busy ? "Processing…":"Continue") {
                            if let pack=CoinPack.all.first(where:{$0.id==selected}){Task{await commerce.buy(pack)}}
                        }.buttonStyle(PapiButtonStyle()).disabled(!PapiCommerce.purchasesConfigured || commerce.busy || commerce.unresolved || commerce.products.first(where:{$0.id==selected})==nil)
                        HStack {
                            PapiTextButton("Reload products"){Task{await commerce.load()}}.disabled(commerce.busy)
                            Spacer()
                            PapiTextButton("Recover purchases"){Task{await commerce.sync()}}.disabled(!PapiCommerce.purchasesConfigured || commerce.busy)
                        }.font(.caption).padding(.vertical,8)
                        PapiText("Consumable coins belong to this local guest. They do not sync between devices. Deleting the guest removes its spendable balance; purchase ownership records are kept to prevent duplicate delivery.").font(.caption2).foregroundStyle(Color.mutedCoffee)
                        PapiText("Wallet activity").font(.headline).frame(maxWidth:.infinity,alignment:.leading)
                        if store.state.wallet.isEmpty {PapiEmpty(title:"No transactions yet",detail:"Daily check-in is a free way to start collecting coins.")}
                        ForEach(store.state.wallet.prefix(40)) {entry in
                            HStack {VStack(alignment:.leading,spacing:3){PapiText(entry.reason).font(.subheadline);Text(entry.createdAt,style:.date).font(.caption2).foregroundStyle(Color.mutedCoffee)};Spacer();PapiText(entry.delta>0 ? "+\(entry.delta)":"\(entry.delta)").monospacedDigit().fontWeight(.semibold)}.padding(14).background(Color.white,in:RoundedRectangle(cornerRadius:12))
                        }
                    }.padding(20).frame(maxWidth:640).frame(maxWidth:.infinity)
                }
            }
        }.task{await commerce.load()}
    }
}
struct CheckinView:View {
    @EnvironmentObject private var store:PapiStore
    var body:some View {
        PapiScreen {
            VStack(spacing:0) {
                PapiHeader(store.text("Check in"))
                ScrollView {
                    VStack(spacing:24) {
                        PapiText("Check in Rewards").font(.system(size:30,weight:.heavy,design:.serif)).italic()
                        PapiText("A little reward for your daily ritual.").font(.subheadline)
                        LazyVGrid(columns:[GridItem(.adaptive(minimum:70),spacing:8)],spacing:12) {
                            ForEach(0..<7) {i in
                                VStack(spacing:12) {
                                    PapiText("Day \(i+1)").font(.caption2)
                                    Image("coin").resizable().scaledToFit().frame(width:30,height:30)
                                    PapiText("\((i+1)*10)").font(.headline)
                                    if i < store.state.checkinDays.count%7 {Image("check").resizable().scaledToFit().frame(width:15,height:15)}
                                }.padding(.vertical,15).frame(maxWidth:.infinity).background(i==store.state.checkinDays.count%7 ? Color.butter:Color.white,in:RoundedRectangle(cornerRadius:15))
                            }
                        }
                        PapiText("Seven check-ins complete a reward cycle. Each day starts at 00:00 UTC; missed days do not reset your collection.").font(.caption).multilineTextAlignment(.center).foregroundStyle(Color.mutedCoffee)
                        PapiTextButton(store.checkedInToday ? "Checked in today":"Check in · \(store.nextCheckinReward) coins"){store.checkIn()}.buttonStyle(PapiButtonStyle()).disabled(store.checkedInToday)
                        PapiText("\(store.state.checkinDays.count) days collected").font(.caption)
                    }.padding(22).frame(maxWidth:600).frame(maxWidth:.infinity)
                }
            }
        }
    }
}
struct LevelView:View {
    @EnvironmentObject private var store:PapiStore
    var body:some View {
        PapiScreen {
            VStack(spacing:22) {
                PapiHeader("My Level")
                VStack(alignment:.leading,spacing:16) {
                    HStack {Avatar(name:store.state.profile.avatar,size:48);PapiText(verbatim:store.state.profile.name).font(.title3.bold());Spacer()}
                    PapiText("Lv.\(store.state.experience/100+1)").font(.system(size:32,weight:.heavy,design:.rounded))
                    ProgressView(value:Double(store.state.experience%100),total:100).tint(.coffee)
                    PapiText("\(store.state.experience%100)/100 EXP").font(.caption)
                }.padding(24).frame(minHeight:205).background{Image("levelCard").resizable()}.padding(.horizontal,20)
                PapiText("Your Coffee Journey").font(.title3.bold())
                PapiText("Check in for 20 EXP. Save a local coffee post for 10 EXP. Every 100 EXP brings a new level.").font(.subheadline).multilineTextAlignment(.center).padding(.horizontal,30)
                PapiText("Progress is saved with this local guest.").font(.caption).foregroundStyle(Color.mutedCoffee)
                Spacer()
            }.frame(maxWidth:650).frame(maxWidth:.infinity)
        }
    }
}
