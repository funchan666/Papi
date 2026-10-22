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
        let granted = await withCheckedContinuation { (continuation:CheckedContinuation<Bool,Never>) in
            AVAudioSession.sharedInstance().requestRecordPermission {continuation.resume(returning:$0)}
        }
        guard !Task.isCancelled else {return}
        guard granted else {message="Microphone permission was not granted. You can change it in iOS Settings.";return}
        do {
            try PapiAudioSession.acquire(audioID,recording:true)
            let name=UUID().uuidString+".m4a"
            let url=try MediaFiles.directory(owner).appendingPathComponent(name)
            let recorder=try AVAudioRecorder(url:url,settings:[AVFormatIDKey:kAudioFormatMPEG4AAC,AVSampleRateKey:44100,AVNumberOfChannelsKey:1,AVEncoderAudioQualityKey:AVAudioQuality.high.rawValue])
            recorder.delegate=self
            guard recorder.record() else {throw MediaFiles.MediaError.invalid}
            self.recorder=recorder;self.owner=owner;savedName="local/\(owner.uuidString)/\(name)";recording=true
            message="Recording locally. Tap Stop to keep this voice draft."
        } catch {message="Recording could not start. Please try again.";releaseAudio()}
    }
    func stop() {
        guard recording else{return}
        recorder?.stop();recording=false;releaseAudio();message="Voice draft recorded on this device."
    }
    func releaseAudio(){PapiAudioSession.release(audioID)}
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
    var personID:String
    @EnvironmentObject private var store:PapiStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @StateObject private var recorder=VoiceDraftRecorder()
    @State private var requesting=false
    @State private var owner:UUID?
    @State private var recordingTask:Task<Void,Never>?
    var body:some View {
        PapiScreen {VStack(spacing:24){
            PapiHeader("Voice draft")
            Spacer()
            Image("mic").resizable().scaledToFit().frame(width:90,height:90)
            PapiText(recorder.message).font(.body).multilineTextAlignment(.center).padding(.horizontal,28)
            PapiTextButton(recorder.recording ? "Stop recording":"Record") {
                if recorder.recording {recorder.stop()}
                else {requesting=true;let guest=store.state.profile.id;owner=guest;recordingTask=Task{await recorder.start(owner:guest);requesting=false}}
            }.buttonStyle(PapiButtonStyle()).disabled(requesting)
            if let name=recorder.savedName,!recorder.recording {
                LocalVoicePlayer(name:name)
                PapiTextButton("Keep draft") {
                    guard owner==store.state.profile.id else{return}
                    if store.commit({$0.voiceDrafts[personID]=name}){dismiss()}
                }.buttonStyle(PapiButtonStyle(light:true))
            }
            Spacer()
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
        audioObserver=NotificationCenter.default.addObserver(forName:PapiAudioSession.changed,object:nil,queue:.main) {[weak self] _ in
            Task {@MainActor in if let self,PapiAudioSession.owner != self.audioID {self.stop()}}
        }
        interruptionObserver=NotificationCenter.default.addObserver(forName:AVAudioSession.interruptionNotification,object:nil,queue:.main) {[weak self] _ in
            Task {@MainActor in self?.stop()}
        }
    }
    func toggle(_ name:String) {
        if playing {stop();return}
        errorMessage=nil
        guard let url=MediaFiles.url(name) else {errorMessage="This voice draft is unavailable.";return}
        do {
            try PapiAudioSession.acquire(audioID)
            let p=try AVAudioPlayer(contentsOf:url);p.delegate=self;player=p;playing=p.play()
            if !playing {stop();errorMessage="Audio could not start. Please try again."}
        } catch {stop();errorMessage="Audio could not start. Please try again."}
    }
    func stop(){player?.stop();playing=false;PapiAudioSession.release(audioID)}
    nonisolated func audioPlayerDidFinishPlaying(_ player:AVAudioPlayer,successfully flag:Bool) {Task{@MainActor in guard self.player === player else{return};self.stop()}}
    deinit {
        if let audioObserver {NotificationCenter.default.removeObserver(audioObserver)}
        if let interruptionObserver {NotificationCenter.default.removeObserver(interruptionObserver)}
    }
}
struct LocalVoicePlayer:View {
    var name:String
    @StateObject private var playback=VoicePlayback()
    @Environment(\.scenePhase) private var phase
    var body:some View {
        VStack(spacing:8) {
            Button {playback.toggle(name)} label:{HStack{Image("speaker").resizable().scaledToFit().frame(width:32,height:32);PapiText(playback.playing ? "Stop voice draft":"Play local voice draft")}.padding(10).background(Color.butter,in:Capsule())}.buttonStyle(.plain)
            if let error=playback.errorMessage {PapiText(error).font(.caption).foregroundStyle(Color.mutedCoffee)}
        }.onDisappear{playback.stop()}.onChange(of:phase){_,p in if p != .active {playback.stop()}}
    }
}
