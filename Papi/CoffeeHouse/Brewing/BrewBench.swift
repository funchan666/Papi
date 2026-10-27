import SwiftUI

struct CoffeeRatioStudioView:View {
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    private let doses=[10,15,18,20,25]
    private let ratios=[14,15,16,17,18]
    private var dose:Int {let value=store.brewBook.ratioPlan?.coffeeGrams ?? 18;return doses.contains(value) ? value:18}
    private var ratio:Int {let value=store.brewBook.ratioPlan?.partsWater ?? 16;return ratios.contains(value) ? value:16}

    var body:some View {
        PapiScreen {
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    VStack(alignment:.leading,spacing:5) {
                        PapiText("Brew calculator").font(CoffeeType.display(.title,weight:.bold))
                        PapiText("Plan your pour").font(CoffeeType.face(.subheadline)).foregroundStyle(Color.mutedCoffee)
                    }
                    PapiArtworkFill(asset:"ratioStudioArtwork").frame(height:190).clipShape(RoundedRectangle(cornerRadius:22))
                    PapiText("Choose your coffee and ratio. The water amount updates as you make changes.")
                        .font(CoffeeType.face(.subheadline)).foregroundStyle(Color.mutedCoffee).fixedSize(horizontal:false,vertical:true)
                    VStack(alignment:.leading,spacing:16) {
                        PapiText("Coffee dose").font(CoffeeType.face(.headline))
                        choices(doses,selected:dose,isRatio:false) {value in
                            store.updateBrewBook {book in
                                var plan=book.ratioPlan ?? CoffeeRatioPlan();plan.coffeeGrams=value;book.ratioPlan=plan
                            }
                        }
                        PapiText("Water ratio").font(CoffeeType.face(.headline))
                        choices(ratios,selected:ratio,isRatio:true) {value in
                            store.updateBrewBook {book in
                                var plan=book.ratioPlan ?? CoffeeRatioPlan();plan.partsWater=value;book.ratioPlan=plan
                            }
                        }
                    }.padding(18).frame(maxWidth:.infinity,alignment:.leading).background(Color.white.opacity(0.8),in:RoundedRectangle(cornerRadius:22))
                    HStack(alignment:.center,spacing:12) {
                        VStack(alignment:.leading,spacing:6) {
                            PapiText("Water to pour").font(CoffeeType.face(.subheadline,weight:.semibold))
                            PapiText("A starting point for filter coffee.").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
                        }
                        Spacer(minLength:8)
                        PapiText(verbatim:"\(dose*ratio) g").font(CoffeeType.face(.title2,weight:.bold)).monospacedDigit()
                    }.padding(18).frame(maxWidth:.infinity,alignment:.leading).background(Color.butter,in:RoundedRectangle(cornerRadius:20))
                    PapiTextButton("Explore brew recipes"){router.go(.brewBench)}.buttonStyle(PapiButtonStyle(wide:true,cornerRadius:16))
                    PapiTextButton("Open my brew book"){router.go(.brewArchive)}.buttonStyle(PapiButtonStyle(light:true,wide:true,cornerRadius:16))
                }.padding(20).frame(maxWidth:720).frame(maxWidth:.infinity)
            }
        }
    }
    private func choices(_ values:[Int],selected:Int,isRatio:Bool,select:@escaping (Int)->Void)->some View {
        ViewThatFits(in:.horizontal) {
            HStack(spacing:8) {
                ForEach(values,id:\.self) {value in
                    choice(isRatio ? "1 : \(value)":"\(value) g",selected:selected==value){select(value)}
                        .fixedSize(horizontal:true,vertical:false)
                }
            }
            LazyVGrid(columns:[GridItem(.adaptive(minimum:74),spacing:8)],spacing:8) {
                ForEach(values,id:\.self) {value in
                    choice(isRatio ? "1 : \(value)":"\(value) g",selected:selected==value){select(value)}
                }
            }
        }
    }
    private func choice(_ label:String,selected:Bool,action:@escaping ()->Void)->some View {
        Button(action:action) {
            PapiText(verbatim:label).font(CoffeeType.face(.subheadline,weight:.semibold)).fixedSize(horizontal:false,vertical:true).padding(.horizontal,12).frame(maxWidth:.infinity,minHeight:44)
                .foregroundStyle(selected ? Color.cream:Color.coffee)
                .background(selected ? Color.coffee:Color.cream,in:RoundedRectangle(cornerRadius:14))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected:[])
    }
}

