import SwiftUI
import AVFoundation
import UIKit

@MainActor final class CoffeeFilmPlayback:ObservableObject {
    let player=AVPlayer()
    @Published var playing=false
    @Published var position:Double=0
    @Published var duration:Double=0
    @Published var failure:String?
    private var loaded:String?
    private var observer:Any?
    private var statusObservation:NSKeyValueObservation?
    private var durationObservation:NSKeyValueObservation?
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
    func load(_ media:String,remoteURL:URL?=nil,force:Bool=false) {
        guard loaded != media || force else{return}
        pause()
        statusObservation=nil;durationObservation=nil
        if let finishObserver {NotificationCenter.default.removeObserver(finishObserver)}
        finishObserver=nil
        loaded=nil;position=0;duration=0
        player.replaceCurrentItem(with:nil)
        guard let url=remoteURL ?? CoffeeMedia.url(media) else {failure="This video is unavailable.";return}
        loaded=media;failure=nil
        let item=AVPlayerItem(url:url);player.replaceCurrentItem(with:item)
        durationObservation=item.observe(\.duration,options:[.initial,.new]) { [weak self] item,_ in
            Task {@MainActor in
                guard let self,self.player.currentItem === item else{return}
                let seconds=item.duration.seconds;self.duration=seconds.isFinite ? seconds:0
            }
        }
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
    var remoteURL:URL? = nil
    var onRetry:(()->Void)? = nil
    var autoplay=false
    var onAutoplay:(()->Void)? = nil
    @ScaledMetric(relativeTo:.body) private var seekWidth:CGFloat=120
    @StateObject private var playback=CoffeeFilmPlayback()
    @State private var didAutoplay=false
    @Environment(\.scenePhase) private var scenePhase
    var body:some View {
        VStack(spacing:0) {
            ZStack {
                Color.coffee
                if !media.hasPrefix("cloud/") {
                    PapiImage(name:media,fallback:"emptyCup").blur(radius:22).overlay(Color.coffee.opacity(0.55)).clipped().accessibilityHidden(true)
                }
                PlayerSurface(player:playback.player)
                if let failure=playback.failure {
                    ScrollView {VStack(spacing:14) {PapiText(failure);PapiTextButton("Retry"){if let onRetry {onRetry()} else {playback.load(media,remoteURL:remoteURL,force:true)}}.frame(minHeight:44)}
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
        }.clipShape(RoundedRectangle(cornerRadius:18)).onAppear{playback.load(media,remoteURL:remoteURL);startAutoplayIfNeeded()}.onDisappear{playback.pause()}
            .onChange(of:media){_,value in playback.load(value,remoteURL:remoteURL)}
            .onChange(of:remoteURL){_,value in playback.load(media,remoteURL:value,force:true)}
            .onChange(of:scenePhase){_,phase in if phase != .active {playback.pause()} else {startAutoplayIfNeeded()}}
    }
    private func startAutoplayIfNeeded() {
        guard autoplay,!didAutoplay,scenePhase == .active else{return}
        didAutoplay=true;onAutoplay?();playback.toggle()
    }
    private func time(_ t:Double)->String {let value=Int(max(0,t));return String(format:"%d:%02d",value/60,value%60)}
}
struct CloudMomentPoster:View {
    let media:String
    @EnvironmentObject private var store:CoffeeHouse
    @Environment(\.scenePhase) private var scenePhase
    @State private var image:UIImage?
    @State private var imageOwner:UUID?
    @State private var imageMedia:String?
    private var isVisible:Bool {store.isVisibleCloudVideo(media)}
    var body:some View {
        Group {
            if scenePhase == .active,store.state.signedIn,imageOwner==store.state.cloudAccountID,imageMedia==media,isVisible,let image {
                Image(uiImage:image).resizable().scaledToFill()
            } else {PapiImage(name:"emptyCup")}
        }.clipped()
        .task(id:"\(store.state.cloudAccountID?.uuidString ?? "none")|\(media)|\(scenePhase == .active)|\(store.state.signedIn)|\(isVisible)") {
            image=nil;imageOwner=nil;imageMedia=nil
            guard scenePhase == .active,store.state.signedIn,let account=store.state.cloudAccountID,
                  media.hasPrefix("cloud/"),isVisible else{return}
            let path=String(media.dropFirst(6))
            guard path.split(separator:"/").count==2,!path.contains("..") else{return}
            do {
                let url=try await CoffeeCloud.shared.mediaURL(path:path,account:account,expiresIn:120)
                guard !Task.isCancelled,url.scheme=="https",url.host=="cquoffowtjnxmgaxavym.supabase.co",
                      store.state.signedIn,store.state.cloudAccountID==account,isVisible else{return}
                let poster=await CoffeeMedia.privateVideoPoster(from:url)
                guard !Task.isCancelled,scenePhase == .active,store.state.signedIn,store.state.cloudAccountID==account,isVisible,let poster else{return}
                image=poster;imageOwner=account;imageMedia=media
            } catch {return}
        }
        .onDisappear {image=nil;imageOwner=nil;imageMedia=nil}
    }
}
struct CloudMomentVideo:View {
    let media:String
    var autoplay=false
    @EnvironmentObject private var store:CoffeeHouse
    @Environment(\.scenePhase) private var scenePhase
    @State private var signedURL:URL?
    @State private var owner:UUID?
    @State private var failed=false
    @State private var reload=0
    @State private var didAutoplay=false
    var body:some View {
        Group {
            if let signedURL,let owner,store.state.signedIn,store.state.cloudAccountID==owner,scenePhase == .active {
                CoffeePlayerView(media:media,remoteURL:signedURL,onRetry:{reload+=1},autoplay:autoplay && !didAutoplay,onAutoplay:{didAutoplay=true})
            } else {
                VStack(spacing:12) {
                    PapiText(failed ? "This video is unavailable.":"Loading video…")
                    if failed {PapiTextButton("Retry"){reload+=1}}
                }.frame(maxWidth:.infinity,maxHeight:.infinity).background(Color.coffee).foregroundStyle(.white)
            }
        }.task(id:"\(store.state.cloudAccountID?.uuidString ?? "none")|\(media)|\(scenePhase == .active)|\(reload)") {
            signedURL=nil;owner=nil;failed=false
            guard scenePhase == .active,store.state.signedIn,let account=store.state.cloudAccountID,
                  media.hasPrefix("cloud/"),store.isVisibleCloudVideo(media) else{return}
            do {
                let url=try await CoffeeCloud.shared.mediaURL(path:String(media.dropFirst(6)),account:account,expiresIn:300)
                guard !Task.isCancelled,store.state.signedIn,store.state.cloudAccountID==account,
                      store.isVisibleCloudVideo(media),
                      url.scheme=="https",url.host=="cquoffowtjnxmgaxavym.supabase.co" else{return}
                owner=account;signedURL=url
            } catch {if !Task.isCancelled {failed=true}}
        }
    }
}
private struct PlayerSurface:UIViewRepresentable {
    let player:AVPlayer
    func makeUIView(context:Context)->PlayerView {let view=PlayerView();view.isOpaque=false;view.backgroundColor = .clear;view.playerLayer.backgroundColor = UIColor.clear.cgColor;view.playerLayer.player=player;view.playerLayer.videoGravity = .resizeAspect;return view}
    func updateUIView(_ view:PlayerView,context:Context) {view.playerLayer.player=player}
    static func dismantleUIView(_ view:PlayerView,coordinator:()) {view.playerLayer.player=nil}
    final class PlayerView:UIView {
        override static var layerClass:AnyClass {AVPlayerLayer.self}
        var playerLayer:AVPlayerLayer {layer as! AVPlayerLayer}
    }
}
