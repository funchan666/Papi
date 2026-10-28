import SwiftUI
import AVFoundation
@preconcurrency import LiveKit

// The route remains gated until the token service, remote participant removal
// and device validation are ready.
@MainActor final class CoffeeLiveCall:ObservableObject {
    let room=Room()
    @Published private(set) var connecting=false
    @Published private(set) var connected=false
    @Published private(set) var microphoneEnabled=false
    @Published private(set) var cameraEnabled=false
    @Published var message:String?
    private var generation=UUID()
    private var monitor:Task<Void,Never>?
    private var joining=false
    private var disconnecting=0

    func join(call:UUID,account:UUID) async {
        guard !joining,disconnecting==0,!connected else{return}
        let attempt=UUID();generation=attempt;joining=true;connecting=true;message=nil
        defer {joining=false;connecting=disconnecting>0}
        do {
            guard try await CoffeeCloud.shared.canJoinCall(id:call,account:account) else {throw CoffeeCloud.ConnectionError.actionUnavailable}
            guard generation==attempt,!Task.isCancelled else{return}
            let credentials=try await CoffeeCloud.shared.callToken(id:call,account:account)
            guard generation==attempt,!Task.isCancelled else {return}
            try await room.connect(url:credentials.server_url,token:credentials.participant_token,
                                   connectOptions:ConnectOptions(enableMicrophone:false))
            guard generation==attempt,!Task.isCancelled else {await room.disconnect();return}
            let allowed=try await CoffeeCloud.shared.canJoinCall(id:call,account:account)
            guard generation==attempt,!Task.isCancelled,allowed else {await room.disconnect();return}
            connected=true
            monitor=Task { [weak self] in
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for:.seconds(5))
                        guard let self else{return}
                        guard self.generation==attempt,self.room.connectionState != .disconnected else {
                            if self.generation==attempt {self.monitor=nil;await self.disconnect()}
                            return
                        }
                        let allowed=try await CoffeeCloud.shared.canJoinCall(id:call,account:account)
                        guard !Task.isCancelled,self.generation==attempt else{return}
                        if !allowed {self.monitor=nil;await self.disconnect();return}
                    } catch {
                        if !Task.isCancelled,let self,self.generation==attempt {self.monitor=nil;await self.disconnect()}
                        return
                    }
                }
            }
        } catch {
            await room.disconnect();connected=false
            if generation==attempt {message="The call could not be connected."}
        }
    }

    func setMicrophone(_ enabled:Bool) async {
        guard connected else{return}
        let attempt=generation
        if enabled,!(await AVAudioApplication.requestRecordPermission()) {if generation==attempt {message="Microphone permission was not granted."};return}
        guard connected,generation==attempt,!Task.isCancelled else{return}
        do {_ = try await room.localParticipant.setMicrophone(enabled:enabled);if connected,generation==attempt {microphoneEnabled=enabled}}
        catch {if generation==attempt {message="The microphone could not be changed."}}
    }
    func setCamera(_ enabled:Bool) async {
        guard connected else{return}
        let attempt=generation
        if enabled,!(await AVCaptureDevice.requestAccess(for:.video)) {if generation==attempt {message="Camera permission was not granted."};return}
        guard connected,generation==attempt,!Task.isCancelled else{return}
        do {_ = try await room.localParticipant.setCamera(enabled:enabled);if connected,generation==attempt {cameraEnabled=enabled}}
        catch {if generation==attempt {message="The camera could not be changed."}}
    }
    func disconnect() async {
        disconnecting+=1;connecting=true
        defer {disconnecting-=1;connecting=joining || disconnecting>0}
        generation=UUID();monitor?.cancel();monitor=nil
        connected=false;microphoneEnabled=false;cameraEnabled=false
        await room.disconnect()
    }
}

struct CoffeeLiveCallView:View {
    let callID:UUID
    let accountID:UUID
    @EnvironmentObject private var store:CoffeeHouse
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var call=CoffeeLiveCall()
    var body:some View {
        PapiScreen(background:"roomBackground") {
            VStack(spacing:16) {
                PapiHeader("Video call")
                LiveCallVideo(room:call.room).frame(maxWidth:.infinity,maxHeight:.infinity)
                if let message=call.message {PapiText(message).foregroundStyle(.white)}
                if call.connected {
                    PapiActionGroup {
                        PapiTextButton(call.microphoneEnabled ? "Mute microphone":"Enable microphone"){Task {await call.setMicrophone(!call.microphoneEnabled)}}
                        PapiTextButton(call.cameraEnabled ? "Turn camera off":"Enable camera"){Task {await call.setCamera(!call.cameraEnabled)}}
                        PapiTextButton("End call"){Task {await finish();dismiss()}}
                    }
                } else {PapiTextButton(call.connecting ? "Connecting…":"Join call"){Task {await call.join(call:callID,account:accountID)}}.disabled(call.connecting)}
            }.padding(16)
        }.onDisappear {Task {await finish()}}
            .onChange(of:scenePhase){_,phase in if phase == .background {Task {await finish()}}}
    }
    private func finish() async {await call.disconnect();await store.endCloudCall(callID)}
}

