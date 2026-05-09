import Foundation
import Combine

/// Maps VLM action classifications to NPC responses and app reactions
/// Designed for Japanese language learning scenarios
@MainActor
class ReactionSystem: ObservableObject {

    // MARK: - Published State

    @Published private(set) var lastReaction: Reaction?
    @Published private(set) var reactionHistory: [Reaction] = []
    @Published var isEnabled = true

    // MARK: - Configuration

    /// Minimum time between reactions to the same action (seconds)
    var reactionCooldown: TimeInterval = 3.0

    /// Minimum confidence required to trigger a reaction
    var confidenceThreshold: Float = 0.6

    /// Current scene context (affects which reactions are available)
    var sceneContext: SceneContext = .restaurant

    // MARK: - State

    private var lastReactionTimes: [ActionType: Date] = [:]
    private var currentHeldObject: String?

    // MARK: - Callbacks

    /// Called when NPC should speak
    var onNPCSpeak: ((String, String?) -> Void)?  // (Japanese text, optional English hint)

    /// Called when a learning moment occurs
    var onLearningMoment: ((LearningMoment) -> Void)?

    /// Called when scene state changes
    var onSceneStateChange: ((SceneState) -> Void)?

    // MARK: - Reaction Processing

    /// Process an action classification and generate appropriate reaction
    func process(_ classification: ActionClassification) {
        guard isEnabled else { return }
        guard classification.confidence >= confidenceThreshold else { return }

        // Check cooldown
        if let lastTime = lastReactionTimes[classification.action],
           Date().timeIntervalSince(lastTime) < reactionCooldown {
            return
        }

        // Generate reaction based on action
        let reaction = generateReaction(for: classification)

        guard let reaction = reaction else { return }

        // Record reaction
        lastReaction = reaction
        reactionHistory.append(reaction)
        lastReactionTimes[classification.action] = Date()

        // Execute reaction
        executeReaction(reaction)
    }

    // MARK: - Reaction Generation

    private func generateReaction(for classification: ActionClassification) -> Reaction? {
        switch classification.action {
        case .pickingUp:
            return handlePickUp(object: classification.object)

        case .holding:
            return handleHolding(object: classification.object)

        case .placing:
            return handlePlacing(object: classification.object, target: classification.target)

        case .reaching:
            return handleReaching(object: classification.object)

        case .pointing:
            return handlePointing(target: classification.target)

        case .waving:
            return handleWaving()

        case .idle:
            return handleIdle()

        case .gesturing, .unknown:
            return nil
        }
    }

    // MARK: - Action Handlers

    private func handlePickUp(object: String?) -> Reaction? {
        guard let object = object else { return nil }

        currentHeldObject = object

        switch object.lowercased() {
        case "menu":
            return Reaction(
                type: .npcResponse,
                japaneseText: "ごゆっくりどうぞ。",
                englishHint: "Please take your time.",
                learningNote: "ごゆっくり (go-yukkuri) = please take your time; どうぞ (douzo) = please/go ahead",
                sceneStateChange: .userViewingMenu
            )

        case "teacup", "cup":
            return Reaction(
                type: .npcResponse,
                japaneseText: "お茶をどうぞ。おかわりはいかがですか？",
                englishHint: "Please have some tea. Would you like a refill?",
                learningNote: "おかわり (okawari) = refill/seconds",
                sceneStateChange: nil
            )

        default:
            return nil
        }
    }

    private func handleHolding(object: String?) -> Reaction? {
        guard let object = object else { return nil }

        // Only react to holding if it's been a while (user studying menu)
        switch object.lowercased() {
        case "menu":
            // This would be called periodically while holding
            // Could trigger hints about menu items
            return Reaction(
                type: .learningHint,
                japaneseText: "何かお決まりですか？",
                englishHint: "Have you decided on something?",
                learningNote: "お決まり (o-kimari) = decided/chosen",
                sceneStateChange: nil
            )

        default:
            return nil
        }
    }

    private func handlePlacing(object: String?, target: String?) -> Reaction? {
        guard let object = object else { return nil }

        currentHeldObject = nil

        switch object.lowercased() {
        case "menu":
            return Reaction(
                type: .npcResponse,
                japaneseText: "ご注文はお決まりですか？",
                englishHint: "Are you ready to order?",
                learningNote: "ご注文 (go-chuumon) = order; お決まり (o-kimari) = decided",
                sceneStateChange: .readyToOrder
            )

        case "chopsticks":
            return Reaction(
                type: .npcResponse,
                japaneseText: "お食事はいかがでしたか？",
                englishHint: "How was your meal?",
                learningNote: "お食事 (o-shokuji) = meal; いかが (ikaga) = how",
                sceneStateChange: .finishedEating
            )

        default:
            return nil
        }
    }

