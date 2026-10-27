import SwiftUI
import AVFoundation
@preconcurrency import LiveKit

// Prepared for the consent-based call flow. It is not routed from the app until
// the token service, remote participant removal and device validation are ready.
@MainActor final class CoffeeLiveCall:ObservableObject {
    let room=Room()
    @Published private(set) var connecting=false
    @Published private(set) var connected=false
    @Published private(set) var microphoneEnabled=false
    @Published private(set) var cameraEnabled=false
    @Published var message:String?
    private var sessionID:UUID?
    private var accountID:UUID?
    private var generation=UUID()
    private var monitor:Task<Void,Never>?

    func join(call:UUID,account:UUID) async {
        guard !connecting,!connected else{return}
        let attempt=UUID();generation=attempt;connecting=true;message=nil
        do {
            guard try await CoffeeCloud.shared.canJoinCall(id:call,account:account) else {throw CoffeeCloud.ConnectionError.actionUnavailable}
            let credentials=try await CoffeeCloud.shared.callToken(id:call,account:account)
            guard generation==attempt,!Task.isCancelled else {connecting=false;return}
            try await room.connect(url:credentials.server_url,token:credentials.participant_token,
                                   connectOptions:ConnectOptions(enableMicrophone:false))
            guard generation==attempt,!Task.isCancelled,try await CoffeeCloud.shared.canJoinCall(id:call,account:account) else {
                await room.disconnect();connecting=false;return
            }
            sessionID=call;accountID=account;connected=true;connecting=false
            monitor=Task { [weak self] in
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for:.seconds(5))
                        guard let self else{return}
                        let allowed=try await CoffeeCloud.shared.canJoinCall(id:call,account:account)
                        if !allowed {await self.disconnect();return}
                    } catch {if !Task.isCancelled {await self?.disconnect()};return}
                }
            }
        } catch {
            await room.disconnect();connecting=false;connected=false
            if generation==attempt {message="The call could not be connected."}
        }
    }

    func setMicrophone(_ enabled:Bool) async {
        guard connected else{return}
        if enabled,!(await AVAudioApplication.requestRecordPermission()) {message="Microphone permission was not granted.";return}
        do {_ = try await room.localParticipant.setMicrophone(enabled:enabled);microphoneEnabled=enabled}
        catch {message="The microphone could not be changed."}
    }
    func setCamera(_ enabled:Bool) async {
        guard connected else{return}
        if enabled,!(await AVCaptureDevice.requestAccess(for:.video)) {message="Camera permission was not granted.";return}
        do {_ = try await room.localParticipant.setCamera(enabled:enabled);cameraEnabled=enabled}
        catch {message="The camera could not be changed."}
    }
    func disconnect() async {
        generation=UUID();monitor?.cancel();monitor=nil
        await room.disconnect();connecting=false;connected=false;microphoneEnabled=false;cameraEnabled=false
    }
    func end() async {
        let call=sessionID,account=accountID
        await disconnect()
        guard let call,let account else{return}
        do {try await CoffeeCloud.shared.endCall(id:call,account:account);sessionID=nil;accountID=nil}
        catch {message="The call ended on this device. Its server status needs another attempt."}
    }
}

struct CoffeeLiveCallView:View {
    let callID:UUID
    let accountID:UUID
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
                        PapiTextButton("End call"){Task {await call.end()}}
                    }
                } else {PapiTextButton(call.connecting ? "Connecting…":"Join call"){Task {await call.join(call:callID,account:accountID)}}.disabled(call.connecting)}
            }.padding(16)
        }.onDisappear {Task {await call.end()}}
            .onChange(of:scenePhase){_,phase in if phase != .active {Task {await call.end()}}}
    }
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
