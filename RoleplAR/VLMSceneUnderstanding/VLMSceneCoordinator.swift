import Foundation
import SwiftUI
import RealityKit
import Combine
import AVFoundation

/// Main coordinator that integrates VLM scene understanding with RoleplAR
/// Connects VLMPipeline → ReactionSystem → NPCController → Dialogue
@MainActor
class VLMSceneCoordinator: ObservableObject {

    // MARK: - Published State

    @Published private(set) var isRunning = false
    @Published private(set) var currentSceneState: SceneState = .greeting
    @Published var debugInfo: DebugInfo = DebugInfo()

    // MARK: - Components

    let vlmPipeline: VLMPipeline
    let reactionSystem: ReactionSystem
    let npcController: NPCController

    /// FastVLM analyzer instance (for cache management)
    let fastVLMAnalyzer = FastVLMAnalyzer()

    // MARK: - Configuration

    /// Analyzer type to use
    enum AnalyzerType {
        case mock           // Heuristic-based (no actual VLM)
        case fastVLM        // On-device CoreML model (requires FastVLM.mlmodelc)
        case gpt4Vision     // OpenAI GPT-4V API (real VLM, requires API key)
    }

    /// Which analyzer to use (defaults to FastVLM for on-device inference)
    var analyzerType: AnalyzerType = .fastVLM

    /// Whether to use mock analyzer (true) or FastVLM (false) - legacy property
    var useMockAnalyzer: Bool {
        get { analyzerType == .mock }
        set { analyzerType = newValue ? .mock : .fastVLM }
    }

    /// Capture resolution
    var captureResolution: Int = 512

    // MARK: - Stats Update Timer

    private var statsUpdateTask: Task<Void, Never>?

    // MARK: - Speech

    private let speechSynthesizer = AVSpeechSynthesizer()
    private var lastSpokenAction: ActionType?
    private var lastSpokenObject: String?

    /// Enable/disable action speech feedback
    var speakActions: Bool = true

    // MARK: - Integration

    /// Reference to dialogue view model
    weak var dialogueViewModel: DialogueViewModel? {
        didSet {
            npcController.dialogueViewModel = dialogueViewModel
        }
    }

    /// Reference to narrative model
    weak var narrativeModel: NarrativeModel? {
        didSet {
            npcController.narrativeModel = narrativeModel
        }
    }

    // MARK: - Initialization

    init() {
        vlmPipeline = VLMPipeline(width: 512, height: 512)
        reactionSystem = ReactionSystem()
        npcController = NPCController()

        setupBindings()
    }

    private func setupBindings() {
        // VLM Pipeline → Reaction System
        vlmPipeline.onActionClassified = { [weak self] classification in
            self?.reactionSystem.process(classification)
            self?.updateDebugInfo(classification: classification)
            self?.speakAction(classification)
        }

        // Reaction System → NPC Controller
        reactionSystem.onNPCSpeak = { [weak self] japanese, english in
            self?.npcController.speak(japanese: japanese, englishHint: english)
        }

        reactionSystem.onSceneStateChange = { [weak self] state in
            self?.currentSceneState = state
        }

        reactionSystem.onLearningMoment = { [weak self] moment in
            self?.handleLearningMoment(moment)
        }
    }

    // MARK: - Lifecycle

    /// Start the VLM scene understanding system
    func start() async throws {
        vlmLog("VLMSceneCoordinator.start() called, isRunning=\(isRunning)", category: "Coordinator")

        guard !isRunning else {
            vlmLog("Already running, returning early", category: "Coordinator")
            return
        }

        vlmLog("analyzerType=\(analyzerType)", category: "Coordinator")

        switch analyzerType {
        case .mock:
            vlmLog("Starting with MockAnalyzer...", category: "Coordinator")
            try await vlmPipeline.startWithMockAnalyzer()
            debugInfo.analyzerName = "Mock (heuristics)"
            vlmLog("MockAnalyzer started", category: "Coordinator")

        case .fastVLM:
            vlmLog("Starting with FastVLM...", category: "Coordinator")
            try await fastVLMAnalyzer.loadModelFromBundle()
            try await vlmPipeline.start(analyzer: fastVLMAnalyzer)
            debugInfo.analyzerName = "FastVLM (on-device)"
            vlmLog("FastVLM started", category: "Coordinator")

        case .gpt4Vision:
            vlmLog("Starting with GPT-4V...", category: "Coordinator")
            let analyzer = GPT4VisionAnalyzer()
            analyzer.minAnalysisInterval = 2.0  // Rate limit to avoid excessive API calls
            try await vlmPipeline.start(analyzer: analyzer)
            debugInfo.analyzerName = "GPT-4V (API)"
            vlmLog("GPT-4V started", category: "Coordinator")
        }

        isRunning = true
        vlmLog("isRunning set to true", category: "Coordinator")

        // Start periodic stats update
        startStatsUpdateTimer()

        // Trigger initial greeting
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.reactionSystem.triggerGreeting()
        }