    private func handleReaching(object: String?) -> Reaction? {
        guard let object = object else { return nil }

        switch object.lowercased() {
        case "menu":
            return Reaction(
                type: .npcResponse,
                japaneseText: "メニューをどうぞ。",
                englishHint: "Here's the menu.",
                learningNote: "どうぞ (douzo) = here you go / please",
                sceneStateChange: nil
            )

        default:
            return nil
        }
    }

    private func handlePointing(target: String?) -> Reaction? {
        return Reaction(
            type: .npcResponse,
            japaneseText: "はい、こちらですね。",
            englishHint: "Yes, this one here.",
            learningNote: "こちら (kochira) = this one (polite)",
            sceneStateChange: nil
        )
    }

    private func handleWaving() -> Reaction? {
        return Reaction(
            type: .npcResponse,
            japaneseText: "はい、少々お待ちください。",
            englishHint: "Yes, please wait a moment.",
            learningNote: "少々 (shoushou) = a little/moment; お待ちください (o-machi kudasai) = please wait",
            sceneStateChange: .callingWaiter
        )
    }

    private func handleIdle() -> Reaction? {
        // Only react to idle after certain states
        return nil
    }

    // MARK: - Reaction Execution

    private func executeReaction(_ reaction: Reaction) {
        // Trigger NPC speech
        if reaction.type == .npcResponse || reaction.type == .learningHint {
            onNPCSpeak?(reaction.japaneseText, reaction.englishHint)
        }

        // Trigger learning moment if there's a note
        if let note = reaction.learningNote {
            let moment = LearningMoment(
                timestamp: Date(),
                context: reaction.japaneseText,
                note: note,
                triggerAction: lastReaction?.type.rawValue ?? "unknown"
            )
            onLearningMoment?(moment)
        }

        // Update scene state
        if let stateChange = reaction.sceneStateChange {
            onSceneStateChange?(stateChange)
        }
    }

    // MARK: - Manual Triggers

    /// Trigger a greeting when user enters scene
    func triggerGreeting() {
        let reaction = Reaction(
            type: .npcResponse,
            japaneseText: "いらっしゃいませ！何名様ですか？",
            englishHint: "Welcome! How many people?",
            learningNote: "いらっしゃいませ (irasshaimase) = welcome (to a shop/restaurant); 何名様 (nan-mei-sama) = how many people (polite)",
            sceneStateChange: .greeting
        )

        lastReaction = reaction
        reactionHistory.append(reaction)
        executeReaction(reaction)
    }

    /// Trigger farewell when user leaves
    func triggerFarewell() {
        let reaction = Reaction(
            type: .npcResponse,
            japaneseText: "ありがとうございました。またお越しくださいませ。",
            englishHint: "Thank you very much. Please come again.",
            learningNote: "またお越しください (mata okoshi kudasai) = please come again",
            sceneStateChange: .farewell
        )

        lastReaction = reaction
        reactionHistory.append(reaction)
        executeReaction(reaction)
    }

    // MARK: - Reset

    func reset() {
        lastReaction = nil
        reactionHistory.removeAll()
        lastReactionTimes.removeAll()
        currentHeldObject = nil
    }
}

// MARK: - Supporting Types

struct Reaction {
    enum ReactionType: String {
        case npcResponse
        case learningHint
        case sceneTransition
        case audioFeedback
    }

    let type: ReactionType
    let japaneseText: String
    let englishHint: String?
    let learningNote: String?
    let sceneStateChange: SceneState?
    let timestamp: Date

    init(
        type: ReactionType,
        japaneseText: String,
        englishHint: String? = nil,
        learningNote: String? = nil,
        sceneStateChange: SceneState? = nil
    ) {
        self.type = type
        self.japaneseText = japaneseText
        self.englishHint = englishHint
        self.learningNote = learningNote
        self.sceneStateChange = sceneStateChange
        self.timestamp = Date()
    }
}

enum SceneContext: Equatable {
    case restaurant
    case shop
    case trainStation
    case hotel
    case custom(String)
}

enum SceneState: String {
    case greeting
    case userViewingMenu
    case readyToOrder
    case ordering
    case waitingForFood
    case eating
    case finishedEating
    case paying
    case farewell
    case callingWaiter
}

struct LearningMoment {
    let timestamp: Date
    let context: String      // The Japanese text that was said
    let note: String         // Explanation/vocabulary breakdown
    let triggerAction: String // What action triggered this
}
