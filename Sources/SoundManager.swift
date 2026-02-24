import AppKit

final class SoundManager {
    static let shared = SoundManager()

    var soundFeedbackEnabled: Bool {
        ConfigManager.shared.config.soundFeedback
    }

    private init() {}

    func play(_ name: String) {
        guard soundFeedbackEnabled else { return }
        // NSSound looks in /System/Library/Sounds/ automatically
        if let sound = NSSound(named: NSSound.Name(name)) {
            sound.play()
        }
    }

    func playRecordStart() { play("Tink") }
    func playRecordStop() { play("Pop") }
    func playTranscribeComplete() { play("Glass") }
    func playCancel() { play("Funk") }
    func playError() { play("Basso") }
}