struct BrewBenchView:View {
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    var body:some View {
        PapiScreen {
            VStack(spacing:0) {
                PapiHeader("Brew bench") {PapiIconButton(asset:"brewDripper",label:"My brew book"){router.go(.brewArchive)}}
                ScrollView {
                    VStack(alignment:.leading,spacing:24) {
                        BrewFrontispiece(artwork:"brewBenchArtwork",title:"One cup. Your own recipe.")
                        if let active=store.brewBook.activePour,let recipe=BrewRecipe.recipe(active.recipeID) {
                            Button {router.go(.brewRecipe(recipe.id))} label:{
                                HStack(spacing:12) {Image("brewDripper").resizable().scaledToFit().frame(width:44,height:44);VStack(alignment:.leading){PapiText("Return to your pour").font(CoffeeType.face(.headline));PapiText(verbatim:active.coffeeLot).font(CoffeeType.face(.subheadline))};Spacer();PapiText("Open").font(CoffeeType.face(.subheadline,weight:.bold))}
                                    .padding(18).background(Color.butter,in:RoundedRectangle(cornerRadius:18))
                            }.buttonStyle(.plain)
                        }
                        HStack {PapiText("The recipe shelf").font(CoffeeType.face(.title2,weight:.bold));Spacer();Button{router.openWallet()}label:{CoinLabel(value:store.state.coinBalance)}.buttonStyle(.plain)}
                        PapiText("Two recipes are yours from the start. Unlock another once, then brew it as often as you like.").font(CoffeeType.face(.subheadline)).foregroundStyle(Color.mutedCoffee)
                        ForEach(BrewRecipe.collection) {recipe in
                            Button {router.go(.brewRecipe(recipe.id))} label:{
                                VStack(alignment:.leading,spacing:10) {
                                    HStack(alignment:.firstTextBaseline,spacing:12) {PapiText(recipe.title).font(CoffeeType.face(.title3,weight:.bold));Spacer(minLength:4);if store.ownsRecipe(recipe){PapiText(recipe.unlockCoins==0 ? "Included":"On your shelf").font(CoffeeType.face(.caption,weight:.bold))}else{CoinLabel(value:recipe.unlockCoins).font(CoffeeType.face(.subheadline))}}
                                    PapiText(recipe.brewer).font(CoffeeType.face(.subheadline)).foregroundStyle(Color.mutedCoffee)
                                    PapiText("\(recipe.coffeeGrams) g coffee · \(recipe.hotWaterGrams) g hot water · \(recipe.waterCelsius) °C").font(CoffeeType.face(.caption))
                                }.frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,16)
                            }.buttonStyle(.plain).papiAvoidReserved()
                            Divider().overlay(Color.coffee.opacity(0.15))
                        }
                        Button {router.go(.cuppingFlight)} label:{
                            VStack(alignment:.leading,spacing:14) {
                                Image("tastingFlightArtwork").resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius:18))
                                HStack {PapiText("Two cups, side by side").font(CoffeeType.face(.title2,weight:.bold));Spacer();PapiText("Free").font(CoffeeType.face(.caption,weight:.bold))}
                                PapiText("Taste your own brews. Compare sweetness, brightness and body, then keep the pairing in your book.").font(CoffeeType.face(.subheadline)).foregroundStyle(Color.mutedCoffee)
                            }
                        }.buttonStyle(.plain)
                        PapiTextButton("Open my brew book"){router.go(.brewArchive)}.buttonStyle(PapiButtonStyle(wide:true))
                    }.padding(20).frame(maxWidth:760).frame(maxWidth:.infinity)
                }
            }
        }
    }
}
struct BrewFrontispiece:View {
    let artwork:String
    let title:String
    @Environment(\.layoutDirection) private var direction
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.papiBounds) private var bounds
    @ScaledMetric(relativeTo:.title2) private var artworkTextWidth:CGFloat=320
    var body:some View {
        Group {
            if direction == .rightToLeft || typeSize.isAccessibilitySize || (bounds.width>0 && bounds.width<artworkTextWidth+40) {
                VStack(alignment:.leading,spacing:16) {
                    Image(artwork).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius:22))
                    PapiText(title).font(CoffeeType.display(.title2,weight:.bold))
                }
            } else {
                Image(artwork).resizable().scaledToFit().overlay(alignment:.topLeading) {
                    PapiText(title).font(CoffeeType.display(.title2,weight:.bold)).frame(maxWidth:210,alignment:.leading).padding(18)
                }.clipShape(RoundedRectangle(cornerRadius:22))
            }
        }.accessibilityElement(children:.combine)
    }
}
struct BrewRecipeView:View {
    let recipeID:String
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    @State private var confirmUnlock=false
    @State private var confirmDiscard=false
    @State private var confirmSave=false
    private func draft(_ key:WritableKeyPath<BrewDraft,String>)->Binding<String> {
        Binding(get:{store.brewBook.draft[keyPath:key]},set:{value in store.updateBrewBook{$0.draft[keyPath:key]=String(value.prefix(100))}})
    }
    var body:some View {
        PapiScreen {
            if let recipe=BrewRecipe.recipe(recipeID) {
                VStack(spacing:0) {
                    PapiHeader(recipe.title)
                    ScrollView {
                        VStack(alignment:.leading,spacing:24) {
                            BrewFrontispiece(artwork:recipe.iceGrams>0 ? "tastingFlightArtwork":"brewBenchArtwork",title:recipe.brewer)
                            PapiText(recipe.story).font(CoffeeType.face(.body)).lineSpacing(4)
                            if let pour=store.brewBook.activePour,pour.recipeID==recipe.id {livePour(pour,recipe:recipe)}
                            else {
                                brewSetup(recipe)
                                if store.ownsRecipe(recipe) {
                                    PapiTextButton("Begin this pour") {_ = store.startPour(recipe)}.buttonStyle(PapiButtonStyle(wide:true)).disabled(store.brewBook.activePour != nil)
                                    if store.brewBook.activePour != nil {PapiText("Another pour is running. Return to it from the brew bench.").font(CoffeeType.face(.caption))}
                                } else {
                                    PapiText("Unlock once for \(recipe.unlockCoins) coins. Brewing, saving cups and tasting comparisons stay free.").font(CoffeeType.face(.subheadline))
                                    PapiTextButton("Add recipe · \(recipe.unlockCoins) coins"){confirmUnlock=true}.buttonStyle(PapiButtonStyle(wide:true))
                                }
                                pourPlan(recipe,dose:store.brewBook.draft.doseGrams)
                            }
                            PapiText("Keep hot water away from children. Use a stable brewer and a heat-safe server. Times are a starting point; let your own taste guide adjustments.").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
                        }.padding(20).frame(maxWidth:720).frame(maxWidth:.infinity)
                    }.scrollDismissesKeyboard(.interactively)
                }.overlay {
                    if confirmUnlock {PapiDialog(title:"Make room on your recipe shelf?",message:"Spend \(recipe.unlockCoins) coins to unlock this recipe for this account. Future brews using it cost no coins.",confirm:"Unlock recipe",cancel:"Keep browsing",action:{confirmUnlock=false;if store.unlockRecipe(recipe){store.notice = .init(title:"A new recipe for your shelf",message:"Your recipe is ready. Every future pour with it is free.",kind:.purchase)}},dismiss:{confirmUnlock=false})}
                    if confirmSave {PapiDialog(title:"Keep this cup?",message:"Save the elapsed brew time and recipe to your book. Add tasting notes after the cup has cooled. Saving costs no coins.",confirm:"Save this cup",cancel:"Keep brewing",action:{confirmSave=false;if store.saveBrew(){router.go(.brewArchive)}},dismiss:{confirmSave=false})}
                    if confirmDiscard {PapiDialog(title:"Clear this pour?",message:"This removes the running timer. Your bean details and unlocked recipes stay in your book.",confirm:"Clear pour",cancel:"Keep brewing",action:{confirmDiscard=false;store.discardPour()},dismiss:{confirmDiscard=false})}
                }
            } else {VStack(spacing:0){PapiHeader("Brew bench");ScrollView {PapiEmpty(title:"Recipe unavailable")}}}
        }
    }
    private func brewSetup(_ recipe:BrewRecipe)->some View {
        VStack(alignment:.leading,spacing:16) {
            PapiText("Beans on the bench").font(CoffeeType.face(.headline))
            if store.brewBook.draft.baselineCupID != nil {
                PapiText("Rebrew the same coffee. Change one detail and keep a note; the two cups will be paired for tasting.").font(CoffeeType.face(.subheadline)).foregroundStyle(Color.mutedCoffee)
                PapiTextButton("Use as a fresh cup"){store.updateBrewBook{$0.draft.baselineCupID=nil}}.font(CoffeeType.face(.subheadline,weight:.semibold)).frame(minHeight:44)
            }
            PapiInput("Roaster, origin or coffee name",text:draft(\.coffeeLot)).padding(16).background(Color.white,in:RoundedRectangle(cornerRadius:14))
            PapiInput("Grinder and setting (optional)",text:draft(\.grindNote)).padding(16).background(Color.white,in:RoundedRectangle(cornerRadius:14))
            PapiActionGroup {
                PapiTextButton("Less"){store.updateBrewBook{$0.draft.doseGrams=max(8,$0.draft.doseGrams-1)}}.buttonStyle(PapiButtonStyle(light:true)).disabled(store.brewBook.draft.doseGrams<=8)
                PapiText("\(store.brewBook.draft.doseGrams) g coffee").font(CoffeeType.face(.headline)).monospacedDigit()
                PapiTextButton("More"){store.updateBrewBook{$0.draft.doseGrams=min(40,$0.draft.doseGrams+1)}}.buttonStyle(PapiButtonStyle(light:true)).disabled(store.brewBook.draft.doseGrams>=40)
            }
            PapiText("Water: \(recipe.water(for:store.brewBook.draft.doseGrams)) g · \(recipe.waterCelsius) °C").font(CoffeeType.face(.headline))
            if recipe.iceGrams>0 {PapiText("Ice in the server: \(recipe.ice(for:store.brewBook.draft.doseGrams)) g").font(CoffeeType.face(.subheadline))}
        }
    }
    private func livePour(_ pour:PourSession,recipe:BrewRecipe)->some View {
        TimelineView(.periodic(from:.now,by:1)) {context in
            let seconds=Int(exactly:pour.elapsed(at:context.date).rounded(.down)) ?? 0
            let current=recipe.checkpoints.last(where:{$0.elapsedSeconds<=seconds}) ?? recipe.checkpoints[0]
            VStack(alignment:.leading,spacing:18) {
                PapiText(verbatim:pour.coffeeLot).font(CoffeeType.face(.headline))
                Text(String(format:"%02d:%02d",seconds/60,seconds%60)).font(CoffeeType.counter(size:60,weight:.bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65).papiAccessibilityLabel("Elapsed brew time")
                PapiText(seconds>=recipe.drawdownSeconds ? "Let the last drops settle":current.cue).font(CoffeeType.face(.title2,weight:.bold))
                PapiText("Target on the scale: \(Int((Double(recipe.water(for:pour.doseGrams))*current.cumulativeWaterFraction).rounded())) g").font(CoffeeType.face(.headline))
                PapiActionGroup {
                    PapiTextButton(pour.resumedAt==nil ? "Resume pour":"Pause timer"){store.togglePourClock()}.buttonStyle(PapiButtonStyle(light:true))
                    PapiTextButton("Keep this cup"){confirmSave=true}.buttonStyle(PapiButtonStyle()).disabled(seconds==0)
                }
                PapiText("The timer follows elapsed time while Papi is away. It does not play a background alarm.").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
                pourPlan(recipe,dose:pour.doseGrams)
                PapiTextButton("Clear this pour"){confirmDiscard=true}.font(CoffeeType.face(.subheadline)).frame(minHeight:44)
            }
        }
    }
    private func pourPlan(_ recipe:BrewRecipe,dose:Int)->some View {
        VStack(alignment:.leading,spacing:16) {
            PapiText("Your pour sequence").font(CoffeeType.face(.title3,weight:.bold))
            ForEach(recipe.checkpoints) {step in
                HStack(alignment:.top,spacing:18) {
                    Text(String(format:"%d:%02d",step.elapsedSeconds/60,step.elapsedSeconds%60)).font(CoffeeType.face(.headline)).monospacedDigit().frame(minWidth:44,alignment:.leading)
                    VStack(alignment:.leading,spacing:4) {PapiText(step.cue).font(CoffeeType.face(.subheadline));PapiText("Total water \(Int((Double(recipe.water(for:dose))*step.cumulativeWaterFraction).rounded())) g").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)}
                }
            }
            PapiText("Aim to finish around \(recipe.drawdownSeconds/60):\(String(format:"%02d",recipe.drawdownSeconds%60)).").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
        }.padding(20).frame(maxWidth:.infinity,alignment:.leading).background(Color.butter.opacity(0.6),in:RoundedRectangle(cornerRadius:18))
    }
}
struct BrewArchiveView:View {
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    var body:some View {
        PapiScreen {VStack(spacing:0) {
            PapiHeader("My brew book")
            ScrollView {VStack(alignment:.leading,spacing:22) {
                BrewFrontispiece(artwork:"brewBenchArtwork",title:"A record of your own cups.")
                if store.brewBook.cups.isEmpty {PapiEmpty(title:"The first page is yours",detail:"Begin a pour on the brew bench, then keep the cup here.")}
                ForEach(store.brewBook.cups) {cup in
                    Button {router.go(.brewCup(cup.id))} label:{BrewRecordRow(cup:cup)}.buttonStyle(.plain)
                    Divider()
                }
                PapiTextButton("Compare two cups"){router.go(.cuppingFlight)}.buttonStyle(PapiButtonStyle(wide:true))
                if !store.brewBook.flights.isEmpty {
                    PapiText("Tastings to remember").font(CoffeeType.face(.title2,weight:.bold))
                    ForEach(store.brewBook.flights) {flight in
                        if let first=store.brewBook.cups.first(where:{$0.id==flight.firstCupID}),let second=store.brewBook.cups.first(where:{$0.id==flight.secondCupID}) {
                            VStack(alignment:.leading,spacing:8) {
                                PapiText(verbatim:first.coffeeLot+" / "+second.coffeeLot).font(CoffeeType.face(.headline))
                                PapiText(flight.preferredCup.label).font(CoffeeType.face(.subheadline))
                                ForEach(flight.recordedChanges ?? []) {change in
                                    HStack {PapiText(change.variable.title).font(CoffeeType.face(.caption));Spacer();PapiText(verbatim:change.firstSetting+" / "+change.secondSetting).font(CoffeeType.face(.caption))}
                                }
                                if let firstTaste=flight.firstImpression,let secondTaste=flight.secondImpression {
                                    CupScorePair(label:"Sweetness",firstScore:firstTaste.sweetness,secondScore:secondTaste.sweetness)
                                    CupScorePair(label:"Brightness",firstScore:firstTaste.brightness,secondScore:secondTaste.brightness)
                                    CupScorePair(label:"Body",firstScore:firstTaste.body,secondScore:secondTaste.body)
                                }
                                if !flight.tastingNote.isEmpty {PapiText(verbatim:flight.tastingNote).font(CoffeeType.face(.subheadline))}
                                Text(flight.tastedAt,style:.date).font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
                            }.padding(.vertical,12)
                            Divider()
                        }
                    }
                }
            }.padding(20).frame(maxWidth:720).frame(maxWidth:.infinity)}
        }}
    }
}
struct BrewRecordRow:View {
    let cup:BrewRecord
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            HStack {PapiText(verbatim:cup.coffeeLot).font(CoffeeType.face(.headline));Spacer();Text(cup.brewedAt,style:.date).font(CoffeeType.face(.caption))}
            PapiText(BrewRecipe.recipe(cup.recipeID)?.title ?? "Coffee brew").font(CoffeeType.face(.subheadline))
            PapiText("\(cup.doseGrams) g coffee · \(cup.hotWaterGrams) g hot water · \(cup.elapsedSeconds) s").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
            PapiText(cup.impression.hasBeenTasted ? "Tasting notes added":"Ready for tasting notes").font(CoffeeType.face(.caption,weight:.bold))
        }.padding(.vertical,12).frame(maxWidth:.infinity,alignment:.leading)
    }
}
struct CupTastingView:View {
    let cupID:UUID
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete=false
    private var impression:CupImpression {store.brewBook.impressionDrafts[cupID.uuidString] ?? store.brewBook.cups.first{$0.id==cupID}?.impression ?? CupImpression()}
    private func score(_ key:WritableKeyPath<CupImpression,Int>)->Binding<Int> {Binding(get:{impression[keyPath:key]},set:{value in var draft=impression;draft[keyPath:key]=value;store.updateBrewBook{$0.impressionDrafts[cupID.uuidString]=draft}})}
    private var aroma:Binding<String> {Binding(get:{impression.aromaNote},set:{value in var draft=impression;draft.aromaNote=String(value.prefix(1000));store.updateBrewBook{$0.impressionDrafts[cupID.uuidString]=draft}})}
    var body:some View {
        PapiScreen {VStack(spacing:0) {
            PapiHeader("Taste this cup") {PapiIconButton(asset:"trash",label:"Delete brew record"){confirmDelete=true}}
            ScrollView {VStack(alignment:.leading,spacing:22) {
                if let cup=store.brewBook.cups.first(where:{$0.id==cupID}) {
                    BrewFrontispiece(artwork:"tastingFlightArtwork",title:"Let the cup cool. Take a sip.")
                    BrewRecordRow(cup:cup)
                    PapiTextButton("Brew this again") {if store.prepareRebrew(from:cup.id){router.go(.brewRecipe(cup.recipeID))}}.buttonStyle(PapiButtonStyle(light:true,wide:true))
                    if !cup.grindNote.isEmpty {PapiText(verbatim:cup.grindNote).font(CoffeeType.face(.subheadline))}
                    PapiText("Your impressions, from subtle to pronounced. These are tasting notes, not laboratory measurements.").font(CoffeeType.face(.subheadline)).foregroundStyle(Color.mutedCoffee)
                    TasteScale(title:"Sweetness",selection:score(\.sweetness))
                    TasteScale(title:"Brightness",selection:score(\.brightness))
                    TasteScale(title:"Body",selection:score(\.body))
                    PapiInput("Aroma, finish, and what you would change…",text:aroma,axis:.vertical).lineLimit(4...8).padding(18).background(Color.white,in:RoundedRectangle(cornerRadius:18))
                    PapiTextButton("Save tasting notes") {if store.saveImpression(impression,for:cupID){store.inform("Tasting notes kept","Your cup is ready for a side-by-side tasting.")}}.buttonStyle(PapiButtonStyle(wide:true))
                } else {PapiEmpty(title:"Cup unavailable")}
            }.padding(20).frame(maxWidth:720).frame(maxWidth:.infinity)}.scrollDismissesKeyboard(.interactively)
        }.overlay {if confirmDelete {PapiDialog(title:"Remove this cup from the book?",message:"Its tasting notes and comparisons containing this cup will also be removed. Unlocked recipes stay on your shelf.",confirm:"Remove cup",cancel:"Keep cup",action:{store.deleteBrew(cupID);confirmDelete=false;dismiss()},dismiss:{confirmDelete=false})}}}
    }
}
struct TasteScale:View {
    let title:String
    @Binding var selection:Int
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            PapiText(title).font(CoffeeType.face(.headline))
            LazyVGrid(columns:[GridItem(.adaptive(minimum:44),spacing:8)],spacing:8) {ForEach(1...5,id:\.self) {value in
                PapiTextButton("\(value)"){selection=value}.font(CoffeeType.face(.headline)).frame(maxWidth:.infinity,minHeight:44)
                    .background(selection==value ? Color.coffee:Color.butter,in:RoundedRectangle(cornerRadius:12))
                    .foregroundStyle(selection==value ? Color.cream:Color.coffee).accessibilityAddTraits(selection==value ? .isSelected:[]).papiAvoidReserved()
            }}
        }
    }
}
struct CupScorePair:View {
    let label:String
    let firstScore:Int
    let secondScore:Int
    var body:some View {
        HStack {PapiText(label).font(CoffeeType.face(.headline));Spacer();PapiText("\(firstScore) / 5").monospacedDigit();PapiText("·");PapiText("\(secondScore) / 5").monospacedDigit()}.padding(.vertical,8)
    }
}
struct CuppingFlightView:View {
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    private var preference:CuppingFlight.Preference {store.brewBook.comparisonPreference}
    var body:some View {
        PapiScreen {VStack(spacing:0) {
            PapiHeader("Two-cup tasting")
            ScrollView {VStack(alignment:.leading,spacing:24) {
                BrewFrontispiece(artwork:"tastingFlightArtwork",title:"Same beans? Change one thing.")
                PapiText("Choose two cups from your book. Similar beans make it easier to notice what a different pour changed.").font(CoffeeType.face(.subheadline))
                ForEach(0..<2) {slot in
                    VStack(alignment:.leading,spacing:10) {
                        PapiText(slot==0 ? "First cup":"Second cup").font(CoffeeType.face(.title3,weight:.bold))
                        let id=slot==0 ? store.brewBook.firstComparisonCup:store.brewBook.secondComparisonCup
                        if let cup=store.brewBook.cups.first(where:{$0.id==id}) {
                            BrewRecordRow(cup:cup)
                            PapiTextButton("Taste this cup"){router.go(.brewCup(cup.id))}.font(CoffeeType.face(.subheadline,weight:.bold)).frame(minHeight:44)
                        }
                        PapiTextButton("Choose a cup"){router.go(.cupChoice(slot))}.buttonStyle(PapiButtonStyle(light:true))
                    }
                    Divider()
                }
                if let first=store.brewBook.cups.first(where:{$0.id==store.brewBook.firstComparisonCup}),let second=store.brewBook.cups.first(where:{$0.id==store.brewBook.secondComparisonCup}),first.id != second.id {
                    let changes=first.recipeChanges(comparedWith:second)
                    PapiText("What changed in the recipe?").font(CoffeeType.face(.title3,weight:.bold))
                    ForEach(changes) {change in
                        VStack(alignment:.leading,spacing:6) {
                            PapiText(change.variable.title).font(CoffeeType.face(.headline))
                            PapiText(verbatim:change.firstSetting+" / "+change.secondSetting).font(CoffeeType.face(.subheadline))
                        }
                    }
                    if changes.contains(where:{$0.variable == .coffeeLot}) {
                        PapiText("Different coffee names: enjoy the tasting without treating it as a controlled recipe comparison.").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
                    } else if changes.count==1 {
                        PapiText("One recorded setting changed. Keep the other details steady when you try this pair again.").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
                    } else if changes.isEmpty {
                        PapiText("The recorded settings match. Note changes in technique, freshness or the way the cup cools.").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
                    } else {
                        PapiText("Several recorded settings changed. Try changing just one next time to make the comparison easier.").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
                    }
                    if first.impression.hasBeenTasted && second.impression.hasBeenTasted {
                        comparison("Sweetness",first.impression.sweetness,second.impression.sweetness)
                        comparison("Brightness",first.impression.brightness,second.impression.brightness)
                        comparison("Body",first.impression.body,second.impression.body)
                        PapiText("Which would you brew again?").font(CoffeeType.face(.headline))
                        ForEach(CuppingFlight.Preference.allCases,id:\.self) {choice in
                            PapiTextButton(choice.label){store.updateBrewBook{$0.comparisonPreference=choice}}.buttonStyle(PapiButtonStyle(light:preference != choice,wide:true)).accessibilityAddTraits(preference==choice ? .isSelected:[])
                        }
                    } else {PapiText("Add tasting notes to both cups before saving a comparison.").font(CoffeeType.face(.subheadline))}
                }
                PapiInput("What changed between these cups?",text:Binding(get:{store.brewBook.comparisonNote},set:{value in store.updateBrewBook{$0.comparisonNote=String(value.prefix(1000))}}),axis:.vertical).lineLimit(3...6).padding(18).background(Color.white,in:RoundedRectangle(cornerRadius:16))
                PapiTextButton("Keep this tasting") {if store.saveFlight(preference:preference){router.go(.brewArchive)}}.buttonStyle(PapiButtonStyle(wide:true))
                PapiText("Brew records and two-cup tastings are free. No coins are used here.").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
            }.padding(20).frame(maxWidth:720).frame(maxWidth:.infinity)}.scrollDismissesKeyboard(.interactively)
        }}
    }
    private func comparison(_ label:String,_ first:Int,_ second:Int)->some View {
        CupScorePair(label:label,firstScore:first,secondScore:second)
    }
}
struct BrewCupPicker:View {
    let slot:Int
    @EnvironmentObject private var store:CoffeeHouse
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        PapiScreen {VStack(spacing:0) {
            PapiHeader("Choose a cup")
            ScrollView {VStack(alignment:.leading,spacing:16) {
                if store.brewBook.cups.isEmpty {PapiEmpty(title:"Brew a cup first",detail:"Your own saved cups will appear here. Start with a recipe on the brew bench.")}
                ForEach(store.brewBook.cups) {cup in
                    let other=slot==0 ? store.brewBook.secondComparisonCup:store.brewBook.firstComparisonCup
                    Button {
                        store.updateBrewBook {if slot==0 {$0.firstComparisonCup=cup.id}else{$0.secondComparisonCup=cup.id}}
                        if store.storageAvailable {dismiss()}
                    } label:{BrewRecordRow(cup:cup)}.buttonStyle(.plain).disabled(cup.id==other).opacity(cup.id==other ? 0.45:1)
                    Divider()
                }
            }.padding(20).frame(maxWidth:720).frame(maxWidth:.infinity)}
        }}
    }
}
extension CuppingFlight.Preference {
    var label:String {switch self {case .first:return "The first cup";case .second:return "The second cup";case .both:return "Both, for different mornings";case .undecided:return "Still exploring"}}
}
