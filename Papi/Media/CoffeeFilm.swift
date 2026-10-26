import SwiftUI
import AVFoundation

@MainActor final class CoffeeFilmPlayback:ObservableObject {
    let player=AVPlayer()
    @Published var playing=false
    @Published var position:Double=0
    @Published var duration:Double=0
    @Published var failure:String?
    private var loaded:String?
    private var observer:Any?
    private var statusObservation:NSKeyValueObservation?
    private var finishObserver:NSObjectProtocol?
    private let audioID=UUID()
    private var audioObserver:NSObjectProtocol?
    private var interruptionObserver:NSObjectProtocol?
    init() {
        audioObserver=NotificationCenter.default.addObserver(forName:AudioFocus.changed,object:nil,queue:.main) {[weak self] _ in
            Task {@MainActor in if let self,AudioFocus.owner != self.audioID {self.pause()}}
        }
        interruptionObserver=NotificationCenter.default.addObserver(forName:AVAudioSession.interruptionNotification,object:nil,queue:.main) {[weak self] _ in
            Task {@MainActor in self?.pause()}
        }
    }
    func load(_ media:String,force:Bool=false) {
        guard loaded != media || force else{return}
        pause()
        statusObservation=nil
        if let finishObserver {NotificationCenter.default.removeObserver(finishObserver)}
        finishObserver=nil
        loaded=nil;position=0;duration=0
        player.replaceCurrentItem(with:nil)
        guard let url=CoffeeMedia.url(media) else {failure="This video is unavailable.";return}
        loaded=media;failure=nil
        let item=AVPlayerItem(url:url);player.replaceCurrentItem(with:item)
        statusObservation=item.observe(\.status,options:[.initial,.new]) { [weak self] item,_ in
            Task { @MainActor in
                guard let self,self.player.currentItem === item else{return}
                if item.status == .failed {self.failure="This video could not be played. Try another coffee moment.";self.pause()}
                if item.status == .readyToPlay {let seconds=item.duration.seconds;self.duration=seconds.isFinite ? seconds:0}
            }
        }
        if observer==nil {observer=player.addPeriodicTimeObserver(forInterval:CMTime(seconds:0.25,preferredTimescale:600),queue:.main) { [weak self] time in
            Task { @MainActor in self?.position=time.seconds.isFinite ? time.seconds:0 }
        }}
        finishObserver=NotificationCenter.default.addObserver(forName:.AVPlayerItemDidPlayToEndTime,object:item,queue:.main) { [weak self] _ in
            Task { @MainActor in guard let self,self.player.currentItem === item else{return};self.pause();self.player.seek(to:.zero) }
        }
    }
    func toggle() {
        guard failure==nil else{return}
        if playing {pause()} else {
            do {try AudioFocus.acquire(audioID);player.play();playing=true}
            catch {failure="Audio could not start. Please try again."}
        }
    }
    func pause() {player.pause();playing=false;AudioFocus.release(audioID)}
    func seek(_ seconds:Double) {player.seek(to:CMTime(seconds:seconds,preferredTimescale:600));position=seconds}
    deinit {
        if let observer {player.removeTimeObserver(observer)}
        if let finishObserver {NotificationCenter.default.removeObserver(finishObserver)}
        if let audioObserver {NotificationCenter.default.removeObserver(audioObserver)}
        if let interruptionObserver {NotificationCenter.default.removeObserver(interruptionObserver)}
    }
}
struct CoffeePlayerView:View {
    let media:String
    @ScaledMetric(relativeTo:.body) private var seekWidth:CGFloat=120
    @StateObject private var playback=CoffeeFilmPlayback()
    @Environment(\.scenePhase) private var scenePhase
    var body:some View {
        VStack(spacing:0) {
            ZStack {
                Color.black
                PlayerSurface(player:playback.player)
                if let failure=playback.failure {
                    ScrollView {VStack(spacing:14) {PapiText(failure);PapiTextButton("Retry"){playback.load(media,force:true)}.frame(minHeight:44)}
                        .foregroundStyle(.white).multilineTextAlignment(.center).padding(20)}
                }
            }
            PapiComposerLayout(minimumInputWidth:seekWidth) {
                Slider(value:Binding(get:{min(playback.position,max(1,playback.duration))},set:{playback.seek($0)}),in:0...max(1,playback.duration)).tint(.peach).papiAccessibilityLabel("Playback position").disabled(playback.duration<=0)
                HStack(spacing:12) {
                    PapiTextButton(playback.playing ? "Pause":"Play"){playback.toggle()}.font(CoffeeType.face(.subheadline,weight:.bold)).frame(minWidth:52,minHeight:44)
                    PapiText(time(playback.position)).font(CoffeeType.face(.caption)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                }
            }.padding(.horizontal,14).background(Color.coffee).foregroundStyle(.white)
        }.clipShape(RoundedRectangle(cornerRadius:18)).onAppear{playback.load(media)}.onDisappear{playback.pause()}
            .onChange(of:media){_,value in playback.load(value)}
            .onChange(of:scenePhase){_,phase in if phase != .active {playback.pause()}}
    }
    private func time(_ t:Double)->String {let value=Int(max(0,t));return String(format:"%d:%02d",value/60,value%60)}
}
private struct PlayerSurface:UIViewRepresentable {
    let player:AVPlayer
    func makeUIView(context:Context)->PlayerView {let view=PlayerView();view.playerLayer.player=player;view.playerLayer.videoGravity = .resizeAspect;return view}
    func updateUIView(_ view:PlayerView,context:Context) {view.playerLayer.player=player}
    static func dismantleUIView(_ view:PlayerView,coordinator:()) {view.playerLayer.player=nil}
    final class PlayerView:UIView {
        override static var layerClass:AnyClass {AVPlayerLayer.self}
        var playerLayer:AVPlayerLayer {layer as! AVPlayerLayer}
    }
}
