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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @StateObject private var voice=CoffeeLiveVoice()
    var body:some View {
        PapiScreen(background:"roomBackground") {
            VStack(spacing:0) {
                PapiHeader(topic.title)
                ScrollView {
                    VStack(alignment:.leading,spacing:18) {
                        PapiImage(name:cover).frame(height:220).clipped().clipShape(RoundedRectangle(cornerRadius:22))
                        PapiText(topic.category).font(CoffeeType.face(.subheadline)).foregroundStyle(Color.cream)
                        if voice.connected {LiveVoiceParticipants(room:voice.room,account:account)}
                        if let message=voice.message {PapiText(message).foregroundStyle(Color.cream).fixedSize(horizontal:false,vertical:true)}
                        PapiActionGroup {
                            if voice.connected {
                                PapiTextButton(voice.microphoneEnabled ? "Mute microphone":"Enable microphone") {Task {await voice.setMicrophone(!voice.microphoneEnabled)}}
                                PapiTextButton("Leave room") {Task {await voice.disconnect(store:store);dismiss()}}
                            } else {
                                PapiTextButton(voice.connecting ? "Connecting…":"Join voice room") {Task {await voice.join(topic:topic.id,account:account,store:store)}}
                                    .disabled(voice.connecting || store.cloudVoiceBusy)
                            }
                        }.buttonStyle(PapiButtonStyle())
                    }.padding(20).frame(maxWidth:720).frame(maxWidth:.infinity)
                }
            }
        }.onDisappear {Task {await voice.disconnect(store:store)}}
            .onChange(of:phase) {_,value in if value == .background {Task {await voice.disconnect(store:store)}}}
    }
}
private struct LiveVoiceParticipants:View {
    @ObservedObject var room:Room
    let account:UUID
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    var body:some View {
        let participants=Set(room.remoteParticipants.keys.compactMap { identity -> String? in
            let parts=identity.stringValue.split(separator:":",omittingEmptySubsequences:false)
            guard parts.count == 2, let user=UUID(uuidString:String(parts[0])),
                  UUID(uuidString:String(parts[1])) != nil else {return nil}
            return user.uuidString
        }).sorted()
        VStack(alignment:.leading,spacing:10) {
            PapiText("Participants").font(CoffeeType.face(.headline)).foregroundStyle(Color.coffee)
            PapiUserLink(userID:account.uuidString,size:42)
            ForEach(participants,id:\.self) {id in
                if !store.isUserHidden(id) {
                    HStack {
                        PapiUserLink(userID:id,size:42)
                        Spacer(minLength:8)
                        PapiIconButton(asset:"moreLight",label:"Safety options",size:20) {router.sheet = .safety(.user(id))}
                    }
                }
            }
        }.padding(16).frame(maxWidth:.infinity,alignment:.leading).background(Color.cream,in:RoundedRectangle(cornerRadius:18))
            .task(id:participants.joined(separator:"|")) {await store.ensureCloudProfiles(Set(participants.compactMap(UUID.init(uuidString:))))}
    }
}
