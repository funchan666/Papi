import Foundation
import AVFoundation

/// A late dismissal from an old player must never deactivate a newer recording.
@MainActor enum AudioFocus {
    static let changed = Notification.Name("PapiAudioSessionOwnerChanged")
    private(set) static var owner:UUID?
    static func acquire(_ id:UUID,recording:Bool=false) throws {
        let session=AVAudioSession.sharedInstance()
        try session.setCategory(recording ? .playAndRecord:.playback,mode:.default,options:recording ? [.defaultToSpeaker]:[])
        try session.setActive(true)
        owner=id
        NotificationCenter.default.post(name:changed,object:id)
    }
    static func release(_ id:UUID) {
        guard owner==id else{return}
        owner=nil
        try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)
    }
}
