import Foundation
import Combine
import RealityKit

/// Main coordinator for the VLM scene understanding pipeline
/// Connects scene capture with VLM analysis and delivers action classifications
@MainActor
class VLMPipeline: ObservableObject {

    // MARK: - Published State

    @Published private(set) var isRunning = false
    @Published private(set) var latestClassification: ActionClassification?
    @Published private(set) var captureStats: CaptureStats = CaptureStats()

    // MARK: - Components

    private var sceneCapture: SceneCapture?
    private(set) var analyzer: SceneAnalyzer?

    /// Access the mock analyzer for configuration (only available when using mock)
    var mockAnalyzer: MockAnalyzer? {
        return analyzer as? MockAnalyzer
    }

    /// Access latest hand joint data for visualization
    var leftHandJoints: [String: simd_float4x4] {
        sceneCapture?.lastCapturedFrame?.leftHandJoints ?? [:]
    }

    var rightHandJoints: [String: simd_float4x4] {
        sceneCapture?.lastCapturedFrame?.rightHandJoints ?? [:]
    }

    /// Check if hands are currently being tracked
    var isTrackingHands: Bool {
        !leftHandJoints.isEmpty || !rightHandJoints.isEmpty
    }

    // MARK: - Configuration

    /// Frames per second for capture (lower = less CPU, higher = more responsive)
    var captureFPS: Double = 5.0

    /// Only analyze every Nth frame (to reduce VLM load)
    var analyzeEveryNthFrame: Int = 1

    /// Capture resolution
    let captureWidth: Int
    let captureHeight: Int

    // MARK: - Analysis State

    private var framesSinceLastAnalysis = 0
    private var isAnalyzing = false

    // MARK: - Callbacks

    /// Called when a new action is classified
    var onActionClassified: ((ActionClassification) -> Void)?

    /// Called when specific actions occur (for triggering reactions)
    var onPickUp: ((String) -> Void)?
    var onPlace: ((String, String?) -> Void)?
    var onWave: (() -> Void)?

    // MARK: - Initialization

    init(width: Int = 512, height: Int = 512) {
        self.captureWidth = width
        self.captureHeight = height
    }

    // MARK: - Lifecycle

    /// Start the VLM pipeline with the mock analyzer
    func startWithMockAnalyzer() async throws {
        let mockAnalyzer = MockAnalyzer()
        mockAnalyzer.useHeuristicDetection = true
        try await start(analyzer: mockAnalyzer)
    }

    /// Start the VLM pipeline with a custom analyzer
    func start(analyzer: SceneAnalyzer) async throws {
        guard !isRunning else { return }

        self.analyzer = analyzer

        // Create and configure scene capture
        let capture = SceneCapture(width: captureWidth, height: captureHeight)
        capture.targetFPS = captureFPS
        sceneCapture = capture

        // Set up frame callback
        capture.onFrameCaptured = { [weak self] frame in
            Task { @MainActor in
                await self?.handleFrame(frame)
            }
        }

        // Start capture
        try await capture.start()

        isRunning = true
        print("VLM Pipeline started")
    }

    /// Stop the pipeline
    func stop() {
        isRunning = false
        sceneCapture?.stop()
        sceneCapture = nil
        analyzer = nil
        latestClassification = nil
        // Reset stats for clean restart
        captureStats = CaptureStats()
        framesSinceLastAnalysis = 0
        isAnalyzing = false
        print("VLM Pipeline stopped")
    }

    // MARK: - Scene Object Management

    /// Add a scene object to track
    func addSceneObject(_ entity: Entity, name: String) {
        sceneCapture?.addSceneObject(entity, name: name)
    }

    /// Add a scene object by generating it from a prompt
    func addSceneObject(prompt: String, position: SIMD3<Float>, scale: SIMD3<Float> = [1, 1, 1]) async throws {
        try await sceneCapture?.addSceneObject(prompt: prompt, position: position, scale: scale)
    }

    /// Set the list of object names in the scene
    func setSceneObjects(_ names: [String]) {
        sceneCapture?.sceneObjectNames = names
    }

    /// Update the position of a scene object by name (for syncing with immersive view)
    func updateSceneObjectPosition(name: String, position: SIMD3<Float>) {
        // Silently ignore if pipeline not running - objects can be dragged before system starts
        guard isRunning, let capture = sceneCapture else { return }
        capture.updateSceneObjectPosition(name: name, position: position)
    }

    // MARK: - Frame Handling

    private func handleFrame(_ frame: SceneFrame) async {
        // Update stats
        captureStats.totalFrames += 1
        captureStats.fps = sceneCapture?.framesPerSecond ?? 0

        // Check if we should analyze this frame
        framesSinceLastAnalysis += 1
        guard framesSinceLastAnalysis >= analyzeEveryNthFrame else { return }
        framesSinceLastAnalysis = 0

        // Don't start new analysis if one is in progress
        guard !isAnalyzing else { return }

        await analyzeFrame(frame)
    }

    private func analyzeFrame(_ frame: SceneFrame) async {
        guard let analyzer = analyzer else { return }

        isAnalyzing = true
        captureStats.analyzedFrames += 1

        do {
            let classification = try await analyzer.analyze(frame: frame)

            // Only update if confidence is above threshold
            if classification.confidence > 0.5 {
                // Check if this is a new/different action
                let isNewAction = latestClassification?.action != classification.action ||
                                  latestClassification?.object != classification.object

                latestClassification = classification

                if isNewAction {
                    handleClassification(classification)
                }
            }

        } catch {
            print("Analysis error: \(error)")
        }

        isAnalyzing = false
    }

    private func handleClassification(_ classification: ActionClassification) {
        onActionClassified?(classification)

        // Trigger specific action callbacks
        switch classification.action {
        case .pickingUp:
            if let object = classification.object {
                onPickUp?(object)
            }
        case .placing:
            if let object = classification.object {
                onPlace?(object, classification.target)
            }
        case .waving:
            onWave?()
        default:
            break
        }
    }

    // MARK: - Debugging

    /// Save the current frame to Photos for inspection
    func saveCurrentFrame() async throws {
        try await sceneCapture?.saveLastFrameToPhotos()
    }

    /// Get current capture statistics
    func getStats() -> CaptureStats {
        return captureStats
    }
}

// MARK: - Supporting Types

struct CaptureStats {
    var totalFrames: Int = 0
    var analyzedFrames: Int = 0
    var fps: Double = 0

    var analysisRatio: Double {
        guard totalFrames > 0 else { return 0 }
        return Double(analyzedFrames) / Double(totalFrames)
    }
}

// MARK: - Convenience Extensions

extension VLMPipeline {
    /// Quick setup for the restaurant demo scene
    func setupRestaurantDemo() async throws {
        // Add table
        try await addSceneObject(
            prompt: "simple wooden restaurant table",
            position: [0, 0.75, -1.5],
            scale: [0.5, 0.5, 0.5]
        )

        // Add menu
        try await addSceneObject(
            prompt: "Japanese restaurant menu booklet",
            position: [0, 0.85, -1.5],
            scale: [0.3, 0.3, 0.3]
        )

        setSceneObjects(["menu", "table"])
    }
}