private struct LiveCallVideo:View {
    @ObservedObject var room:Room
    var body:some View {
        VStack(spacing:12) {
            ForEach(Array(room.remoteParticipants.keys),id:\.self) {key in
                if let participant=room.remoteParticipants[key] {LiveParticipantVideo(participant:participant)}
            }
            LiveParticipantVideo(participant:room.localParticipant).frame(maxHeight:180)
        }
    }
}
private struct LiveParticipantVideo:View {
    @ObservedObject var participant:Participant
    var body:some View {
        Group {
            if let track=participant.firstCameraVideoTrack {SwiftUIVideoView(track,layoutMode:.fit)}
            else {PapiImage(name:"emptyCup",fit:true)}
        }.frame(maxWidth:.infinity,maxHeight:.infinity).clipped().clipShape(RoundedRectangle(cornerRadius:18))
    }
}

@MainActor final class CoffeeLiveVoice:ObservableObject {
    let room=Room()
    @Published private(set) var connecting=false
    @Published private(set) var connected=false
    @Published private(set) var microphoneEnabled=false
    @Published var message:String?
    private var generation=UUID()
    private var monitor:Task<Void,Never>?
    private var joining=false
    private var disconnecting=0
    private var joiningTopic:String?
    private var joiningAccount:UUID?
    private var sessionID:UUID?

    func join(topic:String,account:UUID,store:CoffeeHouse) async {
        guard !joining,disconnecting==0,!connected else{return}
        let attempt=UUID();generation=attempt;joining=true;joiningTopic=topic;joiningAccount=account;connecting=true;message=nil
        defer {joining=false;joiningTopic=nil;joiningAccount=nil;connecting=disconnecting>0}
        guard let session=await store.startCloudVoice(topic) else {return}
        sessionID=session.id
        defer {if !connected && sessionID==session.id {sessionID=nil}}
        do {
            guard generation==attempt,!Task.isCancelled else {await store.finishCloudVoice(expectedID:session.id);return}
            let token=try await CoffeeCloud.shared.voiceToken(topic:topic,id:session.id,account:account)
            guard generation==attempt,!Task.isCancelled else {await store.finishCloudVoice(expectedID:session.id);return}
            try await room.connect(url:token.server_url,token:token.participant_token,
                                   connectOptions:ConnectOptions(enableMicrophone:false))
            guard generation==attempt,!Task.isCancelled else {await room.disconnect();await store.finishCloudVoice(expectedID:session.id);return}
            let allowed=try await CoffeeCloud.shared.voiceSession(topic:topic,id:session.id,account:account,operation:.heartbeat)
            guard generation==attempt,!Task.isCancelled,allowed else {await room.disconnect();await store.finishCloudVoice(expectedID:session.id);return}
            connected=true
            monitor=Task { [weak self,weak store] in
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for:.seconds(10))
                        guard let self,let store else{return}
                        guard store.state.signedIn,store.state.cloudAccountID==account,
                              store.state.pendingCloudVoice?.id==session.id,store.state.pendingCloudVoice?.closing==false,
                              self.generation==attempt,self.room.connectionState != .disconnected else {
                            if self.generation==attempt {self.monitor=nil;await self.disconnect(store:store)}
                            return
                        }
                        let allowed=try await CoffeeCloud.shared.voiceSession(topic:topic,id:session.id,account:account,operation:.heartbeat)
                        guard !Task.isCancelled,self.generation==attempt else{return}
                        if !allowed {self.monitor=nil;await self.disconnect(store:store);self.message="The voice session ended.";return}
                    } catch {
                        if !Task.isCancelled,let self,let store,self.generation==attempt {self.monitor=nil;await self.disconnect(store:store);self.message="The voice session ended."}
                        return
                    }
                }
            }
        } catch {
            await room.disconnect();await store.finishCloudVoice(expectedID:session.id);connected=false
            if generation==attempt {message="The voice room could not be connected."}
        }
    }
    func setMicrophone(_ enabled:Bool) async {
        guard connected else{return}
        let attempt=generation
        if enabled,!(await AVAudioApplication.requestRecordPermission()) {if generation==attempt {message="Microphone permission was not granted."};return}
        guard connected,generation==attempt,!Task.isCancelled else{return}
        do {_ = try await room.localParticipant.setMicrophone(enabled:enabled);if connected,generation==attempt {microphoneEnabled=enabled}}
        catch {if generation==attempt {message="The microphone could not be changed."}}
    }
    func disconnect(store:CoffeeHouse) async {
        disconnecting+=1;connecting=true
        defer {disconnecting-=1;connecting=joining || disconnecting>0}
        let pending=store.state.pendingCloudVoice
        let ownedID=sessionID ?? (joining && pending?.topic==joiningTopic && pending?.accountID==joiningAccount ? pending?.id:nil)
        sessionID=nil
        generation=UUID();monitor?.cancel();monitor=nil
        connected=false;microphoneEnabled=false
        await room.disconnect()
        if let ownedID {await store.finishCloudVoice(expectedID:ownedID)}
    }
}

