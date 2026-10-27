import SwiftUI

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
        PapiScreen() {
            GeometryReader {geo in
                let topInset=geo.safeAreaInsets.top
                let bannerHeight=min(280,max(180,geo.size.width*0.57))
                ScrollView {
                    VStack(spacing:0) {
                        ZStack(alignment:.top) {
                            Image("roomListBackground").resizable().scaledToFill()
                                .frame(width:geo.size.width,height:bannerHeight+topInset,alignment:.top).clipped().accessibilityHidden(true)
                            Image("roomListBackground").resizable().scaledToFill()
                                .frame(width:geo.size.width,height:bannerHeight,alignment:.top).clipped().padding(.top,topInset)
                        }.frame(width:geo.size.width,height:bannerHeight+topInset).papiAccessibilityLabel("Welcome Coffee Party")
                        VStack(spacing:14) {
                            HStack {
                                ForEach(0..<3) {i in
                                    PapiTextButton(store.text(["All","Following","Recent"][i])){filter=i}
                                        .font(CoffeeType.face(.subheadline,weight:.medium)).padding(.vertical,9).frame(maxWidth:.infinity)
                                        .foregroundStyle(filter==i ? Color.white:Color.mutedCoffee)
                                        .background(filter==i ? Color.peach:Color.clear,in:Capsule())
                                }
                            }.padding(6).background(Color.cream,in:RoundedRectangle(cornerRadius:22))
                            if let id=store.activeRoomID,let room=CoffeeTable.previews.first(where:{$0.id==id}),store.isRoomVisible(room) {
                                Button {router.go(.room(id))} label:{HStack {Image("voiceOn").resizable().scaledToFit().frame(width:26,height:26);PapiText("Return to \(room.title)");Spacer();PapiText("Open")}.padding(12).background(Color.butter,in:RoundedRectangle(cornerRadius:15))}.buttonStyle(.plain)
                            }
                            if rooms.isEmpty {PapiEmpty(title:filter==1 ? "No followed rooms yet":"No recent rooms",detail:"Open a coffee topic to keep it here.")}
                            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:12),count:typeSize.isAccessibilitySize ? 1:max(1,Int((min(1100,geo.size.width)-20)/170))),spacing:14) {
                                ForEach(rooms) {room in
                                    Button {if store.enter(room){router.go(.room(room.id))}} label:{
                                        VStack(alignment:.leading,spacing:8) {
                                            PapiText(room.category).font(CoffeeType.face(.caption,weight:.bold)).padding(.horizontal,10).padding(.vertical,5).background(Color.peach,in:Capsule())
                                            Spacer(minLength:12)
                                            PapiText(room.title).font(CoffeeType.face(.headline)).fixedSize(horizontal:false,vertical:true).shadow(color:.black,radius:4)
                                            HStack {Image("soundWave").resizable().scaledToFit().frame(width:18,height:18);PapiText("Coffee topic").font(CoffeeType.face(.caption));Spacer()}.padding(8).background(Color.coffee.opacity(0.85),in:Capsule())
                                        }.padding(10).frame(maxWidth:.infinity,minHeight:235,alignment:.bottomLeading).foregroundStyle(.white)
                                            .background {PapiImage(name:room.image)}.clipShape(RoundedRectangle(cornerRadius:17))
                                    }.buttonStyle(.plain)
                                }
                            }
                        }.padding(.horizontal,16).padding(.top,14).padding(.bottom,20).frame(maxWidth:1100).frame(maxWidth:.infinity)
                    }
                }
                .ignoresSafeArea(.container,edges:.top)
                .contentMargins(.top,0,for:.scrollContent)
            }
        }
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
    @State private var leave=false
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
                    PapiIconButton(asset:"close",label:"Leave room") {leave=true}
                }.padding(.horizontal,16).padding(.vertical,8).foregroundStyle(.white).papiAvoidReserved()
                ScrollView {
                    VStack(alignment:.leading,spacing:24) {
                        HStack {PreviewLabel(text:"Coffee table concept · No live session");Spacer()}
                        if let host=CoffeeMember.find(room.hostMemberID) {
                            Button {router.go(.person(host.id))} label:{VStack(spacing:7){Avatar(name:host.portrait,size:82);PapiText(host.name).font(CoffeeType.face(.headline))}}.buttonStyle(.plain)
                        }
                        PapiText("A topic to bring to your next coffee table").font(CoffeeType.display(.title2))
                        PapiText("Which beans are you brewing, and what changed in the cup?").font(CoffeeType.face(.body))
                        Spacer(minLength:100)
                        PapiText("A little space for coffee and conversation.").font(CoffeeType.display(.title3)).italic().foregroundStyle(Color.cream.opacity(0.8))
                        PapiText("This is a coffee-table concept. Live audio and room messaging are not connected.").font(CoffeeType.face(.caption)).foregroundStyle(Color.cream.opacity(0.75))
                        ForEach(store.state.giftHistory.filter{$0.context==room.id}.prefix(6)) {event in
                            if let gift=CoffeeCollectible.all.first(where:{$0.id==event.giftID}) {
                                HStack {Image(gift.asset).resizable().scaledToFit().frame(width:42,height:42);PapiText("\(gift.name) × \(event.quantity)");Spacer();PapiText("Preview").font(CoffeeType.face(.caption))}.padding(10).background(Color.white.opacity(0.12),in:RoundedRectangle(cornerRadius:15))
                            }
                        }
                    }.padding(20).frame(maxWidth:820).frame(maxWidth:.infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge:.bottom,spacing:0) {
                    PapiInputBar {
                        VStack(alignment:.leading,spacing:5) {
                            if !compactControls {PapiText("Table notes").font(CoffeeType.face(.caption,weight:.bold))}
                            PapiInput("A thought for the coffee table…",text:draft,axis:.vertical).lineLimit(1...3).padding(12).background(Color.white.opacity(0.18),in:RoundedRectangle(cornerRadius:18))
                        }
                    } actions: {
                        HStack(spacing:8) {
                            PapiIconButton(asset:"check",label:"Keep table note") {
                                let note=draft.wrappedValue
                                if store.commit({$0.tableNotes[room.id]=note}) {store.inform("Table note kept","Your note is in your coffee book. It has not been sent to a room.")}
                            }.background(Color.cream,in:RoundedRectangle(cornerRadius:12)).disabled(draft.wrappedValue.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                            PapiIconButton(asset:"gift",label:"Gifts",size:35) {router.sheet = .gifts(room.id)}
                        }
                    }
                }
            }.foregroundStyle(.white)
            .overlay {
                if leave {PapiDialog(title:"Leave the room?",message:"Your local draft and room history will be kept.",confirm:"Leave room",cancel:"Stay here",action:{store.activeRoomID=nil;store.roomMicRequested=false;dismiss()},dismiss:{leave=false})}

            }
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
            VStack(spacing:0) {
                if person.id != CoffeeMember.editorial.id {
                    PapiRow(asset:"plus",title:store.isFriend(person.id) ? "Friends":(store.community.friendshipRequests[person.id] == nil ? "Request friendship":"Cancel friend request")) {
                        if store.community.friendshipRequests[person.id] != nil {store.cancelFriendshipRequest(person.id)} else {store.requestFriendship(person.id)}
                    }.disabled(store.isFriend(person.id))
                    Divider().padding(.horizontal,14)
                }
                PapiRow(asset:"gift",title:"Gift preview"){router.sheet = .gifts(person.id)}
            }.background(Color.white.opacity(0.8),in:RoundedRectangle(cornerRadius:16))
            PapiText("A portrait in the coffee collection, not an available chat contact.")
                .font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee).lineSpacing(3)
                .fixedSize(horizontal:false,vertical:true)
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
