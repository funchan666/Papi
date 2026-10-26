import SwiftUI
import PhotosUI

struct CorrespondenceInbox:View {
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    @State private var confirmClear=false
    var body:some View {
        PapiScreen {
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    HStack {Image("chatTitle").resizable().scaledToFit().frame(width:110,height:58);Spacer();PapiIconButton(asset:"clean",label:"Clear chat drafts"){confirmClear=true}}
                    let followed=CoffeeMember.previews.filter{store.state.followedMembers.contains($0.id) && !store.isUserHidden($0.id)}
                    if !followed.isEmpty {
                        PapiText("Following").font(CoffeeType.face(.headline))
                        ScrollView(.horizontal,showsIndicators:false) {HStack(spacing:18) {
                            ForEach(followed) {person in
                                VStack(spacing:7) {PapiUserLink(userID:person.id,size:54,showsName:false);Button{router.go(.person(person.id))}label:{PapiText(verbatim:person.name).font(CoffeeType.face(.caption))}.buttonStyle(.plain)}
                            }
                        }}
                    }
                    Button {router.go(.notifications)} label:{HStack {Image("interactionNotice").resizable().scaledToFit().frame(width:48,height:48);PapiText("Coffee desk").font(CoffeeType.face(.headline));Spacer()}}.buttonStyle(.plain)
                    if store.conversationPeople.isEmpty {PapiEmpty(title:"No conversations yet",detail:"Open a profile to start a draft. Sending messages requires both people to follow each other.")}
                    ForEach(store.conversationPeople) {person in
                        VStack(alignment:.leading,spacing:10) {
                            HStack {PapiUserLink(userID:person.id);Spacer();PapiIconButton(asset:"comment",label:"Open chat"){router.go(.chat(person.id))}}
                            Button {router.go(.chat(person.id))} label:{
                                HStack {PapiText(verbatim:preview(person.id)).font(CoffeeType.face(.subheadline)).lineLimit(2);Spacer();PapiText(store.hasChatDraft(person.id) ? "Draft":"Conversation").font(CoffeeType.face(.caption))}.frame(maxWidth:.infinity,alignment:.leading)
                            }.buttonStyle(.plain)
                        }.padding(16).background(Color.white,in:RoundedRectangle(cornerRadius:16))
                    }
                }.padding(20).frame(maxWidth:800).frame(maxWidth:.infinity)
            }
        }.overlay {
            if confirmClear {PapiDialog(title:"Clear chat drafts?",message:"Remove all saved chat text, photo attachments and voice drafts from your chats. Your profile and journal stay unchanged.",confirm:"Clear drafts",cancel:"Keep drafts",action:{confirmClear=false;store.clearChatDrafts()},dismiss:{confirmClear=false})}
        }
    }
    private func preview(_ id:String)->String {
        if store.hasChatDraft(id){return store.chatPreview(id)}
        guard let last=store.messages(with:id).last else{return ""}
        return last.kind == .text ? last.value:store.text(last.kind == .photo ? "Photo":"Voice draft")
    }
}
struct CoffeeConversationView:View {
    let memberID:String
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    @State private var picker:PhotosPickerItem?
    @State private var showVoice=false
    @State private var showCamera=false
    @State private var requestCallMicrophone=false
    @State private var importing=false
    private var draft:Binding<String> {Binding(get:{store.state.letterDrafts[memberID] ?? ""},set:{new in _ = store.commit{$0.letterDrafts[memberID]=String(new.prefix(2000))}})}
    private var canSend:Bool {
        !importing && store.storageAvailable && store.state.signedIn &&
            (!draft.wrappedValue.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || store.state.letterPhotos[memberID] != nil || store.state.letterVoiceNotes[memberID] != nil)
    }
    var body:some View {
        PapiScreen {
            if let person=store.person(memberID),!store.isUserHidden(memberID) {
                VStack(spacing:0) {
                    PapiHeader(person.name,titleAction:{router.go(.person(memberID))}) {
                        HStack(spacing:0) {
                            PapiIconButton(asset:"more",label:"Safety options"){router.sheet = .safety(.user(memberID))}
                        }
                    }
                    ScrollViewReader {proxy in
                        ScrollView {
                            VStack(spacing:20) {
                                PapiUserLink(userID:memberID,size:66)
                                PapiText(store.isMutual(memberID) ? "Mutual following confirmed":"Messages require mutual following.").font(CoffeeType.face(.subheadline)).multilineTextAlignment(.center)
                                PapiActionGroup {
                                    PapiTextButton("Video call"){if store.requireMutual(memberID){requestCallMicrophone=true;showCamera=true}}.font(CoffeeType.face(.caption,weight:.bold)).padding(10).frame(minHeight:44).background(Color.butter,in:Capsule())
                                    PapiTextButton("Preview my camera"){requestCallMicrophone=false;showCamera=true}.font(CoffeeType.face(.caption,weight:.bold)).padding(10).frame(minHeight:44).background(Color.butter,in:Capsule())
                                }
                                ForEach(store.messages(with:memberID)) {message in ChatMessageView(message:message).id(message.id)}
                                if let attachment=store.state.letterPhotos[memberID] {
                                    VStack(spacing:8) {PapiText("Photo draft · Not sent").font(CoffeeType.face(.caption));PapiImage(name:attachment).frame(height:200).clipped().clipShape(RoundedRectangle(cornerRadius:16));PapiTextButton("Remove attachment"){_ = store.commit{$0.letterPhotos.removeValue(forKey:memberID)}}.font(CoffeeType.face(.caption))}
                                }
                                if let voice=store.state.letterVoiceNotes[memberID] {VoiceNotePlayer(name:voice);PapiTextButton("Remove voice draft"){_ = store.commit{$0.letterVoiceNotes.removeValue(forKey:memberID)}}.font(CoffeeType.face(.caption))}
                                if importing {PapiText("Importing photo…").font(CoffeeType.face(.caption))}
                            }.padding(22).frame(maxWidth:700).frame(maxWidth:.infinity)
                        }.scrollDismissesKeyboard(.interactively)
                            .onChange(of:store.messages(with:memberID).count){_,_ in if let id=store.messages(with:memberID).last?.id{proxy.scrollTo(id,anchor:.bottom)}}
                    }
                    .safeAreaInset(edge:.bottom,spacing:0) {
                        PapiInputBar {
                            PapiInput("Say Hi…",text:draft,axis:.vertical).lineLimit(1...3).padding(12).foregroundStyle(Color.coffee).background(Color.cream,in:RoundedRectangle(cornerRadius:18))
                        } actions: {
                            HStack(spacing:5) {
                                PapiIconButton(asset:"mic",label:"Record a voice note",size:34){showVoice=true}
                                PhotosPicker(selection:$picker,matching:.images) {Image("chatPhoto").resizable().scaledToFit().frame(width:34,height:34).frame(width:44,height:44)}.disabled(importing).papiAccessibilityLabel("Choose a photo for this draft")
                                PapiIconButton(asset:"send",label:"Send message",size:24){if canSend {_ = store.sendChat(to:memberID,text:draft.wrappedValue)}}.background(Color.cream,in:RoundedRectangle(cornerRadius:12)).disabled(!canSend)
                            }
                        }
                    }
                }
            } else {VStack(spacing:0){PapiHeader("Chat");ScrollView {PapiEmpty(title:"Profile unavailable")}}}
        }.onChange(of:picker){_,item in
            guard let item,!importing else{return}
            let owner=store.state.passport.id;importing=true
            Task{await importPhoto(item,owner:owner)}
        }
            .sheet(isPresented:$showVoice){PapiDeviceContainer {VoiceDraftView(memberID:memberID).papiNotices()}.presentationBackground {PapiBackground()}.presentationDragIndicator(.hidden).interactiveDismissDisabled(router.hasBlockingModal)}
            .sheet(isPresented:$showCamera){PapiDeviceContainer {CameraPreviewView(requestMicrophone:requestCallMicrophone).papiNotices()}.presentationBackground {PapiBackground(asset:"roomBackground")}.presentationDragIndicator(.hidden).interactiveDismissDisabled(router.hasBlockingModal)}
    }
    @MainActor private func importPhoto(_ item:PhotosPickerItem,owner:UUID) async {
        defer{importing=false;picker=nil}
        guard store.state.passport.id==owner,store.state.signedIn else{return}
        do {
            guard let data=try await item.loadTransferable(type:Data.self) else {throw CoffeeMedia.MediaError.invalid}
            guard store.state.passport.id==owner,store.state.signedIn,!store.isUserHidden(memberID) else{return}
            let name=try CoffeeMedia.saveImage(data,guest:owner)
            _ = store.commit{$0.letterPhotos[memberID]=name}
        } catch {store.inform("Could not import photo",error.localizedDescription)}
    }
}
struct ChatMessageView:View {
    var message:CoffeeLetter
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {PapiUserLink(userID:message.authorID,size:32);Spacer();PapiIconButton(asset:"more",label:"Message options",size:20){router.sheet = .safety(.init(kind:.message,contentReference:message.id,authorID:message.authorID))}}
            switch message.kind {
            case .text:PapiText(verbatim:message.value)
            case .photo:Button{router.go(.photo(message.value))}label:{PapiImage(name:message.value).frame(height:220).clipped()}.buttonStyle(.plain)
            case .voice:VoiceNotePlayer(name:message.value)
            }
            HStack {Text(message.createdAt,style:.time);Spacer();PapiText(message.delivery == .waitingForConnection ? "In your outbox · Not delivered":(message.delivery == .sent ? "Sent":"Received"))}.font(CoffeeType.face(.caption2)).foregroundStyle(Color.mutedCoffee)
        }.padding(16).frame(maxWidth:.infinity,alignment:.leading).background(message.authorID==store.state.passport.id.uuidString ? Color.butter:Color.white,in:RoundedRectangle(cornerRadius:18))
    }
}
struct CoffeeDeskView:View {
    @EnvironmentObject private var store:CoffeeHouse
    var body:some View {
        PapiScreen {VStack(spacing:0){
            PapiHeader("Coffee desk")
            ScrollView {
                VStack(alignment:.leading,spacing:14) {
                    PapiPanel{VStack(alignment:.leading,spacing:8){PapiText("Welcome to Papi").font(CoffeeType.face(.headline));PapiText("Your recent brews, collection and saved reports, gathered in one place.").font(CoffeeType.face(.subheadline))}}
                    ForEach(store.brewBook.cups.prefix(3)) {cup in BrewRecordRow(cup:cup)}
                    if !store.state.communityReports.isEmpty {PapiText("Saved report drafts").font(CoffeeType.face(.headline))}
                    ForEach(store.state.communityReports.reversed()){report in PapiPanel{VStack(alignment:.leading,spacing:8){
                        PapiText(report.reason).font(CoffeeType.face(.headline))
                        PapiText("Content hidden after your report").font(CoffeeType.face(.subheadline))
                        Text(report.createdAt,style:.date).font(CoffeeType.face(.caption))
                        PapiText("Saved report · Awaiting a connected moderation service").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
                    }}}
                }.padding(20).frame(maxWidth:700).frame(maxWidth:.infinity)
            }
        }}
    }
}