        vlmLog("VLM Scene Coordinator started successfully", category: "Coordinator")
    }

    /// Stop the system
    func stop() {
        statsUpdateTask?.cancel()
        statsUpdateTask = nil

        vlmPipeline.stop()
        reactionSystem.reset()
        npcController.reset()
        isRunning = false

        // Reset debug info for clean restart
        debugInfo = DebugInfo()
        currentSceneState = .greeting

        print("VLM Scene Coordinator stopped")
    }

    /// Start timer to periodically update stats for UI
    private func startStatsUpdateTimer() {
        statsUpdateTask = Task {
            while !Task.isCancelled && isRunning {
                updateStatsOnly()
                try? await Task.sleep(nanoseconds: 500_000_000) // Update every 0.5 seconds
            }
        }
    }

    /// Update stats without requiring an action classification
    private func updateStatsOnly() {
        debugInfo.fps = vlmPipeline.captureStats.fps
        debugInfo.totalFrames = vlmPipeline.captureStats.totalFrames
        debugInfo.analyzedFrames = vlmPipeline.captureStats.analyzedFrames
        debugInfo.rendererActive = vlmPipeline.isRunning
        debugInfo.hasValidFrames = debugInfo.totalFrames > 0

        // Hand tracking status
        debugInfo.leftHandTracked = !vlmPipeline.leftHandJoints.isEmpty
        debugInfo.rightHandTracked = !vlmPipeline.rightHandJoints.isEmpty
        debugInfo.handsTracked = debugInfo.leftHandTracked || debugInfo.rightHandTracked

        // Update analyzer-specific info
        if let gpt4v = vlmPipeline.analyzer as? GPT4VisionAnalyzer {
            debugInfo.vlmIsAnalyzing = gpt4v.isAnalyzing
            debugInfo.vlmLastResponse = gpt4v.lastRawResponse
            debugInfo.lastError = gpt4v.lastError
        } else if let fastVLM = vlmPipeline.analyzer as? FastVLMAnalyzer {
            debugInfo.vlmIsAnalyzing = fastVLM.isAnalyzing
            debugInfo.vlmLastResponse = fastVLM.lastRawResponse
            debugInfo.lastError = fastVLM.lastError
            debugInfo.fastVLMModelLoaded = fastVLM.isModelLoaded
        }
    }

    // MARK: - Scene Setup

    /// Set up the restaurant demo scene
    func setupRestaurantScene() async throws {
        // Configure scene objects
        vlmPipeline.setSceneObjects(["menu", "table", "teacup"])
        reactionSystem.sceneContext = .restaurant

        // Load 3D models if usdz_project is available
        let isServiceAvailable = await USDZLoader.shared.checkServiceAvailability()

        if isServiceAvailable {
            try await vlmPipeline.addSceneObject(
                prompt: "wooden Japanese restaurant table",
                position: [0, 0.75, -0.7],
                scale: [0.5, 0.5, 0.5]
            )

            try await vlmPipeline.addSceneObject(
                prompt: "Japanese restaurant menu booklet",
                position: [0, 0.85, -0.7],
                scale: [0.3, 0.3, 0.3]
            )

            vlmLog("Loaded USDZ scene objects", category: "Scene")
        } else {
            vlmLog("USDZ not available, adding placeholder geometry", category: "Scene")
            addPlaceholderSceneObjects()
        }
    }

    /// Add simple placeholder geometry when USDZ is not available
    private func addPlaceholderSceneObjects() {
        // Positions matching DeviceSceneManager
        let tableY: Float = 0.55
        let tableZ: Float = -0.85

        // Table - brown box
        var tableMaterial = UnlitMaterial()
        tableMaterial.color = .init(tint: .brown)
        let table = ModelEntity(
            mesh: .generateBox(width: 0.7, height: 0.04, depth: 0.5),
            materials: [tableMaterial]
        )
        table.position = [0, tableY, tableZ]
        table.name = "table"
        vlmPipeline.addSceneObject(table, name: "table")

        // Menu - red box
        var menuMaterial = UnlitMaterial()
        menuMaterial.color = .init(tint: .red)
        let menu = ModelEntity(
            mesh: .generateBox(width: 0.18, height: 0.015, depth: 0.25),
            materials: [menuMaterial]
        )
        menu.position = [0, tableY + 0.05, tableZ]
        menu.name = "menu"
        vlmPipeline.addSceneObject(menu, name: "menu")

        // Teacup - cyan cylinder
        var teacupMaterial = UnlitMaterial()
        teacupMaterial.color = .init(tint: .cyan)
        let teacup = ModelEntity(
            mesh: .generateCylinder(height: 0.07, radius: 0.035),
            materials: [teacupMaterial]
        )
        teacup.position = [0.2, tableY + 0.04, tableZ]
        teacup.name = "teacup"
        vlmPipeline.addSceneObject(teacup, name: "teacup")

        vlmLog("Added placeholder scene objects at z=\(tableZ)", category: "Scene")
    }

    /// Set up a custom scene
    func setupScene(objects: [String], context: SceneContext) {
        vlmPipeline.setSceneObjects(objects)
        reactionSystem.sceneContext = context
    }

    // MARK: - Manual Triggers

    /// Manually trigger a greeting (for testing)
    func triggerGreeting() {
        reactionSystem.triggerGreeting()
    }

    /// Manually trigger farewell
    func triggerFarewell() {
        reactionSystem.triggerFarewell()
    }

    // MARK: - Learning Moments

    private func handleLearningMoment(_ moment: LearningMoment) {
        // Could log to analytics, show in UI, etc.
        debugInfo.lastLearningMoment = moment.note
        print("Learning moment: \(moment.note)")
    }

    // MARK: - Debug

    private func updateDebugInfo(classification: ActionClassification) {
        debugInfo.lastAction = classification.action.displayName
        debugInfo.lastObject = classification.object ?? "-"
        debugInfo.confidence = classification.confidence
        debugInfo.fps = vlmPipeline.captureStats.fps
        debugInfo.totalFrames = vlmPipeline.captureStats.totalFrames
        debugInfo.analyzedFrames = vlmPipeline.captureStats.analyzedFrames
        debugInfo.rendererActive = vlmPipeline.isRunning
        debugInfo.hasValidFrames = debugInfo.totalFrames > 0

        // Store the scene summary from the classification
        debugInfo.sceneSummary = classification.sceneSummary

        // Update analyzer-specific info
        if let gpt4v = vlmPipeline.analyzer as? GPT4VisionAnalyzer {
            debugInfo.vlmIsAnalyzing = gpt4v.isAnalyzing
            debugInfo.vlmLastResponse = gpt4v.lastRawResponse
            debugInfo.lastError = gpt4v.lastError
            debugInfo.apiCallCount = debugInfo.analyzedFrames // Each analyzed frame = 1 API call
        } else if let fastVLM = vlmPipeline.analyzer as? FastVLMAnalyzer {
            debugInfo.vlmIsAnalyzing = fastVLM.isAnalyzing
            debugInfo.vlmLastResponse = fastVLM.lastRawResponse
            debugInfo.lastError = fastVLM.lastError
            debugInfo.fastVLMModelLoaded = fastVLM.isModelLoaded
        }
    }

    /// Save current frame to Photos for debugging
    func saveDebugFrame() async throws {
        try await vlmPipeline.saveCurrentFrame()
    }

    // MARK: - Speech Feedback

    /// Speak the current action if it's different from the last spoken action
    private func speakAction(_ classification: ActionClassification) {
        guard speakActions else { return }

        // Only speak non-idle actions with reasonable confidence
        guard classification.action != .idle,
              classification.action != .unknown,
              classification.confidence > 0.6 else {
            return
        }

        // Don't repeat the same action/object combination
        if classification.action == lastSpokenAction &&
           classification.object == lastSpokenObject {
            return
        }

        lastSpokenAction = classification.action
        lastSpokenObject = classification.object

        // Build the speech text
        let text = buildSpeechText(for: classification)

        // Speak it
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.1  // Slightly faster
        utterance.pitchMultiplier = 1.0
        utterance.volume = 0.8

        // Stop any current speech
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }

        speechSynthesizer.speak(utterance)
        vlmLog("Speaking: \(text)", category: "Speech")
    }

    /// Build natural speech text for an action
    private func buildSpeechText(for classification: ActionClassification) -> String {
        let action = classification.action
        let object = classification.object

        switch action {
        case .reaching:
            if let obj = object {
                return "Reaching for \(obj)"
            }
            return "Reaching"

        case .pickingUp:
            if let obj = object {
                return "Picking up \(obj)"
            }
            return "Picking up"

        case .holding:
            if let obj = object {
                return "Holding \(obj)"
            }
            return "Holding"

        case .placing:
            if let obj = object {
                return "Placing \(obj)"
            }
            return "Placing"

        case .pointing:
            if let obj = object {
                return "Pointing at \(obj)"
            }
            return "Pointing"

        case .waving:
            return "Waving"

        case .gesturing:
            return "Gesturing"

        case .idle, .unknown:
            return ""
        }
    }
}