struct CoffeeLiveVoiceRoomView:View {
    let topic:CoffeeCloud.VoiceTopic
    let cover:String
    let account:UUID
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.papiBounds) private var bounds
    @StateObject private var voice=CoffeeLiveVoice()
    @State private var roomMessages:[CoffeeCloud.VoiceMessage]=[]
    @State private var messageDraft=""
    @State private var pendingMessageID:UUID?
    @State private var pendingMessageBody=""
    @State private var messageSending=false
    @State private var messageUnavailable=false
    private var activeSession:UUID? {
        guard voice.connected,let pending=store.state.pendingCloudVoice,pending.accountID==account,
              pending.topic==topic.id,!pending.closing else {return nil}
        return pending.id
    }
    var body:some View {
        PapiScreen(background:"voiceLoungeBackground") {
            VStack(spacing:0) {
                HStack(spacing:12) {
                    PapiIconButton(asset:"back",label:"Back") {dismiss()}
                    PapiText("Coffee tables").font(CoffeeType.display(.title3,weight:.bold)).foregroundStyle(Color.cream)
                        .frame(maxWidth:.infinity,alignment:.leading)
                    PapiArtworkFit(asset:"audioTableMark").frame(width:36,height:36)
                }.padding(.horizontal,16).padding(.vertical,8).papiAvoidReserved()
                ScrollView {
                    VStack(alignment:.leading,spacing:20) {
                        let compact=typeSize.isAccessibilitySize || (bounds.width>0 && bounds.width<330)
                        let topicLayout=compact ? AnyLayout(VStackLayout(alignment:.leading,spacing:12)):AnyLayout(HStackLayout(alignment:.center,spacing:16))
                        topicLayout {
                            PapiImage(name:cover).frame(width:108,height:136).clipped().clipShape(RoundedRectangle(cornerRadius:16))
                            VStack(alignment:.leading,spacing:8) {
                                PapiText(topic.category).font(CoffeeType.face(.caption,weight:.bold)).foregroundStyle(Color.mutedCoffee).fixedSize(horizontal:false,vertical:true)
                                PapiText(topic.title).font(CoffeeType.display(.title2,weight:.bold)).foregroundStyle(Color.coffee).fixedSize(horizontal:false,vertical:true)
                                HStack(alignment:.center,spacing:6) {
                                    PapiArtworkFit(asset:"audioTableMark").frame(width:24,height:24)
                                    PapiText(voice.connected ? (voice.microphoneEnabled ? "Microphone on":"Microphone off"):"Your microphone starts off.")
                                        .font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee).fixedSize(horizontal:false,vertical:true)
                                }
                            }.frame(maxWidth:.infinity,alignment:.leading)
                        }.padding(.horizontal,16).padding(.vertical,26).frame(maxWidth:.infinity,alignment:.leading)
                            .background {Image("voiceTopicPlate").resizable()}
                        VStack(alignment:.leading,spacing:8) {
                            PapiText("Coffee prompt").font(CoffeeType.face(.caption,weight:.bold)).foregroundStyle(Color.cream.opacity(0.85))
                            PapiText(TableRoomStory.forRoom(topic.id).prompt).font(CoffeeType.display(.title3,weight:.bold))
                                .foregroundStyle(Color.cream).fixedSize(horizontal:false,vertical:true)
                        }.padding(.horizontal,8).frame(maxWidth:.infinity,alignment:.leading)
                        if voice.connected {
                            LiveVoiceParticipants(room:voice.room,account:account,microphoneEnabled:voice.microphoneEnabled)
                            VStack(alignment:.leading,spacing:10) {
                                PapiText("Room messages").font(CoffeeType.display(.title3,weight:.bold)).foregroundStyle(Color.cream)
                                if messageUnavailable {
                                    PapiText("Room messages unavailable. Try again.").font(CoffeeType.face(.caption)).foregroundStyle(Color.cream)
                                } else if roomMessages.isEmpty {
                                    PapiText("No room messages yet.").font(CoffeeType.face(.caption)).foregroundStyle(Color.cream.opacity(0.85))
                                }
                                ForEach(roomMessages.filter{!store.isUserHidden($0.sender_id.uuidString)}) {message in
                                    HStack(alignment:.top,spacing:9) {
                                        Avatar(name:store.person(message.sender_id.uuidString)?.portrait ?? "emptyCup",size:32)
                                        VStack(alignment:.leading,spacing:3) {
                                            PapiText(verbatim:store.person(message.sender_id.uuidString)?.name ?? store.text("Coffee friend"))
                                                .font(CoffeeType.face(.caption,weight:.bold))
                                            PapiText(verbatim:message.body).font(CoffeeType.face(.subheadline)).fixedSize(horizontal:false,vertical:true)
                                        }.frame(maxWidth:.infinity,alignment:.leading)
                                        if message.sender_id != account {
                                            PapiIconButton(asset:"moreLight",label:"Safety options",size:20) {router.sheet = .safety(.user(message.sender_id.uuidString))}
                                        }
                                    }.foregroundStyle(Color.coffee).padding(12).background(Color.cream,in:RoundedRectangle(cornerRadius:16))
                                }
                            }.frame(maxWidth:.infinity,alignment:.leading)
                        }
                        if let message=voice.message {
                            PapiText(message).font(CoffeeType.face(.subheadline)).foregroundStyle(Color.cream).fixedSize(horizontal:false,vertical:true)
                                .padding(14).frame(maxWidth:.infinity,alignment:.leading).background(Color.coffee.opacity(0.85),in:RoundedRectangle(cornerRadius:16))
                        }
                    }.padding(20).frame(maxWidth:720).frame(maxWidth:.infinity)
                }
                .safeAreaInset(edge:.bottom,spacing:0) {
                    VStack(spacing:4) {
                        if voice.connected {
                            PapiInputBar(background:.coffee) {
                                PapiInput("Write a room message…",text:Binding(get:{messageDraft},set:{messageDraft=String($0.prefix(300))}),axis:.vertical).lineLimit(1...3)
                                    .foregroundStyle(Color.coffee).tint(Color.coffee).padding(10)
                                    .background(Color.cream,in:RoundedRectangle(cornerRadius:16)).disabled(messageSending)
                            } actions: {
                                PapiIconButton(asset:"send",label:"Send room message",size:28) {Task {await sendRoomMessage()}}
                                    .disabled(messageSending || messageDraft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || activeSession==nil)
                            }
                            VoiceLoungeAction(title:voice.microphoneEnabled ? "Mute microphone":"Enable microphone",icon:"mic") {Task {await voice.setMicrophone(!voice.microphoneEnabled)}}
                            VoiceLoungeAction(title:"Leave room") {Task {await voice.disconnect(store:store);dismiss()}}
                                .disabled(voice.connecting || store.cloudVoiceBusy)
                        } else {
                            VoiceLoungeAction(title:voice.connecting ? "Connecting…":"Join voice room",icon:"mic") {Task {await voice.join(topic:topic.id,account:account,store:store)}}
                                .disabled(voice.connecting || store.cloudVoiceBusy)
                        }
                    }.padding(.horizontal,16).padding(.top,6).padding(.bottom,6).frame(maxWidth:720).frame(maxWidth:.infinity)
                        .papiAvoidReserved()
                }
            }
        }.onDisappear {Task {await voice.disconnect(store:store)}}
            .onChange(of:phase) {_,value in if value == .background {Task {await voice.disconnect(store:store)}}}
            .task(id:voice.connected) {
                guard voice.connected else {roomMessages=[];return}
                while !Task.isCancelled && voice.connected {
                    await refreshRoomMessages()
                    do {try await Task.sleep(for:.seconds(4))} catch {return}
                }
            }
    }
    private func refreshRoomMessages() async {
        guard let session=activeSession else{return}
        do {
            let rows=try await CoffeeCloud.shared.voiceMessages(topic:topic.id,session:session,account:account)
            guard !Task.isCancelled,activeSession==session else{return}
            roomMessages=Array(rows.reversed());messageUnavailable=false
            await store.ensureCloudProfiles(Set(rows.map(\.sender_id)))
        } catch {if !Task.isCancelled,activeSession==session {messageUnavailable=true}}
    }
    private func sendRoomMessage() async {
        let text=messageDraft.trimmingCharacters(in:.whitespacesAndNewlines)
        guard let session=activeSession,!messageSending,!text.isEmpty,text.count<=300,store.validateCommunityText(text) else{return}
        if pendingMessageID==nil || pendingMessageBody != text {pendingMessageID=UUID();pendingMessageBody=text}
        guard let id=pendingMessageID else{return}
        messageSending=true;defer {messageSending=false}
        do {
            try await CoffeeCloud.shared.sendVoiceMessage(topic:topic.id,session:session,id:id,body:text,account:account)
            guard activeSession==session else{return}
            if messageDraft.trimmingCharacters(in:.whitespacesAndNewlines)==text {messageDraft=""}
            pendingMessageID=nil;pendingMessageBody=""
            await refreshRoomMessages()
        } catch {if activeSession==session {messageUnavailable=true}}
    }
}
private struct VoiceLoungeAction:View {
    let title:String
    var icon:String? = nil
    let action:()->Void
    @Environment(\.isEnabled) private var enabled
    var body:some View {
        Button(action:action) {
            HStack(spacing:8) {
                if let icon {Image(icon).resizable().scaledToFit().frame(width:28,height:28).accessibilityHidden(true)}
                PapiText(title).font(CoffeeType.face(.subheadline,weight:.bold)).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
            }.foregroundStyle(Color.coffee).padding(.horizontal,22).frame(maxWidth:.infinity,minHeight:62)
                .background {Image("voiceActionPlate").resizable()}
                .contentShape(Rectangle()).opacity(enabled ? 1:0.5)
        }.buttonStyle(.plain)
    }
}
private struct LiveVoiceParticipants:View {
    @ObservedObject var room:Room
    let account:UUID
    let microphoneEnabled:Bool
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    var body:some View {
        let participants=Set(room.remoteParticipants.keys.compactMap { identity -> String? in
            let parts=identity.stringValue.split(separator:":",omittingEmptySubsequences:false)
            guard parts.count == 2, let user=UUID(uuidString:String(parts[0])),
                  UUID(uuidString:String(parts[1])) != nil else {return nil}
            return user.uuidString
        }).sorted()
        VStack(alignment:.leading,spacing:14) {
            HStack(alignment:.firstTextBaseline) {
                PapiText("Participants").font(CoffeeType.display(.title3,weight:.bold))
                Spacer(minLength:8)
                PapiText(microphoneEnabled ? "Microphone on":"Microphone off").font(CoffeeType.face(.caption,weight:.semibold)).foregroundStyle(Color.mutedCoffee)
            }
            ScrollView(.horizontal,showsIndicators:false) {
                HStack(alignment:.top,spacing:18) {
                    participant(account.uuidString,isSelf:true)
                    ForEach(participants,id:\.self) {id in
                        if !store.isUserHidden(id) {participant(id,isSelf:false)}
                    }
                }
            }
        }.foregroundStyle(Color.coffee).padding(18).frame(maxWidth:.infinity,alignment:.leading).background(Color.cream,in:RoundedRectangle(cornerRadius:20))
            .task(id:participants.joined(separator:"|")) {await store.ensureCloudProfiles(Set(participants.compactMap(UUID.init(uuidString:))))}
    }
    @ViewBuilder private func participant(_ id:String,isSelf:Bool)->some View {
        if let person=store.person(id),!store.isUserHidden(id) {
            VStack(spacing:7) {
                Button {router.goAfterClosingSheet(.person(id))} label:{
                    VStack(spacing:6) {
                        Avatar(name:person.portrait,size:64)
                        PapiText(verbatim:person.name).font(CoffeeType.face(.caption,weight:.semibold)).lineLimit(2).multilineTextAlignment(.center)
                    }.frame(width:88).frame(minHeight:92).contentShape(Rectangle())
                }.buttonStyle(.plain).papiAccessibilityLabel(person.name)
                if isSelf {PapiText("You").font(CoffeeType.face(.caption2,weight:.bold)).foregroundStyle(Color.mutedCoffee)}
                else {PapiIconButton(asset:"moreLight",label:"Safety options",size:20) {router.sheet = .safety(.user(id))}}
            }.frame(width:88)
        }
    }
}
