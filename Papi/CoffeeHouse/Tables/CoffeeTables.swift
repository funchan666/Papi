import SwiftUI
import AVFoundation

private struct TableDemoEvent:Identifiable {
    let id=UUID()
    let memberID:String
    let message:String
    let giftAsset:String?
}
@MainActor private final class TableSampleVoice:ObservableObject {
    private let speaker=AVSpeechSynthesizer()
    func play(_ text:String,language:String) {
        speaker.stopSpeaking(at:.immediate)
        let utterance=AVSpeechUtterance(string:text)
        utterance.voice=AVSpeechSynthesisVoice(language:language)
        speaker.speak(utterance)
    }
    func stop() {speaker.stopSpeaking(at:.immediate)}
}

struct CoffeeTablesView:View {
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var filter=0
    private var rooms:[CoffeeTable] {
        CoffeeTable.previews.filter {room in
            store.isRoomVisible(room) && (filter==0 || (filter==1 && store.state.followedMembers.contains(room.hostMemberID)) || (filter==2 && store.state.recentRooms.contains(room.id)))
        }.sorted {a,b in
            guard filter==2 else{return a.id<b.id}
            return (store.state.recentRooms.firstIndex(of:a.id) ?? 99)<(store.state.recentRooms.firstIndex(of:b.id) ?? 99)
        }
    }
    var body:some View {
        PapiScreen {
            GeometryReader {geo in
                let topInset=geo.safeAreaInsets.top
                let bannerHeight=(typeSize.isAccessibilitySize ? 260:min(230,max(180,geo.size.width*0.48)))+topInset
                let contentWidth=max(0,min(1100,geo.size.width)-32)
                let columnCount=typeSize.isAccessibilitySize || contentWidth<330 ? 1:min(4,max(1,Int((contentWidth+12)/170)))
                ScrollView {
                    VStack(spacing:0) {
                        ZStack(alignment:.topLeading) {
                            Image("coffeeAudioHero").resizable().scaledToFill()
                                .frame(width:geo.size.width,height:bannerHeight,alignment:.trailing).clipped()
                                .overlay(Color.cream.opacity(0.38)).accessibilityHidden(true)
                            VStack(alignment:.leading,spacing:8) {
                                PapiText("Coffee tables").font(CoffeeType.display(.largeTitle,weight:.bold)).fixedSize(horizontal:false,vertical:true)
                                PapiText("Around the coffee table").font(CoffeeType.face(.subheadline,weight:.medium)).fixedSize(horizontal:false,vertical:true)
                            }.padding(14).background(Color.cream.opacity(0.92),in:RoundedRectangle(cornerRadius:18))
                                .padding(.horizontal,20).padding(.top,topInset+18).frame(maxWidth:480,alignment:.leading).papiAvoidReserved()
                        }.frame(width:geo.size.width,height:bannerHeight)
                        VStack(alignment:.leading,spacing:16) {
                            HStack(spacing:4) {
                                ForEach(0..<3) {i in
                                    Button {filter=i} label:{
                                        PapiText(["All","Following","Recent"][i]).font(CoffeeType.face(.subheadline,weight:.medium)).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
                                            .frame(maxWidth:.infinity,minHeight:44).background(filter==i ? Color.peach:Color.clear,in:RoundedRectangle(cornerRadius:14)).contentShape(Rectangle())
                                    }.buttonStyle(.plain).foregroundStyle(filter==i ? Color.white:Color.mutedCoffee).accessibilityAddTraits(filter==i ? .isSelected:[])
                                }
                            }.padding(5).background(Color.white.opacity(0.88),in:RoundedRectangle(cornerRadius:19))
                            HStack(spacing:8) {
                                PapiArtworkFit(asset:"audioTableMark").frame(width:32,height:32)
                                PapiText("Sample rooms · Voices, messages and gifts").font(CoffeeType.face(.caption)).fixedSize(horizontal:false,vertical:true)
                            }.foregroundStyle(Color.mutedCoffee).frame(maxWidth:.infinity,alignment:.leading)
                            if let id=store.activeRoomID,let room=CoffeeTable.previews.first(where:{$0.id==id}),store.isRoomVisible(room) {
                                Button {router.go(.room(id))} label:{HStack {Image("voiceOn").resizable().scaledToFit().frame(width:26,height:26);PapiText("Return to \(room.title)");Spacer();PapiText("Open")}.padding(12).background(Color.butter,in:RoundedRectangle(cornerRadius:15))}.buttonStyle(.plain)
                            }
                            if rooms.isEmpty {PapiEmpty(title:filter==1 ? "No followed rooms yet":"No recent rooms",detail:"Open a coffee topic to keep it here.")}
                            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:12),count:columnCount),spacing:14) {
                                ForEach(rooms) {room in
                                    roomCard(room)
                                }
                            }
                        }.padding(.horizontal,16).padding(.top,16).padding(.bottom,24).frame(maxWidth:1100).frame(maxWidth:.infinity)
                    }
                }.ignoresSafeArea(.container,edges:.top).contentMargins(.top,0,for:.scrollContent)
            }
        }
    }
    private func roomCard(_ room:CoffeeTable)->some View {
        VStack(alignment:.leading,spacing:0) {
            Button {if store.enter(room){router.go(.room(room.id))}} label:{
                VStack(alignment:.leading,spacing:0) {
                    ZStack(alignment:.topLeading) {
                        PapiArtworkFill(asset:room.image).frame(height:150).clipped()
                        HStack(spacing:4) {
                            PapiArtworkFit(asset:"audioTableMark").frame(width:26,height:26)
                            PapiText("Coffee topic").font(CoffeeType.face(.caption2,weight:.bold)).fixedSize(horizontal:false,vertical:true)
                        }.padding(.horizontal,8).padding(.vertical,4).background(Color.cream.opacity(0.94),in:Capsule()).padding(9)
                    }
                    VStack(alignment:.leading,spacing:5) {
                        PapiText(room.title).font(CoffeeType.face(.headline)).fixedSize(horizontal:false,vertical:true)
                        PapiText(room.category).font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee).fixedSize(horizontal:false,vertical:true)
                        PapiText("Sample room").font(CoffeeType.face(.caption2,weight:.medium)).foregroundStyle(Color.mutedCoffee).fixedSize(horizontal:false,vertical:true)
                    }.padding(12).frame(maxWidth:.infinity,alignment:.leading)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if let portrait=store.person(room.hostMemberID),!store.isUserHidden(portrait.id) {
                Button {router.go(.person(portrait.id))} label:{
                    HStack(spacing:8) {
                        Avatar(name:portrait.portrait,size:32)
                        VStack(alignment:.leading,spacing:2) {
                            PapiText(verbatim:portrait.name).font(CoffeeType.face(.caption,weight:.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                            PapiText("Coffee portrait").font(CoffeeType.face(.caption2)).foregroundStyle(Color.mutedCoffee).lineLimit(1)
                        }.frame(maxWidth:.infinity,alignment:.leading)
                    }.frame(maxWidth:.infinity,minHeight:44,alignment:.leading).contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.horizontal,12).padding(.bottom,10)
            }
        }.frame(maxWidth:.infinity,alignment:.leading).background(Color.white.opacity(0.95),in:RoundedRectangle(cornerRadius:20)).clipShape(RoundedRectangle(cornerRadius:20))
    }
}
struct CoffeeTableView:View {
    let room:CoffeeTable
    @Environment(\.papiBounds) private var bounds
    @ScaledMetric(relativeTo:.headline) private var headingLineHeight:CGFloat=24
    private var compactControls:Bool {bounds.height>0 && bounds.height<headingLineHeight*10}
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @StateObject private var sampleVoice=TableSampleVoice()
    @State private var leave=false
    @State private var noteAnnouncement:TableNoteEntry?
    @State private var giftAnnouncement:GiftPreview?
    @State private var observedGiftID:String?
    @State private var giftTrackingReady=false
    @State private var demoEvents:[TableDemoEvent]=[]
    @State private var demoIndex=0
    @State private var demoGiftAnnouncement:TableDemoEvent?
    private var demoMembers:[CoffeeMember] {
        let available=CoffeeMember.portraits.filter{!store.isUserHidden($0.id) && $0.id != room.hostMemberID}
        guard !available.isEmpty else{return []}
        let offset=(CoffeeTable.previews.firstIndex(where:{$0.id==room.id}) ?? 0)%available.count
        return Array((Array(available[offset...])+Array(available[..<offset])).prefix(3))
    }
    private var draft:Binding<String> {Binding(get:{store.state.tableNotes[room.id] ?? ""},set:{new in _ = store.commit{$0.tableNotes[room.id]=String(new.prefix(2000))}})}
    var body:some View {
        PapiScreen(background:"roomBackground") {
            VStack(spacing:0) {
                HStack(spacing:8) {
                    Button {router.go(.person(room.hostMemberID))} label:{
                        HStack {Avatar(name:CoffeeMember.find(room.hostMemberID)?.portrait ?? "brandMark",size:42);PapiText(room.title).font(CoffeeType.face(.headline)).lineLimit(compactControls ? 1:2)}
                    }.buttonStyle(.plain)
                    Spacer(minLength:0)
                    PapiIconButton(asset:"moreLight",label:"Report room") {router.sheet = .safety(.init(kind:.room,contentReference:room.id,authorID:room.hostMemberID))}
                    PapiIconButton(asset:"close",label:"Leave room") {sampleVoice.stop();leave=true}
                }.padding(.horizontal,16).padding(.vertical,8).foregroundStyle(.white).papiAvoidReserved()
                ScrollViewReader {reader in
                ScrollView {
                    VStack(alignment:.leading,spacing:18) {
                        VStack(spacing:12) {
                            HStack {
                                HStack(spacing:6) {
                                    PapiArtworkFit(asset:"audioTableMark").frame(width:24,height:24)
                                    PapiText("Sample room").font(CoffeeType.face(.caption,weight:.bold))
                                }.foregroundStyle(Color.coffee).padding(.horizontal,10).padding(.vertical,5).background(Color.cream.opacity(0.96),in:Capsule())
                                Spacer(minLength:0)
                            }
                            if let portrait=store.person(room.hostMemberID),!store.isUserHidden(portrait.id) {
                                Button {router.go(.person(portrait.id))} label:{
                                    VStack(spacing:6) {
                                        Avatar(name:portrait.portrait,size:72)
                                        PapiText(verbatim:portrait.name).font(CoffeeType.face(.headline)).lineLimit(2).multilineTextAlignment(.center)
                                    }.frame(minWidth:88,minHeight:88).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                            PapiText(room.title).font(CoffeeType.display(.title2,weight:.bold)).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
                            PapiText(room.category).font(CoffeeType.face(.caption,weight:.semibold)).foregroundStyle(Color.cream.opacity(0.85))
                        }.padding(18).frame(maxWidth:.infinity,minHeight:250)
                            .background {ZStack {PapiArtworkFill(asset:room.image);Color.coffee.opacity(0.68)}}
                            .clipShape(RoundedRectangle(cornerRadius:22))
                        demoStage
                        ForEach(store.state.giftHistory.filter{$0.context==room.id}.prefix(6)) {event in
                            if let gift=CoffeeCollectible.all.first(where:{$0.id==event.giftID}) {
                                HStack {Image(gift.asset).resizable().scaledToFit().frame(width:42,height:42);PapiText("\(gift.name) × \(event.quantity)");Spacer();PapiText("Not sent").font(CoffeeType.face(.caption))}.padding(10).background(Color.white.opacity(0.12),in:RoundedRectangle(cornerRadius:15))
                            }
                        }
                    }.padding(20).frame(maxWidth:820).frame(maxWidth:.infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge:.bottom,spacing:0) {
                    PapiInputBar {
                        VStack(alignment:.leading,spacing:5) {
                            if !compactControls {PapiText("Only you can see these notes").font(CoffeeType.face(.caption,weight:.bold)).foregroundStyle(Color.cream)}
                            PapiInput("A thought for the coffee table…",text:draft,axis:.vertical).lineLimit(1...3).foregroundStyle(Color.coffee).tint(Color.coffee).padding(12).background(Color.cream,in:RoundedRectangle(cornerRadius:18))
                        }
                    } actions: {
                        HStack(spacing:8) {
                            PapiIconButton(asset:"roomNoteButton",label:"Keep table note",size:36) {
                                if store.keepTableNote(room),let saved=store.state.tableNoteHistory?[room.id]?.last {
                                    withAnimation(reduceMotion ? nil:.easeOut(duration:0.3)){noteAnnouncement=saved}
                                }
                            }.disabled(draft.wrappedValue.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                                .opacity(draft.wrappedValue.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? 0.45:1)
                            PapiIconButton(asset:"roomGiftButton",label:"Gifts",size:36) {router.sheet = .gifts(room.id)}
                        }
                    }
                }
                .onChange(of:store.state.tableNoteHistory?[room.id]?.count ?? 0) {_,_ in
                    if let id=store.state.tableNoteHistory?[room.id]?.last?.id {
                        withAnimation(reduceMotion ? nil:.easeOut(duration:0.25)){reader.scrollTo(id,anchor:.bottom)}
                    }
                }
                }
            }.foregroundStyle(.white)
            .overlay {
                if leave {PapiDialog(title:"Leave the room?",message:"Your draft and room history will be kept.",confirm:"Leave room",cancel:"Stay here",action:{store.activeRoomID=nil;store.roomMicRequested=false;dismiss()},dismiss:{leave=false})}

            }
            .overlay(alignment:.topLeading) {
                if !leave,let event=giftAnnouncement,let gift=CoffeeCollectible.all.first(where:{$0.id==event.giftID}) {
                    HStack(spacing:10) {
                        Image(gift.asset).resizable().scaledToFit().frame(width:44,height:44).accessibilityHidden(true)
                        VStack(alignment:.leading,spacing:3) {
                            PapiText("Gift idea · Not sent").font(CoffeeType.face(.caption,weight:.bold))
                            PapiText("\(gift.name) × \(event.quantity)").font(CoffeeType.face(.subheadline))
                        }
                    }.foregroundStyle(Color.cream).padding(12).background(Color.coffee.opacity(0.94),in:RoundedRectangle(cornerRadius:18))
                        .padding(.horizontal,16).padding(.top,70).transition(reduceMotion ? .opacity:.move(edge:.leading).combined(with:.opacity)).allowsHitTesting(false).papiAvoidReserved()
                } else if !leave,let note=noteAnnouncement {
                    HStack(alignment:.top,spacing:8) {
                        Avatar(name:store.state.passport.portraitReference,size:32)
                        VStack(alignment:.leading,spacing:3) {
                            PapiText("Only you can see these notes").font(CoffeeType.face(.caption,weight:.bold))
                            PapiText(verbatim:note.text).font(CoffeeType.face(.subheadline)).lineLimit(2)
                        }
                    }.foregroundStyle(Color.cream).padding(10).background(Color.coffee.opacity(0.94),in:RoundedRectangle(cornerRadius:16))
                        .padding(.horizontal,16).padding(.top,70).transition(reduceMotion ? .opacity:.move(edge:.trailing).combined(with:.opacity)).allowsHitTesting(false).papiAvoidReserved()
                } else if !leave,let event=demoGiftAnnouncement,!store.isUserHidden(event.memberID),let member=store.person(event.memberID),let asset=event.giftAsset {
                    HStack(spacing:10) {
                        Avatar(name:member.portrait,size:32)
                        VStack(alignment:.leading,spacing:3) {
                            PapiText("Sample gift").font(CoffeeType.face(.caption2,weight:.bold))
                            PapiText(verbatim:member.name).font(CoffeeType.face(.caption,weight:.semibold))
                        }
                        PapiArtworkFit(asset:asset).frame(width:42,height:42)
                    }.foregroundStyle(Color.cream).padding(10).background(Color.coffee.opacity(0.94),in:RoundedRectangle(cornerRadius:16))
                        .padding(.horizontal,16).padding(.top,70).transition(reduceMotion ? .opacity:.move(edge:.leading).combined(with:.opacity)).allowsHitTesting(false).papiAvoidReserved()
                }
            }
        }.onAppear {
            if !giftTrackingReady {observedGiftID=store.state.giftHistory.first(where:{$0.context==room.id})?.id;giftTrackingReady=true}
        }.onChange(of:router.sheet?.id){_,value in if value != nil {sampleVoice.stop()};showNewGiftIfReady()}
            .onChange(of:store.notice?.id){_,_ in showNewGiftIfReady()}
            .onChange(of:phase){_,value in if value != .active {sampleVoice.stop()}}
            .onDisappear {sampleVoice.stop()}
            .task {
                if demoEvents.isEmpty {appendDemoEvent();appendDemoEvent()}
                while !Task.isCancelled {
                    try? await Task.sleep(for:.seconds(5))
                    if Task.isCancelled {break}
                    if phase == .active && router.sheet == nil && !leave {appendDemoEvent()}
                }
            }
            .task(id:noteAnnouncement?.id) {
                guard let id=noteAnnouncement?.id else{return}
                try? await Task.sleep(for:.seconds(3))
                if !Task.isCancelled,noteAnnouncement?.id==id {withAnimation(reduceMotion ? nil:.easeInOut(duration:0.2)){noteAnnouncement=nil}}
            }
            .task(id:giftAnnouncement?.id) {
                guard let id=giftAnnouncement?.id else{return}
                try? await Task.sleep(for:.seconds(3))
                if !Task.isCancelled,giftAnnouncement?.id==id {withAnimation(reduceMotion ? nil:.easeInOut(duration:0.2)){giftAnnouncement=nil}}
            }
            .task(id:demoGiftAnnouncement?.id) {
                guard let id=demoGiftAnnouncement?.id else{return}
                try? await Task.sleep(for:.seconds(3))
                if !Task.isCancelled,demoGiftAnnouncement?.id==id {withAnimation(reduceMotion ? nil:.easeInOut(duration:0.2)){demoGiftAnnouncement=nil}}
            }
    }
    private func showNewGiftIfReady() {
        guard giftTrackingReady,router.sheet==nil,store.notice==nil,
              let event=store.state.giftHistory.first(where:{$0.context==room.id}),event.id != observedGiftID else{return}
        observedGiftID=event.id
        withAnimation(reduceMotion ? nil:.spring(response:0.4,dampingFraction:0.85)){giftAnnouncement=event}
    }
    private var demoStage:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                PapiText("Sample participants").font(CoffeeType.face(.headline))
                Spacer(minLength:8)
            }
            ScrollView(.horizontal,showsIndicators:false) {
                HStack(alignment:.top,spacing:14) {
                    ForEach(demoMembers) {member in
                        Button {sampleVoice.stop();router.go(.person(member.id))} label:{
                            VStack(spacing:5) {
                                Avatar(name:member.portrait,size:48)
                                PapiText(verbatim:member.name).font(CoffeeType.face(.caption2,weight:.semibold)).lineLimit(1)
                            }.frame(width:80).frame(minHeight:72).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
            PapiTextButton("Play sample voice") {
                sampleVoice.play(store.text("Welcome to the coffee table. What are you brewing today?"),language:store.state.language)
            }.font(CoffeeType.face(.caption,weight:.bold)).padding(.horizontal,12).frame(minHeight:44).background(Color.cream.opacity(0.16),in:Capsule())
            PapiText("Synthetic sample voice").font(CoffeeType.face(.caption2)).foregroundStyle(Color.cream.opacity(0.8))
            VStack(alignment:.leading,spacing:8) {
                ForEach(demoEvents.filter{!store.isUserHidden($0.memberID)}) {event in
                    if let member=store.person(event.memberID) {
                        HStack(alignment:.center,spacing:8) {
                            Button {sampleVoice.stop();router.go(.person(member.id))} label:{Avatar(name:member.portrait,size:32)}.buttonStyle(.plain)
                            VStack(alignment:.leading,spacing:3) {
                                Button {sampleVoice.stop();router.go(.person(member.id))} label:{PapiText(verbatim:member.name).font(CoffeeType.face(.caption,weight:.bold))}.buttonStyle(.plain)
                                PapiText(event.message).font(CoffeeType.face(.caption)).fixedSize(horizontal:false,vertical:true)
                            }.frame(maxWidth:.infinity,alignment:.leading)
                            if let asset=event.giftAsset {PapiArtworkFit(asset:asset).frame(width:38,height:38)}
                        }.padding(9).frame(maxWidth:.infinity,alignment:.leading).background(Color.coffee.opacity(0.65),in:RoundedRectangle(cornerRadius:14))
                            .transition(reduceMotion ? .opacity:.move(edge:.leading).combined(with:.opacity))
                    }
                }
                ForEach(store.state.tableNoteHistory?[room.id] ?? []) {note in
                    HStack(alignment:.top,spacing:8) {
                        Avatar(name:store.state.passport.portraitReference,size:32)
                        VStack(alignment:.leading,spacing:3) {
                            PapiText(verbatim:store.state.passport.name).font(CoffeeType.face(.caption,weight:.bold))
                            PapiText(note.text).font(CoffeeType.face(.caption)).fixedSize(horizontal:false,vertical:true)
                            PapiText("Only you can see these notes").font(CoffeeType.face(.caption2)).foregroundStyle(Color.cream.opacity(0.8))
                        }.frame(maxWidth:.infinity,alignment:.leading)
                    }.padding(9).frame(maxWidth:.infinity,alignment:.leading).background(Color.coffee.opacity(0.65),in:RoundedRectangle(cornerRadius:14)).id(note.id)
                }
            }
        }.padding(16).frame(maxWidth:.infinity,alignment:.leading).background(Color.coffee.opacity(0.74),in:RoundedRectangle(cornerRadius:20))
    }
    private func appendDemoEvent() {
        let members=demoMembers
        guard !members.isEmpty else{return}
        let messages=["That first sip is always the best.","What beans are in your cup today?","I love a slow morning brew.","A little gift for the table · Sample"]
        let index=demoIndex
        let event=TableDemoEvent(memberID:members[index % members.count].id,message:messages[index % messages.count],giftAsset:index % messages.count == 3 ? "giftUmbrella":nil)
        demoIndex += 1
        withAnimation(reduceMotion ? nil:.easeOut(duration:0.3)) {
            demoEvents.append(event)
            if demoEvents.count>4 {demoEvents.removeFirst(demoEvents.count-4)}
            if event.giftAsset != nil {demoGiftAnnouncement=event}
        }
    }
}
struct MemberPassportView:View {
    let memberID:String
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selectedShelf:Int?

    var body:some View {
        PapiScreen {
            if let person=store.person(memberID),!store.isUserHidden(memberID) {
                GeometryReader {container in
                    let topInset=container.safeAreaInsets.top
                    let coverHeight=min(520,max(340,container.size.width*1.08))
                    let contentWidth=max(0,min(720,container.size.width)-40)
                    let posts=store.visiblePosts.filter{$0.authorID==person.id}
                    ScrollView {
                        VStack(spacing:0) {
                            portraitCover(person,width:container.size.width,height:coverHeight+topInset,topInset:topInset)
                            VStack(alignment:.leading,spacing:24) {
                                memberDetails(person,width:contentWidth)
                                collectionShelf(person,posts:posts,width:contentWidth)
                            }
                            .padding(.horizontal,20).padding(.top,-28).padding(.bottom,28)
                            .frame(maxWidth:720).frame(maxWidth:.infinity)
                        }
                    }
                    // Extend the portrait into the top inset; keep controls below the measured system area.
                    .ignoresSafeArea(.container,edges:.top)
                    .contentMargins(.top,0,for:.scrollContent)
                }
            } else {VStack(spacing:0){PapiHeader("Profile");ScrollView {PapiEmpty(title:"Profile unavailable")}}}
        }
    }

    private func portraitCover(_ person:CoffeeMember,width:CGFloat,height:CGFloat,topInset:CGFloat)->some View {
        ZStack(alignment:.top) {
            PapiImage(name:person.portrait).frame(width:width,height:height).clipped()
            HStack {
                PapiIconButton(asset:"back",label:"Back"){dismiss()}
                    .background(Color.cream.opacity(0.94),in:RoundedRectangle(cornerRadius:14))
                Spacer(minLength:16)
                PapiIconButton(asset:"more",label:"Member options"){router.sheet = .more(person.id)}
                    .background(Color.cream.opacity(0.94),in:RoundedRectangle(cornerRadius:14))
            }
            .padding(.horizontal,20).padding(.top,topInset+12)
            .frame(maxWidth:720).papiAvoidReserved()
        }.frame(width:width,height:height)
    }

    private func memberDetails(_ person:CoffeeMember,width:CGFloat)->some View {
        VStack(alignment:.leading,spacing:20) {
            HStack(alignment:.top,spacing:14) {
                Avatar(name:person.portrait,size:76)
                VStack(alignment:.leading,spacing:6) {
                    PapiText(verbatim:person.name).font(CoffeeType.face(.title2,weight:.bold))
                        .fixedSize(horizontal:false,vertical:true)
                    PapiText(verbatim:"@"+person.handle).font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
                        .fixedSize(horizontal:false,vertical:true)
                    PreviewLabel()
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
            PapiText(person.bio).font(CoffeeType.face(.subheadline)).lineSpacing(3)
                .fixedSize(horizontal:false,vertical:true)
            let actionLayout=typeSize.isAccessibilitySize || width<320 ? AnyLayout(VStackLayout(spacing:10)):AnyLayout(HStackLayout(spacing:12))
            actionLayout {
                PapiTextButton(store.state.followedMembers.contains(person.id) ? "Following":"Follow"){store.follow(person.id)}
                    .buttonStyle(PapiButtonStyle(wide:true,cornerRadius:16)).disabled(store.state.blockedMembers.contains(person.id))
                PapiTextButton("Chatting"){router.go(.chat(person.id))}
                    .buttonStyle(PapiButtonStyle(light:true,wide:true,cornerRadius:16))
            }
            if person.id != CoffeeMember.editorial.id {
                PapiRow(asset:"plus",title:store.isFriend(person.id) ? "Friends":(store.community.friendshipRequests[person.id] == nil ? "Request friendship":"Cancel friend request")) {
                    if store.community.friendshipRequests[person.id] != nil {store.cancelFriendshipRequest(person.id)} else {store.requestFriendship(person.id)}
                }.disabled(store.isFriend(person.id)).background(Color.white.opacity(0.8),in:RoundedRectangle(cornerRadius:16))
            }
        }.padding(18).frame(maxWidth:.infinity,alignment:.leading)
            .background(Color.cream,in:RoundedRectangle(cornerRadius:26))
    }

    private func collectionShelf(_ person:CoffeeMember,posts:[CoffeeMoment],width:CGFloat)->some View {
        let activeShelf=selectedShelf ?? (posts.isEmpty ? 0:1)
        let shelfLayout=typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing:6)):AnyLayout(HStackLayout(spacing:6))
        return VStack(alignment:.leading,spacing:16) {
            shelfLayout {
                shelfButton("Photo",count:person.portrait.isEmpty ? 0:1,index:0,selected:activeShelf)
                shelfButton("Posts",count:posts.count,index:1,selected:activeShelf)
            }.padding(6).background(Color.white.opacity(0.85),in:RoundedRectangle(cornerRadius:20))
            if activeShelf==0 {
                if !person.portrait.isEmpty {
                    Button {router.go(.photo(person.portrait))} label:{
                        PapiImage(name:person.portrait).frame(width:width,height:min(460,width*1.18))
                            .clipped().clipShape(RoundedRectangle(cornerRadius:22))
                    }.buttonStyle(.plain).papiAccessibilityLabel("Photo")
                }
            } else if posts.isEmpty {
                PapiEmpty(title:"No published posts",detail:"Explore coffee moments in the Papi collection.")
            } else {
                LazyVGrid(columns:typeSize.isAccessibilitySize ? [GridItem(.flexible())]:[GridItem(.adaptive(minimum:170),spacing:12)],spacing:14) {
                    ForEach(posts){post in CoffeeMomentTile(post:post,height:210)}
                }
            }
        }
    }

    private func shelfButton(_ title:String,count:Int,index:Int,selected:Int)->some View {
        Button {selectedShelf=index} label:{
            HStack(spacing:8) {
                PapiText(title).font(CoffeeType.face(.subheadline,weight:.semibold))
                PapiText(verbatim:String(count)).font(CoffeeType.face(.caption,weight:.semibold))
            }.padding(.horizontal,12).padding(.vertical,12).frame(maxWidth:.infinity,minHeight:46)
                .background(selected==index ? Color.butter:Color.clear,in:RoundedRectangle(cornerRadius:14))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected==index ? .isSelected:[])
    }
}
