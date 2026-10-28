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
        let microphoneAllowed=await AVAudioApplication.requestRecordPermission()
        guard generation==attempt,!Task.isCancelled else{return}
        if !microphoneAllowed {message="Microphone permission was not granted."}
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
            if microphoneAllowed {await setMicrophone(true)}
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
    @State private var knownMessageIDs:Set<UUID>=[]
    @State private var messagesLoaded=false
    @State private var messageAnnouncement:CoffeeCloud.VoiceMessage?
    @State private var roomGifts:[CoffeeCloud.VoiceGift]=[]
    @State private var knownGiftIDs:Set<UUID>=[]
    @State private var giftsLoaded=false
    @State private var giftsUnavailable=false
    @State private var giftAnnouncement:CoffeeCloud.VoiceGift?
    @State private var sampleAnnouncement:LiveRoomSampleEvent?
    @State private var showingGifts=false
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
                    PapiIconButton(asset:"moreLight",label:"Safety options",size:20) {
                        router.sheet = .safety(.init(kind:.room,contentReference:topic.id))
                    }.background(Color.cream.opacity(0.94),in:Circle())
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
                                    PapiText(voice.connected ? (voice.microphoneEnabled ? "Microphone on":"Microphone off"):"Microphone permission is requested when you join.")
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
                            LiveVoiceParticipants(room:voice.room,account:account,microphoneEnabled:voice.microphoneEnabled) {
                                Task {
                                    guard voice.connected else{return}
                                    await voice.disconnect(store:store)
                                    voice.message="You left the room because a blocked or reported participant was present."
                                }
                            }
                            LiveRoomSamples(topicID:topic.id) {event in sampleAnnouncement=event}
                            VStack(alignment:.leading,spacing:10) {
                                PapiText("Room messages").font(CoffeeType.display(.title3,weight:.bold)).foregroundStyle(Color.cream)
                                if messageUnavailable {
                                    PapiText("Room messages unavailable. Try again.").font(CoffeeType.face(.caption)).foregroundStyle(Color.cream)
                                } else if roomMessages.isEmpty && roomGifts.isEmpty {
                                    PapiText("No room messages yet.").font(CoffeeType.face(.caption)).foregroundStyle(Color.cream.opacity(0.85))
                                }
                                if giftsUnavailable {PapiText("Room gifts unavailable. Try again.").font(CoffeeType.face(.caption)).foregroundStyle(Color.cream)}
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
                                ForEach(roomGifts.filter{!store.isUserHidden($0.sender_id.uuidString)}.suffix(5)) {event in
                                    if let gift=CoffeeCollectible.all.first(where:{$0.id==event.gift_id}) {
                                        HStack(spacing:9) {
                                            PapiArtworkFit(asset:gift.asset).frame(width:42,height:42)
                                            VStack(alignment:.leading,spacing:3) {
                                                PapiText(verbatim:store.person(event.sender_id.uuidString)?.name ?? store.text("Coffee friend")).font(CoffeeType.face(.caption,weight:.bold))
                                                PapiText("Sent \(gift.name) × \(event.quantity)").font(CoffeeType.face(.caption))
                                            }.frame(maxWidth:.infinity,alignment:.leading)
                                        }.foregroundStyle(Color.coffee).padding(10).background(Color.cream,in:RoundedRectangle(cornerRadius:16))
                                    }
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
                                PapiIconButton(asset:"roomGiftButton",label:"Gifts",size:32) {showingGifts=true}.disabled(activeSession==nil)
                                PapiIconButton(asset:"send",label:"Send room message",size:28) {Task {await sendRoomMessage()}}
                                    .background(Color.cream,in:RoundedRectangle(cornerRadius:12))
                                    .disabled(messageSending || messageDraft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || activeSession==nil)
                                    .opacity(messageSending || messageDraft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || activeSession==nil ? 0.55:1)
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
        }.sheet(isPresented:$showingGifts) {
            if let session=activeSession {VoiceRoomGiftSheet(topic:topic.id,session:session)}
        }
        .overlay(alignment:.top) {
            if let event=giftAnnouncement,let gift=CoffeeCollectible.all.first(where:{$0.id==event.gift_id}),!store.isUserHidden(event.sender_id.uuidString) {
                HStack(spacing:10) {
                    PapiArtworkFit(asset:gift.asset).frame(width:54,height:54)
                    VStack(alignment:.leading,spacing:3) {
                        PapiText(verbatim:store.person(event.sender_id.uuidString)?.name ?? store.text("Coffee friend")).font(CoffeeType.face(.caption,weight:.bold))
                        PapiText("Sent \(gift.name) × \(event.quantity)").font(CoffeeType.face(.subheadline,weight:.semibold))
                    }
                }.foregroundStyle(Color.coffee).padding(12).background {Image("voiceTopicPlate").resizable()}
                    .padding(.horizontal,20).padding(.top,58).allowsHitTesting(false).papiAvoidReserved()
            } else if let message=messageAnnouncement,!store.isUserHidden(message.sender_id.uuidString) {
                HStack(spacing:9) {
                    Avatar(name:store.person(message.sender_id.uuidString)?.portrait ?? "emptyCup",size:32)
                    VStack(alignment:.leading,spacing:3) {
                        PapiText(verbatim:store.person(message.sender_id.uuidString)?.name ?? store.text("Coffee friend")).font(CoffeeType.face(.caption,weight:.bold))
                        PapiText(verbatim:message.body).font(CoffeeType.face(.caption)).lineLimit(2)
                    }
                }.foregroundStyle(Color.coffee).padding(12).background {Image("voiceTopicPlate").resizable()}
                    .padding(.horizontal,20).padding(.top,58).allowsHitTesting(false).papiAvoidReserved()
            } else if voice.connected,let event=sampleAnnouncement,!store.isUserHidden(event.memberID),let member=store.person(event.memberID) {
                HStack(spacing:9) {
                    Avatar(name:member.portrait,size:32)
                    VStack(alignment:.leading,spacing:3) {
                        PapiText("Example activity").font(CoffeeType.face(.caption2,weight:.bold))
                        PapiText(verbatim:member.name).font(CoffeeType.face(.caption,weight:.bold))
                        PapiText(event.message).font(CoffeeType.face(.caption)).lineLimit(2)
                    }
                    if let asset=event.giftAsset {PapiArtworkFit(asset:asset).frame(width:42,height:42)}
                }.foregroundStyle(Color.coffee).padding(12).background {Image("voiceTopicPlate").resizable()}
                    .padding(.horizontal,20).padding(.top,58).allowsHitTesting(false).papiAvoidReserved()
            }
        }
        .onDisappear {Task {await voice.disconnect(store:store)}}
            .onChange(of:phase) {_,value in if value == .background {Task {await voice.disconnect(store:store)}}}
            .task(id:voice.connected) {
                guard voice.connected else {roomMessages=[];roomGifts=[];knownMessageIDs=[];messagesLoaded=false;messageAnnouncement=nil;knownGiftIDs=[];giftsLoaded=false;giftAnnouncement=nil;sampleAnnouncement=nil;return}
                while !Task.isCancelled && voice.connected {
                    await refreshRoomMessages()
                    await refreshRoomGifts()
                    do {try await Task.sleep(for:.seconds(4))} catch {return}
                }
            }
            .task(id:giftAnnouncement?.id) {
                guard let id=giftAnnouncement?.id else{return}
                do {try await Task.sleep(for:.seconds(3))} catch {return}
                if giftAnnouncement?.id==id {giftAnnouncement=nil}
            }
            .task(id:messageAnnouncement?.id) {
                guard let id=messageAnnouncement?.id else{return}
                do {try await Task.sleep(for:.seconds(3))} catch {return}
                if messageAnnouncement?.id==id {messageAnnouncement=nil}
            }
            .task(id:sampleAnnouncement?.id) {
                guard let id=sampleAnnouncement?.id else{return}
                do {try await Task.sleep(for:.seconds(3))} catch {return}
                if sampleAnnouncement?.id==id {sampleAnnouncement=nil}
            }
    }
    private func refreshRoomMessages() async {
        guard let session=activeSession else{return}
        do {
            let rows=try await CoffeeCloud.shared.voiceMessages(topic:topic.id,session:session,account:account)
            guard !Task.isCancelled,activeSession==session else{return}
            if messagesLoaded,let newest=rows.first(where:{!knownMessageIDs.contains($0.id) && !store.isUserHidden($0.sender_id.uuidString)}) {messageAnnouncement=newest}
            knownMessageIDs=Set(rows.map(\.id));messagesLoaded=true;roomMessages=Array(rows.reversed());messageUnavailable=false
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
    private func refreshRoomGifts() async {
        guard let session=activeSession else{return}
        do {
            let rows=try await CoffeeCloud.shared.voiceGifts(topic:topic.id,session:session,account:account)
            guard !Task.isCancelled,activeSession==session else{return}
            if giftsLoaded,let newest=rows.first(where:{!knownGiftIDs.contains($0.id) && !store.isUserHidden($0.sender_id.uuidString)}) {giftAnnouncement=newest}
            knownGiftIDs=Set(rows.map(\.id));giftsLoaded=true;roomGifts=Array(rows.reversed());giftsUnavailable=false
            await store.ensureCloudProfiles(Set(rows.map(\.sender_id)))
        } catch {if !Task.isCancelled,activeSession==session {giftsUnavailable=true}}
    }
}
private struct LiveRoomSampleEvent:Identifiable {
    let id=UUID()
    let memberID:String
    let message:String
    let giftAsset:String?
}

private struct LiveRoomSamples:View {
    let topicID:String
    let onEvent:(LiveRoomSampleEvent)->Void
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var events:[LiveRoomSampleEvent]=[]
    @State private var index=0
    private var story:TableRoomStory {TableRoomStory.forRoom(topicID)}
    private var members:[CoffeeMember] {story.guestIDs.compactMap {id in store.isUserHidden(id) ? nil:store.person(id)}}
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                PapiText("Sample participants").font(CoffeeType.face(.headline))
                Spacer(minLength:0)
                PapiText("Example activity").font(CoffeeType.face(.caption2,weight:.semibold))
            }
            ScrollView(.horizontal,showsIndicators:false) {
                HStack(alignment:.top,spacing:12) {
                    ForEach(members) {member in
                        Button {router.go(.person(member.id))} label:{
                            VStack(spacing:5) {
                                Avatar(name:member.portrait,size:48)
                                PapiText(verbatim:member.name).font(CoffeeType.face(.caption2,weight:.semibold)).lineLimit(2).multilineTextAlignment(.center)
                            }.frame(width:84).frame(minHeight:78).contentShape(Rectangle())
                        }.buttonStyle(.plain).papiAccessibilityLabel(member.name)
                    }
                }
            }
            ForEach(events.filter{!store.isUserHidden($0.memberID)}) {event in
                if let member=store.person(event.memberID) {
                    HStack(alignment:.center,spacing:9) {
                        Avatar(name:member.portrait,size:32)
                        VStack(alignment:.leading,spacing:3) {
                            PapiText(verbatim:member.name).font(CoffeeType.face(.caption,weight:.bold))
                            PapiText(event.message).font(CoffeeType.face(.caption)).fixedSize(horizontal:false,vertical:true)
                        }.frame(maxWidth:.infinity,alignment:.leading)
                        if let asset=event.giftAsset {PapiArtworkFit(asset:asset).frame(width:38,height:38)}
                    }.padding(10).frame(maxWidth:.infinity,alignment:.leading)
                        .background(Color.cream.opacity(0.10),in:RoundedRectangle(cornerRadius:14))
                        .transition(reduceMotion ? .opacity:.move(edge:.leading).combined(with:.opacity))
                }
            }
        }.foregroundStyle(Color.cream).padding(16).frame(maxWidth:.infinity,alignment:.leading)
            .background(Color.coffee.opacity(0.78),in:RoundedRectangle(cornerRadius:20))
            .task(id:topicID) {
                if events.isEmpty {for item in 0..<3 {appendEvent(announce:item==2)}}
                while !Task.isCancelled {
                    do {try await Task.sleep(for:.seconds(5))} catch {return}
                    if phase == .active && router.sheet == nil && store.notice == nil {appendEvent(announce:true)}
                }
            }
    }
    private func appendEvent(announce:Bool) {
        let available=members
        guard !available.isEmpty else{return}
        let messages=story.messages+["A little gift for the table · Sample"]
        let event=LiveRoomSampleEvent(memberID:available[index % available.count].id,message:messages[index % messages.count],giftAsset:index % messages.count == messages.count-1 ? story.giftAsset:nil)
        index+=1
        withAnimation(reduceMotion ? nil:.easeInOut(duration:0.25)) {events.append(event);if events.count>3 {events.removeFirst(events.count-3)}}
        if announce {onEvent(event)}
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
private struct VoiceRoomGiftSheet:View {
    let topic:String
    let session:UUID
    @EnvironmentObject private var store:CoffeeHouse
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selected=CoffeeCollectible.all[0].id
    @State private var quantity=1
    @State private var confirming=false
    private var gift:CoffeeCollectible {CoffeeCollectible.all.first(where:{$0.id==selected}) ?? CoffeeCollectible.all[0]}
    var body:some View {
        PapiDeviceContainer {
            PapiScreen {
                VStack(spacing:0) {
                    PapiHeader("Gifts")
                    ScrollView {
                        VStack(alignment:.leading,spacing:16) {
                            HStack {
                                VStack(alignment:.leading,spacing:5) {
                                    PapiText("Send a room gift").font(CoffeeType.display(.title2,weight:.bold))
                                    PapiText("Gifts appear in the room and cost the displayed coins. They are not credited to a participant.")
                                        .font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee).fixedSize(horizontal:false,vertical:true)
                                }.frame(maxWidth:.infinity,alignment:.leading)
                                CoffeeCurrentBalance().font(CoffeeType.face(.subheadline,weight:.bold))
                            }
                            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:8),count:typeSize.isAccessibilitySize ? 1:2),spacing:8) {
                                ForEach(CoffeeCollectible.all) {item in
                                    Button {selected=item.id} label:{
                                        HStack(spacing:8) {
                                            PapiArtworkFit(asset:item.asset).frame(width:48,height:48)
                                            VStack(alignment:.leading,spacing:4) {
                                                PapiText(item.name).font(CoffeeType.face(.caption,weight:.bold)).fixedSize(horizontal:false,vertical:true)
                                                CoinLabel(value:item.cost).font(CoffeeType.face(.caption2))
                                            }.frame(maxWidth:.infinity,alignment:.leading)
                                        }.padding(.horizontal,12).frame(minHeight:76)
                                            .background {Image("voiceActionPlate").resizable().opacity(selected==item.id ? 1:0.65)}
                                    }.buttonStyle(.plain).disabled(store.state.pendingCloudRoomGift != nil)
                                        .accessibilityAddTraits(selected==item.id ? .isSelected:[])
                                }
                            }
                            HStack(spacing:8) {
                                PapiTextButton("Less") {quantity=max(1,quantity-1)}.frame(minWidth:44,minHeight:44).disabled(quantity==1 || store.state.pendingCloudRoomGift != nil)
                                PapiText("Quantity \(quantity)").font(CoffeeType.face(.subheadline,weight:.semibold)).frame(maxWidth:.infinity)
                                PapiTextButton("More") {quantity=min(99,quantity+1)}.frame(minWidth:44,minHeight:44).disabled(quantity==99 || store.state.pendingCloudRoomGift != nil)
                            }
                            HStack {PapiText("Total");Spacer();CoinLabel(value:gift.cost*quantity)}.font(CoffeeType.face(.headline))
                            if let pending=store.state.pendingCloudRoomGift {
                                PapiText("Your previous gift needs confirmation. Retry it or cancel the pending request.")
                                    .font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee).fixedSize(horizontal:false,vertical:true)
                                VoiceLoungeAction(title:"Retry pending gift") {
                                    Task {_ = await store.cloudRoomGift(gift:nil,quantity:pending.quantity,topic:pending.topic,session:pending.sessionID)}
                                }.disabled(store.cloudWalletBusy)
                                VoiceLoungeAction(title:"Cancel pending gift") {
                                    Task {_ = await store.cloudRoomGift(gift:nil,quantity:pending.quantity,topic:pending.topic,session:pending.sessionID,cancel:true)}
                                }.disabled(store.cloudWalletBusy)
                            } else {
                                VoiceLoungeAction(title:"Send gift") {confirming=true}.disabled(store.cloudWallet==nil || store.cloudWalletBusy)
                            }
                            if store.cloudWallet==nil && store.state.pendingCloudRoomGift==nil {
                                PapiTextButton("Retry wallet") {Task {await store.refreshCloudWallet()}}.disabled(store.cloudWalletBusy)
                            }
                        }.padding(20).frame(maxWidth:680).frame(maxWidth:.infinity)
                    }
                }.overlay {
                    if confirming {
                        PapiDialog(title:"Send gift?",message:"Spend \(gift.cost*quantity) coins to share \(gift.name) × \(quantity) with this room?",confirm:"Send gift",cancel:"Cancel",action:{
                            confirming=false
                            let chosen=gift;let count=quantity
                            Task {if await store.cloudRoomGift(gift:chosen,quantity:count,topic:topic,session:session) {dismiss()}}
                        },dismiss:{confirming=false})
                    }
                }
            }
        }.onAppear {
            if let pending=store.state.pendingCloudRoomGift {selected=pending.giftID;quantity=pending.quantity}
        }
    }
}
private struct LiveVoiceParticipants:View {
    @ObservedObject var room:Room
    let account:UUID
    let microphoneEnabled:Bool
    var onHiddenParticipant:()->Void
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
            .task(id:participants.joined(separator:"|")+"/"+store.visibilityKeys.joined(separator:"|")) {
                if participants.contains(where:store.isUserHidden) {onHiddenParticipant();return}
                await store.ensureCloudProfiles(Set(participants.compactMap(UUID.init(uuidString:))))
            }
    }
    @ViewBuilder private func participant(_ id:String,isSelf:Bool)->some View {
        if !store.isUserHidden(id) {
            let person=store.person(id)
            let name=person?.name ?? store.text("Coffee friend")
            VStack(spacing:7) {
                Button {router.goAfterClosingSheet(.person(id))} label:{
                    VStack(spacing:6) {
                        Avatar(name:person?.portrait ?? "emptyCup",size:64)
                        PapiText(verbatim:name).font(CoffeeType.face(.caption,weight:.semibold)).lineLimit(2).multilineTextAlignment(.center)
                    }.frame(width:88).frame(minHeight:92).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(person == nil).papiAccessibilityLabel(name)
                if isSelf {PapiText("You").font(CoffeeType.face(.caption2,weight:.bold)).foregroundStyle(Color.mutedCoffee)}
                else {PapiIconButton(asset:"moreLight",label:"Safety options",size:20) {router.sheet = .safety(.user(id))}}
            }.frame(width:88)
        }
    }
}
