import SwiftUI
import AVFoundation

@MainActor final class VoiceDraftRecorder:NSObject,ObservableObject,AVAudioRecorderDelegate {
    @Published private(set) var recording=false
    @Published private(set) var savedName:String?
    @Published var message="Record a private voice draft. It is not sent to anyone."
    private var recorder:AVAudioRecorder?
    private var owner:UUID?
    private let audioID=UUID()
    private var interruptionObserver:NSObjectProtocol?
    override init() {
        super.init()
        interruptionObserver=NotificationCenter.default.addObserver(forName:AVAudioSession.interruptionNotification,object:nil,queue:.main) {[weak self] _ in
            Task {@MainActor in self?.stop()}
        }
    }
    func start(owner:UUID) async {
        guard !recording else{return}
        let granted = await AVAudioApplication.requestRecordPermission()
        guard !Task.isCancelled else {return}
        guard granted else {message="Microphone permission was not granted. You can change it in iOS Settings.";return}
        do {
            try AudioFocus.acquire(audioID,recording:true)
            let name=UUID().uuidString+".m4a"
            let url=try CoffeeMedia.directory(owner).appendingPathComponent(name)
            let recorder=try AVAudioRecorder(url:url,settings:[AVFormatIDKey:kAudioFormatMPEG4AAC,AVSampleRateKey:44100,AVNumberOfChannelsKey:1,AVEncoderAudioQualityKey:AVAudioQuality.high.rawValue])
            recorder.delegate=self
            guard recorder.record() else {throw CoffeeMedia.MediaError.invalid}
            self.recorder=recorder;self.owner=owner;savedName="local/\(owner.uuidString)/\(name)";recording=true
            message="Recording your voice note. Tap Stop to keep it."
        } catch {message="Recording could not start. Please try again.";releaseAudio()}
    }
    func stop() {
        guard recording else{return}
        recorder?.stop();recording=false;releaseAudio();message="Your voice note is ready to keep."
    }
    func releaseAudio(){AudioFocus.release(audioID)}
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder:AVAudioRecorder,error:Error?) {
        Task {@MainActor in guard self.recorder === recorder else{return};self.stop();self.savedName=nil;self.message="Recording could not be saved. Please record again."}
    }
    nonisolated func audioRecorderDidFinishRecording(_ recorder:AVAudioRecorder,successfully flag:Bool) {
        Task {@MainActor in
            guard self.recorder === recorder else{return}
            self.recording=false;self.releaseAudio()
            if !flag {self.savedName=nil;self.message="Recording could not be saved. Please record again."}
        }
    }
    deinit {if let interruptionObserver {NotificationCenter.default.removeObserver(interruptionObserver)}}
}
struct VoiceDraftView:View {
    var memberID:String
    @EnvironmentObject private var store:CoffeeHouse
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @StateObject private var recorder=VoiceDraftRecorder()
    @State private var requesting=false
    @State private var owner:UUID?
    @State private var recordingTask:Task<Void,Never>?
    var body:some View {
        PapiScreen {VStack(spacing:0){
            PapiHeader("Voice draft")
            ScrollView {
                VStack(spacing:24) {
                    Image("mic").resizable().scaledToFit().frame(width:90,height:90)
                    PapiText(recorder.message).font(CoffeeType.face(.body)).multilineTextAlignment(.center).padding(.horizontal,28)
                    PapiTextButton(recorder.recording ? "Stop recording":"Record") {
                        if recorder.recording {recorder.stop()}
                        else {requesting=true;let guest=store.state.passport.id;owner=guest;recordingTask=Task{await recorder.start(owner:guest);requesting=false}}
                    }.buttonStyle(PapiButtonStyle()).disabled(requesting)
                    if let name=recorder.savedName,!recorder.recording {
                        VoiceNotePlayer(name:name)
                        PapiTextButton("Keep draft") {
                            guard owner==store.state.passport.id else{return}
                            if store.commit({$0.letterVoiceNotes[memberID]=name}){dismiss()}
                        }.buttonStyle(PapiButtonStyle(light:true))
                    }
                }.padding(20).frame(maxWidth:620).frame(maxWidth:.infinity)
            }
        }}.onDisappear{recordingTask?.cancel();recorder.stop()}.onChange(of:phase){_,p in if p == .background {recordingTask?.cancel();recorder.stop()}}
    }
}
@MainActor final class VoicePlayback:NSObject,ObservableObject,AVAudioPlayerDelegate {
    @Published var playing=false
    @Published var errorMessage:String?
    private var player:AVAudioPlayer?
    private let audioID=UUID()
    private var audioObserver:NSObjectProtocol?
    private var interruptionObserver:NSObjectProtocol?
    override init() {
        super.init()
        audioObserver=NotificationCenter.default.addObserver(forName:AudioFocus.changed,object:nil,queue:.main) {[weak self] _ in
            Task {@MainActor in if let self,AudioFocus.owner != self.audioID {self.stop()}}
        }
        interruptionObserver=NotificationCenter.default.addObserver(forName:AVAudioSession.interruptionNotification,object:nil,queue:.main) {[weak self] _ in
            Task {@MainActor in self?.stop()}
        }
    }
    func toggle(_ name:String) {
        if playing {stop();return}
        errorMessage=nil
        guard let url=CoffeeMedia.url(name) else {errorMessage="This voice draft is unavailable.";return}
        do {
            try AudioFocus.acquire(audioID)
            let p=try AVAudioPlayer(contentsOf:url);p.delegate=self;player=p;playing=p.play()
            if !playing {stop();errorMessage="Audio could not start. Please try again."}
        } catch {stop();errorMessage="Audio could not start. Please try again."}
    }
    func play(data:Data) {
        errorMessage=nil
        do {
            try AudioFocus.acquire(audioID)
            let p=try AVAudioPlayer(data:data);p.delegate=self;player=p;playing=p.play()
            if !playing {stop();errorMessage="Audio could not start. Please try again."}
        } catch {stop();errorMessage="Audio could not start. Please try again."}
    }
    func stop(){player?.stop();playing=false;AudioFocus.release(audioID)}
    nonisolated func audioPlayerDidFinishPlaying(_ player:AVAudioPlayer,successfully flag:Bool) {Task{@MainActor in guard self.player === player else{return};self.stop()}}
    deinit {
        if let audioObserver {NotificationCenter.default.removeObserver(audioObserver)}
        if let interruptionObserver {NotificationCenter.default.removeObserver(interruptionObserver)}
    }
}
struct CloudVoiceNotePlayer:View {
    let messageID:String
    let name:String
    @EnvironmentObject private var store:CoffeeHouse
    @Environment(\.scenePhase) private var phase
    @StateObject private var playback=VoicePlayback()
    @State private var loading=false
    @State private var loadTask:Task<Void,Never>?
    private static let session:URLSession = {
        let config=URLSessionConfiguration.ephemeral
        config.urlCache=nil;config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpCookieStorage=nil;config.httpShouldSetCookies=false
        config.timeoutIntervalForRequest=20;config.timeoutIntervalForResource=40
        return URLSession(configuration:config)
    }()
    var body:some View {
        VStack(spacing:8) {
            Button {
                if playback.playing {playback.stop();return}
                guard !loading else{return}
                loading=true;loadTask=Task {await play()}
            } label:{HStack {Image("speaker").resizable().scaledToFit().frame(width:32,height:32);PapiText(loading ? "Loading voice note…":(playback.playing ? "Stop voice note":"Play voice note"))}.padding(10).background(Color.butter,in:Capsule())}.buttonStyle(.plain).disabled(loading)
            if let error=playback.errorMessage {PapiText(error).font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)}
        }.onDisappear{loadTask?.cancel();playback.stop()}.onChange(of:phase){_,p in if p != .active {loadTask?.cancel();playback.stop()}}
    }
    @MainActor private func play() async {
        defer{loading=false}
        guard phase == .active,store.state.signedIn,let account=store.state.cloudAccountID,
              name.hasPrefix("cloud/"),let id=UUID(uuidString:messageID),
              let message=(store.cloudConversations.values.flatMap{$0}+store.cloudMessages).first(where:{$0.id==id}),
              store.isTargetVisible(.init(kind:.message,contentReference:messageID,authorID:message.sender_id.uuidString)) else{return}
        do {
            let url=try await CoffeeCloud.shared.mediaURL(path:String(name.dropFirst(6)),account:account)
            guard url.scheme=="https",url.host=="cquoffowtjnxmgaxavym.supabase.co" else {throw CoffeeMedia.MediaError.invalid}
            let (data,response)=try await Self.session.data(from:url)
            guard let response=response as? HTTPURLResponse,response.statusCode==200,response.url?.host==url.host,
                  response.url?.scheme=="https",response.mimeType?.hasPrefix("audio/")==true,data.count<=52_428_800,
                  !Task.isCancelled,store.state.signedIn,store.state.cloudAccountID==account,phase == .active,
                  store.isTargetVisible(.init(kind:.message,contentReference:messageID,authorID:message.sender_id.uuidString)) else{return}
            playback.play(data:data)
        } catch {if !Task.isCancelled {playback.errorMessage="This voice note is unavailable. Please try again."}}
    }
}
struct VoiceNotePlayer:View {
    var name:String
    @StateObject private var playback=VoicePlayback()
    @Environment(\.scenePhase) private var phase
    var body:some View {
        VStack(spacing:8) {
            Button {playback.toggle(name)} label:{HStack{Image("speaker").resizable().scaledToFit().frame(width:32,height:32);PapiText(playback.playing ? "Stop voice draft":"Play voice draft")}.padding(10).background(Color.butter,in:Capsule())}.buttonStyle(.plain)
            if let error=playback.errorMessage {PapiText(error).font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)}
        }.onDisappear{playback.stop()}.onChange(of:phase){_,p in if p != .active {playback.stop()}}
    }
}
