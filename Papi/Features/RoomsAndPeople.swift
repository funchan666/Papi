import SwiftUI

struct RoomsView:View {
    @EnvironmentObject private var store:PapiStore
    @EnvironmentObject private var router:PapiRouter
    @State private var filter=0
    private var rooms:[Room] {
        Room.previews.filter {room in
            !store.state.blocked.contains(room.hostID) && (filter==0 || (filter==1 && store.state.follows.contains(room.hostID)) || (filter==2 && store.state.recentRooms.contains(room.id)))
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
                        Image("roomListBackground").resizable().scaledToFill().frame(width:min(geo.size.width-32,520),height:min(210,geo.size.width*0.49),alignment:.top).clipped().frame(maxWidth:.infinity).papiAccessibilityLabel("Welcome Coffee Party")
                        HStack {
                            ForEach(0..<3) {i in
                                PapiTextButton(store.text(["All","Following","Recent"][i])){filter=i}
                                    .font(.subheadline.weight(.medium)).padding(.vertical,9).frame(maxWidth:.infinity)
                                    .foregroundStyle(filter==i ? Color.white:Color.mutedCoffee)
                                    .background(filter==i ? Color.peach:Color.clear,in:Capsule())
                            }
                        }.padding(6).background(Color.cream,in:RoundedRectangle(cornerRadius:22))
                        if let id=store.activeRoomID,let room=Room.previews.first(where:{$0.id==id}) {
                            Button {router.go(.room(id))} label:{HStack {Image("voiceOn").resizable().scaledToFit().frame(width:26,height:26);PapiText("Return to \(room.title)");Spacer();PapiText("Open")}.padding(12).background(Color.butter,in:RoundedRectangle(cornerRadius:15))}.buttonStyle(.plain)
                        }
                        if rooms.isEmpty {PapiEmpty(title:filter==1 ? "No followed rooms yet":"No recent rooms",detail:"Explore a room or follow a preview host to see it here.")}
                        LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:12),count:max(2,Int(geo.size.width/180)/2*2)),spacing:14) {
                            ForEach(rooms) {room in
                                Button {store.enter(room);router.go(.room(room.id))} label:{
                                    ZStack(alignment:.bottomLeading) {
                                        PapiImage(name:room.image).frame(height:235).clipped()
                                        VStack(alignment:.leading,spacing:8) {
                                            PapiText(room.category).font(.caption.bold()).padding(.horizontal,10).padding(.vertical,5).background(Color.peach,in:Capsule())
                                            Spacer()
                                            PapiText(room.title).font(.headline).shadow(color:.black,radius:4)
                                            HStack {Image("soundWave").resizable().scaledToFit().frame(width:18,height:18);PapiText("Preview room").font(.caption);Spacer()}.padding(8).background(Color.coffee.opacity(0.85),in:Capsule())
                                        }.padding(10).foregroundStyle(.white)
                                    }.clipShape(RoundedRectangle(cornerRadius:17))
                                }.buttonStyle(.plain)
                            }
                        }
                    }.padding(.horizontal,16).padding(.bottom,20).frame(maxWidth:1100).frame(maxWidth:.infinity)
                }
            }
        }
    }
}
struct RoomDetailView:View {
    let room:Room
    @EnvironmentObject private var store:PapiStore
    @EnvironmentObject private var router:PapiRouter
    @Environment(\.dismiss) private var dismiss
    @State private var leave=false
    @State private var micPrompt=false
    @State private var selectedMember:Person?
    private var draft:Binding<String> {Binding(get:{store.state.roomDrafts[room.id] ?? ""},set:{new in _ = store.commit{$0.roomDrafts[room.id]=String(new.prefix(2000))}})}
    var body:some View {
        PapiScreen(background:"roomBackground") {
            VStack(spacing:0) {
                HStack(spacing:8) {
                    Button {if let host=Person.find(room.hostID){selectedMember=host}} label:{
                        HStack {Avatar(name:Person.find(room.hostID)?.portrait ?? "brandMark",size:42);PapiText(room.title).font(.headline).lineLimit(2)}
                    }.buttonStyle(.plain)
                    Spacer(minLength:0)
                    PapiIconButton(asset:"moreLight",label:"Report room") {router.sheet = .report("room:"+room.id)}
                    PapiIconButton(asset:"close",label:"Leave room") {leave=true}
                }.padding(.horizontal,16).padding(.vertical,8).foregroundStyle(.white)
                ScrollView {
                    VStack(alignment:.leading,spacing:24) {
                        HStack {PreviewLabel(text:"Local room preview · Not connected");Spacer()}
                        if let host=Person.find(room.hostID) {
                            Button {selectedMember=host} label:{VStack(spacing:7){Avatar(name:host.portrait,size:82);PapiText(host.name).font(.headline)}}.buttonStyle(.plain)
                        }
                        LazyVGrid(columns:[GridItem(.adaptive(minimum:70),spacing:12)],spacing:24) {
                            ForEach(Person.previews.prefix(4).filter{!store.state.blocked.contains($0.id)}) {person in
                                Button {selectedMember=person} label:{VStack(spacing:7){Avatar(name:person.portrait,size:60);PapiText(verbatim:person.name).font(.caption)}}.buttonStyle(.plain).papiAvoidReserved()
                            }
                            ForEach(0..<4) {index in
                                Button {micPrompt=true} label:{VStack(spacing:7){Image("mic").resizable().scaledToFit().frame(width:60,height:60).opacity(0.5);PapiText("Seat \(index+1)").font(.caption)}}.buttonStyle(.plain).papiAvoidReserved()
                            }
                        }
                        Spacer(minLength:100)
                        PapiText("A little space for coffee and conversation.").font(.system(.title3,design:.serif)).italic().foregroundStyle(Color.cream.opacity(0.8))
                        PapiText("This room is a preview. No microphone is connected and no messages are sent to other people.").font(.caption).foregroundStyle(Color.cream.opacity(0.75))
                        ForEach(store.state.giftHistory.filter{$0.context==room.id}.prefix(6)) {event in
                            if let gift=Gift.all.first(where:{$0.id==event.giftID}) {
                                HStack {Image(gift.asset).resizable().scaledToFit().frame(width:42,height:42);PapiText("\(gift.name) × \(event.quantity)");Spacer();PapiText("Preview").font(.caption)}.padding(10).background(Color.white.opacity(0.12),in:RoundedRectangle(cornerRadius:15))
                            }
                        }
                    }.padding(20).frame(maxWidth:820).frame(maxWidth:.infinity)
                }
                HStack(spacing:8) {
                    PapiTextButton("Mic"){micPrompt=true}.font(.subheadline.bold()).padding(14).background(Color.coffee,in:Capsule()).papiAvoidReserved()
                    PapiInput("Tell your opinion…",text:draft,axis:.vertical).lineLimit(1...3).padding(12).background(Color.white.opacity(0.18),in:Capsule())
                    PapiIconButton(asset:"send",label:"Send room message") {store.inform("Message not sent","The room is not connected. Your draft has been kept.")}
                    PapiIconButton(asset:"gift",label:"Gifts",size:35) {router.sheet = .gifts(room.id)}
                }.padding(12)
            }.foregroundStyle(.white)
            .overlay {
                if leave {PapiDialog(title:"Leave the room?",message:"Your local draft and room history will be kept.",confirm:"Leave room",cancel:"Stay here",action:{store.activeRoomID=nil;store.roomMicRequested=false;dismiss()},dismiss:{leave=false})}
                if micPrompt {PapiDialog(title:"Join the conversation",message:"Live audio is not connected in this local edition. No microphone request will be sent.",confirm:"Got it",action:{micPrompt=false},dismiss:{micPrompt=false})}
                if let person=selectedMember {
                    ZStack {
                        Color.black.opacity(0.45).ignoresSafeArea().onTapGesture{selectedMember=nil}
                        VStack(spacing:16) {
                            HStack {PapiText("Room member").font(.headline);Spacer();PapiIconButton(asset:"close",label:"Close"){selectedMember=nil}}
                            Avatar(name:person.portrait,size:76);PapiText(verbatim:person.name).font(.title3.bold());PreviewLabel()
                            HStack {
                                PapiTextButton("Profile"){selectedMember=nil;router.go(.person(person.id))}.buttonStyle(PapiButtonStyle(light:true))
                                PapiTextButton("Send gift"){selectedMember=nil;router.sheet = .gifts(person.id)}.buttonStyle(PapiButtonStyle())
                            }
                        }.padding(22).background(Color.coffee,in:RoundedRectangle(cornerRadius:24)).frame(maxWidth:400).padding(20)
                    }
                }
            }
        }
    }
}
struct PersonView:View {
    let personID:String
    @EnvironmentObject private var store:PapiStore
    @EnvironmentObject private var router:PapiRouter
    var body:some View {
        PapiScreen {
            if let person=Person.find(personID) {
                ScrollView {
                    VStack(alignment:.leading,spacing:16) {
                        ZStack(alignment:.top) {
                            PapiImage(name:person.portrait).frame(height:450).clipped()
                            PapiHeader("") {PapiIconButton(asset:"more",label:"Member options"){router.sheet = .more(person.id)}}
                        }
                        VStack(alignment:.leading,spacing:15) {
                            HStack {Avatar(name:person.portrait,size:65);VStack(alignment:.leading){PapiText(verbatim:person.name).font(.title3.bold());PapiText("@\(person.id)").font(.caption).foregroundStyle(Color.mutedCoffee)};Spacer();PreviewLabel()}
                            PapiText(person.bio).font(.subheadline)
                            HStack(spacing:12) {
                                PapiTextButton(store.state.follows.contains(person.id) ? store.text("Following"):store.text("Follow")){store.follow(person.id)}.buttonStyle(PapiButtonStyle()).disabled(store.state.blocked.contains(person.id))
                                PapiTextButton("Chatting"){router.go(.chat(person.id))}.buttonStyle(PapiButtonStyle(light:true))
                                PapiIconButton(asset:"gift",label:"Send gift",size:34){router.sheet = .gifts(person.id)}
                            }
                            if store.state.blocked.contains(person.id) {PapiTextButton("Unblock this profile"){store.unblock(person.id)}.buttonStyle(PapiButtonStyle(light:true))}
                            PapiText("Photo").font(.headline)
                            Button {router.go(.photo(person.portrait))} label:{PapiImage(name:person.portrait).frame(width:155,height:200).clipped().clipShape(RoundedRectangle(cornerRadius:16))}.buttonStyle(.plain)
                            PapiText("Posts").font(.headline)
                            PapiEmpty(title:"No published posts",detail:"Explore coffee moments in the Papi collection.")
                        }.padding(.horizontal,20)
                    }.padding(.bottom,25).frame(maxWidth:720).frame(maxWidth:.infinity)
                }
            } else {VStack{PapiHeader("Profile");PapiEmpty(title:"Profile unavailable");Spacer()}}
        }
    }
}
struct MemberActionsView:View {
    var personID:String
    @EnvironmentObject private var store:PapiStore
    @Environment(\.dismiss) private var dismiss
    @State private var reporting=false
    var body:some View {
        Group {
            if reporting {ReportView(subjectID:"person:"+personID)}
            else {
                PapiScreen {
                VStack(spacing:24) {
                    PapiHeader("Member options")
                    Spacer()
                    HStack(spacing:22) {
                        Button {store.block(personID);dismiss()} label:{Image("block").resizable().scaledToFit().frame(width:100,height:100)}.papiAccessibilityLabel("Block member")
                        Button {reporting=true} label:{Image("report").resizable().scaledToFit().frame(width:100,height:100)}.papiAccessibilityLabel("Report member")
                    }.buttonStyle(.plain)
                    PapiText("Blocking hides this preview profile and its rooms on this device.").font(.subheadline).multilineTextAlignment(.center).padding(25)
                    Spacer()
                }
                }
            }
        }
    }
}
struct ReportView:View {
    var subjectID:String
    @EnvironmentObject private var store:PapiStore
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        PapiScreen {
            VStack(spacing:14) {
                PapiHeader("Report Type")
                PapiText("Choose a reason").font(.title3.bold()).padding(.top,25)
                ForEach(["Inappropriate content","Harassment or hate","Discrimination","Spam or misleading content","Other safety concern"],id:\.self) {reason in
                    PapiTextButton(reason){store.report(subjectID,reason:reason);dismiss()}.font(.body).padding(16).frame(maxWidth:.infinity).background(Color.white,in:RoundedRectangle(cornerRadius:14)).buttonStyle(.plain)
                }
                PapiText("Reports remain on this device until a moderation service is connected.").font(.caption).foregroundStyle(Color.mutedCoffee).multilineTextAlignment(.center)
                Spacer()
            }.padding(.horizontal,20).frame(maxWidth:600).frame(maxWidth:.infinity)
        }
    }
}
