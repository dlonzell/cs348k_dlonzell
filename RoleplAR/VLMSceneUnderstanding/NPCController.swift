import Foundation
import AVFoundation
import Combine

/// Controls NPC behavior in response to VLM scene understanding
/// Integrates with RoleplAR's dialogue and audio systems
@MainActor
class NPCController: ObservableObject {

    // MARK: - Published State

    @Published private(set) var currentState: NPCState = .idle
    @Published private(set) var lastUtterance: NPCUtterance?
    @Published private(set) var conversationHistory: [NPCUtterance] = []
    @Published var npcName: String = "店員"  // Default: "Clerk"
    @Published var npcRole: String = "waiter"

    // MARK: - Audio

    private var speechSynthesizer: AVSpeechSynthesizer?
    private var audioPlayer: AVAudioPlayer?

    /// Whether to use text-to-speech for NPC responses
    var useTTS: Bool = true

    /// Japanese voice for TTS
    var japaneseVoice: AVSpeechSynthesisVoice? = AVSpeechSynthesisVoice(language: "ja-JP")

    // MARK: - Integration

    /// Reference to the dialogue view model for adding messages
    weak var dialogueViewModel: DialogueViewModel?

    /// Reference to narrative model for scene context
    weak var narrativeModel: NarrativeModel?

    // MARK: - Callbacks

    /// Called when NPC starts speaking
    var onStartSpeaking: (() -> Void)?

    /// Called when NPC finishes speaking
    var onFinishSpeaking: (() -> Void)?

    /// Called when conversation state changes
    var onStateChange: ((NPCState) -> Void)?

    // MARK: - Initialization

    init() {
        setupAudio()
    }

    private func setupAudio() {
        speechSynthesizer = AVSpeechSynthesizer()

        // Configure audio session for playback
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }

    // MARK: - Speaking

    /// Make the NPC speak Japanese text
    func speak(japanese: String, englishHint: String? = nil) {
        let utterance = NPCUtterance(
            japanese: japanese,
            english: englishHint,
            timestamp: Date(),
            npcName: npcName
        )

        lastUtterance = utterance
        conversationHistory.append(utterance)

        // Add to dialogue view
        addToDialogue(utterance)

        // Speak with TTS if enabled
        if useTTS {
            speakWithTTS(japanese)
        }

        // Update state
        setState(.speaking)
    }

    /// Speak using AVSpeechSynthesizer
    private func speakWithTTS(_ text: String) {
        guard let synthesizer = speechSynthesizer else { return }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = japaneseVoice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9 // Slightly slower for learners
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        onStartSpeaking?()

        synthesizer.speak(utterance)

        // Note: In a full implementation, we'd use AVSpeechSynthesizerDelegate
        // to know when speaking finishes
        let duration = estimateSpeechDuration(text)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self = self else { return }
            self.onFinishSpeaking?()
            self.setState(.waitingForResponse)
        }
    }

    /// Estimate speech duration based on text length
    private func estimateSpeechDuration(_ text: String) -> TimeInterval {
        // Rough estimate: Japanese speech is about 5-7 characters per second
        let charactersPerSecond: Double = 6.0
        let baseDuration = Double(text.count) / charactersPerSecond
        return max(baseDuration, 1.0) // Minimum 1 second
    }

    // MARK: - Dialogue Integration

    private func addToDialogue(_ utterance: NPCUtterance) {
        guard let viewModel = dialogueViewModel else { return }

        // Create message for dialogue view
        // Using assistant role for NPC messages
        let content: String
        if let english = utterance.english {
            content = "\(utterance.japanese)\n(\(english))"
        } else {
            content = utterance.japanese
        }

        viewModel.sendMessage(role: .assistant, content: content)
    }

    // MARK: - State Management

    private func setState(_ newState: NPCState) {
        guard currentState != newState else { return }
        currentState = newState
        onStateChange?(newState)
    }

    /// Handle user speech/action and respond appropriately
    func handleUserAction(_ action: ActionType, object: String? = nil) {
        switch action {
        case .waving:
            setState(.approachingUser)

        case .pickingUp where object == "menu":
            setState(.waitingForOrder)

        case .placing where object == "menu":
            setState(.takingOrder)

        default:
            break
        }
    }

    // MARK: - Scripted Responses

    /// Restaurant scenario responses
    func respondToMenuPickup() {
        speak(
            japanese: "ごゆっくりどうぞ。お決まりになりましたらお声がけください。",
            englishHint: "Please take your time. Let me know when you're ready."
        )
    }

    func respondToMenuPlacement() {
        speak(
            japanese: "ご注文をお伺いします。",
            englishHint: "I'll take your order."
        )
        setState(.takingOrder)
    }

    func respondToWave() {
        speak(
            japanese: "はい、ただいま参ります。",
            englishHint: "Yes, I'll be right there."
        )
        setState(.approachingUser)
    }

    func greetUser() {
        speak(
            japanese: "いらっしゃいませ！ご来店ありがとうございます。",
            englishHint: "Welcome! Thank you for coming."
        )
        setState(.greeting)
    }

    func sayFarewell() {
        speak(
            japanese: "ありがとうございました。またのお越しをお待ちしております。",
            englishHint: "Thank you. We look forward to seeing you again."
        )
        setState(.farewell)
    }

    // MARK: - Reset

    func reset() {
        currentState = .idle
        lastUtterance = nil
        conversationHistory.removeAll()
        speechSynthesizer?.stopSpeaking(at: .immediate)
    }
}

// MARK: - Supporting Types

enum NPCState: String {
    case idle
    case greeting
    case approachingUser
    case waitingForOrder
    case takingOrder
    case speaking
    case waitingForResponse
    case processing
    case farewell
}

struct NPCUtterance: Identifiable {
    let id = UUID()
    let japanese: String
    let english: String?
    let timestamp: Date
    let npcName: String
}

// Note: SenderRole is defined in OpenAIService.swift - do not duplicate here
