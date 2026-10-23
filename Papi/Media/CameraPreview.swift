import SwiftUI
import AVFoundation
import UIKit

private final class CameraCaptureEngine:@unchecked Sendable {
    let session=AVCaptureSession()
    private let queue=DispatchQueue(label:"Papi.CameraPreview")
    private var configured=false
    func start() async throws {
        try await withCheckedThrowingContinuation {(continuation:CheckedContinuation<Void,Error>) in
            queue.async {
                do {
                    if !self.configured {
                        self.session.beginConfiguration()
                        defer {self.session.commitConfiguration()}
                        self.session.sessionPreset = .high
                        guard let camera=AVCaptureDevice.default(.builtInWideAngleCamera,for:.video,position:.front) ?? AVCaptureDevice.default(for:.video) else {throw CaptureError.unavailable}
                        let input=try AVCaptureDeviceInput(device:camera)
                        guard self.session.canAddInput(input) else {throw CaptureError.unavailable}
                        self.session.addInput(input);self.configured=true
                    }
                    if !self.session.isRunning {self.session.startRunning()}
                    guard self.session.isRunning else {throw CaptureError.unavailable}
                    continuation.resume()
                } catch {continuation.resume(throwing:error)}
            }
        }
    }
    func stop(){queue.async {if self.session.isRunning {self.session.stopRunning()}}}
    enum CaptureError:Error {case unavailable}
}
@MainActor private final class CameraPreviewModel:ObservableObject {
    let engine=CameraCaptureEngine()
    @Published private(set) var status="Camera preview paused"
    @Published private(set) var running=false
    @Published private(set) var denied=false
    private var generation=UUID()
    func start(requestMicrophone:Bool) async {
        let token=UUID();generation=token;denied=false;running=false;status=requestMicrophone ? "Requesting camera and microphone access…":"Requesting camera access…"
        let video=await permission(.video)
        guard generation==token,!Task.isCancelled else{return}
        let audio=requestMicrophone ? await permission(.audio):true
        guard generation==token,!Task.isCancelled else{return}
        guard video && audio else {denied=true;status=requestMicrophone ? "Camera and microphone access are required. You can allow them in iOS Settings.":"Camera access is required. You can allow it in iOS Settings.";return}
        do {
            try await engine.start()
            guard generation==token,!Task.isCancelled else{return}
            running=true;status="Private camera preview · No call connected"
        } catch {status="Camera unavailable"}
    }
    func stop(){generation=UUID();engine.stop();running=false;status="Camera preview paused"}
    private func permission(_ type:AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for:type) {
        case .authorized:return true
        case .notDetermined:return await AVCaptureDevice.requestAccess(for:type)
        default:return false
        }
    }
}
struct CameraPreviewView:View {
    var requestMicrophone=false
    @StateObject private var model=CameraPreviewModel()
    @Environment(\.scenePhase) private var phase
    var body:some View {
        PapiScreen(background:"roomBackground") {
            VStack(spacing:18) {
                PapiHeader("My camera preview").background(Color.cream,in:RoundedRectangle(cornerRadius:16))
                ZStack {
                    Color.black
                    CameraSurface(session:model.engine.session)
                    if !model.running {PapiText(model.status).multilineTextAlignment(.center).padding(25).foregroundStyle(.white)}
                }.clipShape(RoundedRectangle(cornerRadius:22)).frame(maxHeight:.infinity)
                PapiText(model.status).font(CoffeeType.face(.headline)).multilineTextAlignment(.center)
                PapiText("Your camera is visible only to you. Video and microphone audio are not recorded or sent, and no call is connected.").font(CoffeeType.face(.caption)).multilineTextAlignment(.center)
                if model.denied {
                    PapiTextButton("Open iOS Settings") {if let url=URL(string:UIApplication.openSettingsURLString){UIApplication.shared.open(url)}}.buttonStyle(PapiButtonStyle(light:true))
                } else if !model.running {
                    PapiTextButton("Retry"){Task{await model.start(requestMicrophone:requestMicrophone)}}.buttonStyle(PapiButtonStyle(light:true))
                }
            }.padding(20).foregroundStyle(Color.cream)
        }.task(id:phase) {if phase == .active {await model.start(requestMicrophone:requestMicrophone)} else {model.stop()}}
            .onReceive(NotificationCenter.default.publisher(for:AVCaptureSession.runtimeErrorNotification,object:model.engine.session).receive(on:DispatchQueue.main)){_ in model.stop()}
            .onReceive(NotificationCenter.default.publisher(for:AVCaptureSession.wasInterruptedNotification,object:model.engine.session).receive(on:DispatchQueue.main)){_ in model.stop()}
            .onDisappear{model.stop()}
    }
}
private struct CameraSurface:UIViewRepresentable {
    let session:AVCaptureSession
    func makeUIView(context:Context)->PreviewView {let view=PreviewView();view.preview.session=session;view.preview.videoGravity = .resizeAspectFill;return view}
    func updateUIView(_ view:PreviewView,context:Context) {view.setNeedsLayout()}
    static func dismantleUIView(_ view:PreviewView,coordinator:()) {view.preview.session=nil}
    final class PreviewView:UIView {
        override class var layerClass:AnyClass {AVCaptureVideoPreviewLayer.self}
        var preview:AVCaptureVideoPreviewLayer {layer as! AVCaptureVideoPreviewLayer}
        override func layoutSubviews() {
            super.layoutSubviews()
            guard let connection=preview.connection,let orientation=window?.windowScene?.effectiveGeometry.interfaceOrientation else{return}
            let angle:CGFloat
            switch orientation {
            case .landscapeRight:angle=0
            case .landscapeLeft:angle=180
            case .portraitUpsideDown:angle=270
            default:angle=90
            }
            if connection.isVideoRotationAngleSupported(angle) {connection.videoRotationAngle=angle}
        }
    }
}
