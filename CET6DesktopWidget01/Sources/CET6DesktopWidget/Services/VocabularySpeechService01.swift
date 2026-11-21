import AVFoundation
import Combine
import Foundation

enum VocabularySpeechAccent01: String, CaseIterable, Identifiable {
    case british
    case american

    var id: String { rawValue }

    var title: String {
        switch self {
        case .british: "英音"
        case .american: "美音"
        }
    }

    var languageCode: String {
        switch self {
        case .british: "en-GB"
        case .american: "en-US"
        }
    }

    var preferredVoiceName: String {
        switch self {
        case .british: "Daniel"
        case .american: "Samantha"
        }
    }
}

enum VocabularyAutoSpeechGate01 {
    static func shouldSpeak(wordID: String?, lastSpokenWordID: String?, isEnabled: Bool) -> Bool {
        guard isEnabled, let wordID, !wordID.isEmpty else { return false }
        return wordID != lastSpokenWordID
    }
}

@MainActor
final class VocabularySpeechService01: ObservableObject {
    static let minimumRate = 0.35
    static let maximumRate = 0.58
    static let defaultRate = 0.46

    @Published var isAutoPlayEnabled: Bool {
        didSet { defaults.set(isAutoPlayEnabled, forKey: Keys.autoPlay) }
    }

    @Published var accent: VocabularySpeechAccent01 {
        didSet { defaults.set(accent.rawValue, forKey: Keys.accent) }
    }

    @Published var rate: Double {
        didSet {
            let normalized = Self.normalizedRate(rate)
            if normalized != rate {
                rate = normalized
                return
            }
            defaults.set(rate, forKey: Keys.rate)
        }
    }

    private enum Keys {
        static let autoPlay = "Goals.flashcards.speech.autoPlay"
        static let accent = "Goals.flashcards.speech.accent"
        static let rate = "Goals.flashcards.speech.rate"
    }

    private let synthesizer = AVSpeechSynthesizer()
    private let defaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        defaults = userDefaults
        if userDefaults.object(forKey: Keys.autoPlay) == nil {
            isAutoPlayEnabled = true
        } else {
            isAutoPlayEnabled = userDefaults.bool(forKey: Keys.autoPlay)
        }
        accent = VocabularySpeechAccent01(
            rawValue: userDefaults.string(forKey: Keys.accent) ?? ""
        ) ?? .british
        if userDefaults.object(forKey: Keys.rate) == nil {
            rate = Self.defaultRate
        } else {
            rate = Self.normalizedRate(userDefaults.double(forKey: Keys.rate))
        }
    }

    func speak(_ rawWord: String) {
        let word = rawWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }

        stop()
        let utterance = AVSpeechUtterance(string: word)
        let preferredVoice = AVSpeechSynthesisVoice.speechVoices().first {
            $0.language == accent.languageCode && $0.name == accent.preferredVoiceName
        }
        utterance.voice = preferredVoice ?? AVSpeechSynthesisVoice(language: accent.languageCode)
        utterance.rate = Float(Self.normalizedRate(rate))
        utterance.pitchMultiplier = 1
        utterance.preUtteranceDelay = 0.04
        synthesizer.speak(utterance)
    }

    func stop() {
        guard synthesizer.isSpeaking || synthesizer.isPaused else { return }
        synthesizer.stopSpeaking(at: .immediate)
    }

    static func normalizedRate(_ rate: Double) -> Double {
        min(max(rate, minimumRate), maximumRate)
    }
}
