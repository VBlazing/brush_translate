import AVFoundation

final class SpeechSynthesizer {
    static let shared = SpeechSynthesizer()
    private let synthesizer = AVSpeechSynthesizer()

    private init() {}

    func speak(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }
}
