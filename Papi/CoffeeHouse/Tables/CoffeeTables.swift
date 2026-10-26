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
                ScrollView {
                    VStack(spacing:14) {
                        Image("roomListBackground").resizable().scaledToFill().frame(width:max(0,min(geo.size.width-32,520)),height:min(210,geo.size.width*0.49),alignment:.top).clipped().frame(maxWidth:.infinity).papiAccessibilityLabel("Welcome Coffee Party")
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
                    }.padding(.horizontal,16).padding(.bottom,20).frame(maxWidth:1100).frame(maxWidth:.infinity)
                }
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
    var body:some View {
        PapiScreen {
            if let person=store.person(memberID),!store.isUserHidden(memberID) {
                ScrollView {
                    VStack(alignment:.leading,spacing:16) {
                        ZStack(alignment:.top) {
                            PapiImage(name:person.portrait).frame(height:450).clipped()
                            PapiHeader("") {PapiIconButton(asset:"more",label:"Member options"){router.sheet = .more(person.id)}}
                                .background(Color.cream.opacity(0.94),in:RoundedRectangle(cornerRadius:16)).padding(12)
                        }
                        VStack(alignment:.leading,spacing:15) {
                            HStack {Avatar(name:person.portrait,size:65);VStack(alignment:.leading){PapiText(verbatim:person.name).font(CoffeeType.face(.title3,weight:.bold));PapiText("@"+person.handle).font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)};Spacer();PreviewLabel()}
                            PapiText("A portrait in the coffee collection, not an available chat contact.").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
                            PapiText(person.bio).font(CoffeeType.face(.subheadline))
                            PapiActionGroup {
                                PapiTextButton(store.state.followedMembers.contains(person.id) ? store.text("Following"):store.text("Follow")){store.follow(person.id)}.buttonStyle(PapiButtonStyle()).disabled(store.state.blockedMembers.contains(person.id))
                                PapiTextButton("Chatting"){router.go(.chat(person.id))}.buttonStyle(PapiButtonStyle(light:true))
                                PapiIconButton(asset:"gift",label:"Send gift",size:34){router.sheet = .gifts(person.id)}
                            }
                            if person.id != CoffeeMember.editorial.id {
                                PapiTextButton(store.isFriend(person.id) ? "Friends":(store.community.friendshipRequests[person.id] == nil ? "Request friendship":"Cancel friend request")){
                                    if store.community.friendshipRequests[person.id] != nil {store.cancelFriendshipRequest(person.id)} else {store.requestFriendship(person.id)}
                                }.buttonStyle(PapiButtonStyle(light:true)).disabled(store.isFriend(person.id))
                            }
                            PapiText("Photo").font(CoffeeType.face(.headline))
                            Button {router.go(.photo(person.portrait))} label:{PapiImage(name:person.portrait).frame(width:155,height:200).clipped().clipShape(RoundedRectangle(cornerRadius:16))}.buttonStyle(.plain)
                            PapiText("Posts").font(CoffeeType.face(.headline))
                            let posts=store.visiblePosts.filter{$0.authorID==person.id}
                            if posts.isEmpty {PapiEmpty(title:"No published posts",detail:"Explore coffee moments in the Papi collection.")}
                            LazyVGrid(columns:[GridItem(.adaptive(minimum:145))],spacing:12){ForEach(posts){post in CoffeeMomentTile(post:post,height:210)}}
                        }.padding(.horizontal,20)
                    }.padding(.bottom,25).frame(maxWidth:720).frame(maxWidth:.infinity)
                }
            } else {VStack(spacing:0){PapiHeader("Profile");ScrollView {PapiEmpty(title:"Profile unavailable")}}}
        }
    }
}