// MARK: - Debug Info

struct DebugInfo {
    var lastAction: String = "-"
    var lastObject: String = "-"
    var confidence: Float = 0
    var fps: Double = 0
    var totalFrames: Int = 0
    var analyzedFrames: Int = 0
    var lastLearningMoment: String?
    var analyzerName: String = "-"

    // Renderer status
    var rendererActive: Bool = false
    var hasValidFrames: Bool = false

    // Hand tracking
    var handsTracked: Bool = false
    var leftHandTracked: Bool = false
    var rightHandTracked: Bool = false

    // VLM analyzer status (shared by GPT-4V and FastVLM)
    var apiCallCount: Int = 0
    var vlmLastResponse: String?
    var vlmIsAnalyzing: Bool = false
    var lastError: String?

    // FastVLM specific
    var fastVLMModelLoaded: Bool = false

    // Scene summary - natural language description of what the VLM sees
    var sceneSummary: String?
}

// MARK: - SwiftUI Integration

/// Debug overlay view showing VLM status
struct VLMDebugOverlay: View {
    @ObservedObject var coordinator: VLMSceneCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header with status indicator
            HStack {
                Text("VLM Debug")
                    .font(.headline)
                Spacer()
                // Pulsing indicator when VLM is analyzing
                if coordinator.debugInfo.vlmIsAnalyzing {
                    Circle()
                        .fill(.cyan)
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle()
                                .stroke(.cyan, lineWidth: 2)
                                .scaleEffect(1.5)
                                .opacity(0.5)
                        )
                }
                // Model loaded indicator for FastVLM
                if coordinator.analyzerType == .fastVLM {
                    Circle()
                        .fill(coordinator.debugInfo.fastVLMModelLoaded ? .green : .orange)
                        .frame(width: 6, height: 6)
                }
            }

            // Scene Summary - prominent display at the top
            if let summary = coordinator.debugInfo.sceneSummary, !summary.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("WHAT I SEE")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(summary)
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.blue.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Divider()

            // Analyzer section
            Text("ANALYZER").font(.caption2).foregroundStyle(.secondary)
            debugRow("Type", coordinator.debugInfo.analyzerName,
                     status: coordinator.debugInfo.analyzerName.contains("GPT") ? .blue : .gray)
            debugRow("Status", coordinator.isRunning ? "Running" : "Stopped",
                     status: coordinator.isRunning ? .blue : .orange)

            Divider()

            // Renderer section
            Text("RENDERER").font(.caption2).foregroundStyle(.secondary)
            debugRow("Frames", "\(coordinator.debugInfo.totalFrames)",
                     status: coordinator.debugInfo.totalFrames > 0 ? .blue : .orange)
            debugRow("Analyzed", "\(coordinator.debugInfo.analyzedFrames)",
                     status: coordinator.debugInfo.analyzedFrames > 0 ? .blue : .orange)
            debugRow("FPS", String(format: "%.1f", coordinator.debugInfo.fps),
                     status: coordinator.debugInfo.fps > 1 ? .blue : .orange)

            // Hand tracking section
            HStack(spacing: 4) {
                Text("Hands:")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Circle()
                    .fill(coordinator.debugInfo.leftHandTracked ? .blue : .gray)
                    .frame(width: 8, height: 8)
                Text("L")
                    .font(.caption2)
                Circle()
                    .fill(coordinator.debugInfo.rightHandTracked ? .blue : .gray)
                    .frame(width: 8, height: 8)
                Text("R")
                    .font(.caption2)
                Spacer()
            }

            Divider()

            // Detection section
            Text("DETECTION").font(.caption2).foregroundStyle(.secondary)
            debugRow("Action", coordinator.debugInfo.lastAction,
                     status: coordinator.debugInfo.lastAction != "-" ? .cyan : .gray)
            debugRow("Object", coordinator.debugInfo.lastObject, status: .purple)
            debugRow("Confidence", String(format: "%.0f%%", coordinator.debugInfo.confidence * 100),
                     status: coordinator.debugInfo.confidence > 0.7 ? .blue : .orange)

            // VLM response (if available)
            if let response = coordinator.debugInfo.vlmLastResponse {
                Divider()
                let responseLabel = coordinator.analyzerType == .gpt4Vision ? "GPT-4V RESPONSE" : "FASTVLM RESPONSE"
                Text(responseLabel).font(.caption2).foregroundStyle(.secondary)
                Text(response)
                    .font(.caption2)
                    .lineLimit(3)
                    .foregroundStyle(.blue)
            }

            // Error display
            if let error = coordinator.debugInfo.lastError {
                Divider()
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func debugRow(_ label: String, _ value: String, status: Color = .primary) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Circle()
                .fill(status)
                .frame(width: 6, height: 6)
            Text(value)
                .lineLimit(2)
                .fontWeight(.medium)
        }
        .font(.caption)
    }
}
