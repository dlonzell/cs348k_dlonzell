import Foundation
import RealityKit
import ARKit
import Combine
import QuartzCore

/// Coordinates the scene capture pipeline for VLM analysis
/// Manages offscreen rendering, hand tracking updates, and frame delivery
@MainActor
class SceneCapture: ObservableObject {

    // MARK: - Published State

    @Published private(set) var isCapturing = false
    @Published private(set) var framesPerSecond: Double = 0
    @Published private(set) var lastCaptureTime: Date?
    @Published var lastCapturedFrame: SceneFrame?

    // MARK: - Configuration

    /// Target frames per second for capture
    var targetFPS: Double = 5.0

    /// Resolution for captured frames
    let captureWidth: Int
    let captureHeight: Int

    /// Objects known to be in the scene (for VLM context)
    var sceneObjectNames: [String] = ["menu", "table"]

    // MARK: - Components

    private var offscreenRenderer: OffscreenRenderer?
    private var handTrackingSystem: HandTrackingSystem?
    private var worldTrackingProvider: WorldTrackingProvider?
    private var arkitSession: ARKitSession?

    // MARK: - Capture Loop

    private var captureTask: Task<Void, Never>?
    private var frameCount: Int = 0
    private var fpsTimer: Date = Date()

    // MARK: - Callbacks

    /// Called when a new frame is captured
    var onFrameCaptured: ((SceneFrame) -> Void)?

    // MARK: - Initialization

    init(width: Int = 512, height: Int = 512) {
        self.captureWidth = width
        self.captureHeight = height
    }

    // MARK: - Lifecycle

    /// Start the capture pipeline
    func start() async throws {
        guard !isCapturing else {
            vlmLog("SceneCapture already running", category: "Capture")
            return
        }

        vlmLog("Starting SceneCapture...", category: "Capture")

        // Initialize offscreen renderer
        vlmLog("Creating OffscreenRenderer \(captureWidth)x\(captureHeight)...", category: "Capture")
        do {
            offscreenRenderer = try OffscreenRenderer(width: captureWidth, height: captureHeight)
            vlmLog("OffscreenRenderer created successfully", category: "Capture")
        } catch {
            vlmError("OffscreenRenderer creation FAILED: \(error)", category: "Capture")
            throw error
        }

        // Initialize hand tracking
        vlmLog("Starting HandTrackingSystem...", category: "Capture")
        handTrackingSystem = HandTrackingSystem()
        await handTrackingSystem?.start()

        // Initialize world tracking for head position
        vlmLog("Setting up world tracking...", category: "Capture")
        await setupWorldTracking()

        isCapturing = true
        frameCount = 0
        fpsTimer = Date()

        // Start capture loop
        vlmLog("Starting capture loop at \(targetFPS) FPS target", category: "Capture")
        captureTask = Task {
            await captureLoop()
        }

        vlmLog("SceneCapture STARTED successfully", category: "Capture")
    }

    /// Stop the capture pipeline
    func stop() {
        isCapturing = false
        captureTask?.cancel()
        captureTask = nil

        handTrackingSystem?.stop()
        handTrackingSystem = nil

        arkitSession?.stop()
        arkitSession = nil
        worldTrackingProvider = nil

        offscreenRenderer?.cleanup()
        offscreenRenderer = nil

        print("SceneCapture stopped")
    }

    // MARK: - World Tracking

    private func setupWorldTracking() async {
        // Check if world tracking is supported
        guard WorldTrackingProvider.isSupported else {
            print("World tracking is not supported on this device")
            return
        }

        let session = ARKitSession()
        let worldProvider = WorldTrackingProvider()

        arkitSession = session
        worldTrackingProvider = worldProvider

        do {
            try await session.run([worldProvider])
            print("World tracking started")
        } catch {
            print("Failed to start world tracking: \(error)")
            // Continue without world tracking - camera will use default position
            arkitSession = nil
            worldTrackingProvider = nil
        }
    }

    /// Get current head position from world tracking
    private func getCurrentHeadTransform() -> simd_float4x4? {
        guard let provider = worldTrackingProvider else { return nil }

        let deviceAnchor = provider.queryDeviceAnchor(atTimestamp: CACurrentMediaTime())
        return deviceAnchor?.originFromAnchorTransform
    }

    // MARK: - Scene Object Management

    /// Add a scene object entity to the offscreen renderer
    func addSceneObject(_ entity: Entity, name: String) {
        offscreenRenderer?.addSceneObject(entity)
        if !sceneObjectNames.contains(name) {
            sceneObjectNames.append(name)
        }
    }

    /// Add a USDZ model by loading from the service
    func addSceneObject(prompt: String, position: SIMD3<Float>, scale: SIMD3<Float> = [1, 1, 1]) async throws {
        let entity = try await USDZLoader.shared.loadModel(prompt: prompt)
        entity.position = position
        entity.scale = scale
        offscreenRenderer?.addSceneObject(entity)

        // Extract object name from prompt (simplified)
        let name = prompt.split(separator: " ").last.map(String.init) ?? prompt
        if !sceneObjectNames.contains(name) {
            sceneObjectNames.append(name)
        }
    }

    /// Clear all scene objects
    func clearSceneObjects() {
        offscreenRenderer?.clearSceneObjects()
        sceneObjectNames.removeAll()
    }

    /// Update the position of a scene object by name
    func updateSceneObjectPosition(name: String, position: SIMD3<Float>) {
        if offscreenRenderer != nil {
            offscreenRenderer?.updateSceneObjectPosition(name: name, position: position)
        } else {
            vlmLog("SceneCapture: offscreenRenderer is nil! Cannot update '\(name)'", category: "Sync")
        }
    }

    // MARK: - Capture Loop

    private func captureLoop() async {
        let frameDuration = 1.0 / targetFPS

        while isCapturing && !Task.isCancelled {
            let frameStart = Date()

            do {
                // Update camera with head position
                if let headTransform = getCurrentHeadTransform() {
                    offscreenRenderer?.updateCamera(transform: headTransform)
                }

                // Update hand meshes
                if let handSystem = handTrackingSystem {
                    offscreenRenderer?.updateHandMeshes(
                        leftJoints: handSystem.leftHandJoints,
                        rightJoints: handSystem.rightHandJoints
                    )
                }

                // Render and capture
                let pixelBuffer = try await offscreenRenderer?.renderToPixelBuffer()

                // Create frame (pixelBuffer may be nil on simulator)
                let frame = SceneFrame(
                    pixelBuffer: pixelBuffer,
                    sceneObjects: sceneObjectNames,
                    leftHandJoints: handTrackingSystem?.leftHandJoints ?? [:],
                    rightHandJoints: handTrackingSystem?.rightHandJoints ?? [:],
                    timestamp: Date()
                )

                lastCapturedFrame = frame
                lastCaptureTime = Date()
                onFrameCaptured?(frame)

                // Update FPS counter
                frameCount += 1
                let elapsed = Date().timeIntervalSince(fpsTimer)
                if elapsed >= 1.0 {
                    framesPerSecond = Double(frameCount) / elapsed
                    frameCount = 0
                    fpsTimer = Date()

                    #if targetEnvironment(simulator)
                    if pixelBuffer == nil && frameCount == 0 {
                        print("SceneCapture: Running on simulator - pixel buffer unavailable, use MockAnalyzer for testing")
                    }
                    #endif
                }

            } catch {
                print("Capture error: \(error)")
            }

            // Wait for next frame
            let elapsed = Date().timeIntervalSince(frameStart)
            let sleepTime = max(0, frameDuration - elapsed)
            if sleepTime > 0 {
                try? await Task.sleep(nanoseconds: UInt64(sleepTime * 1_000_000_000))
            }
        }
    }

    // MARK: - Manual Capture

    /// Capture a single frame (for testing/debugging)
    func captureFrame() async throws -> SceneFrame? {
        guard let renderer = offscreenRenderer else {
            throw SceneCaptureError.notInitialized
        }

        // Update hand meshes
        if let handSystem = handTrackingSystem {
            renderer.updateHandMeshes(
                leftJoints: handSystem.leftHandJoints,
                rightJoints: handSystem.rightHandJoints
            )
        }

        // Render
        let pixelBuffer = try await renderer.renderToPixelBuffer()

        return SceneFrame(
            pixelBuffer: pixelBuffer,
            sceneObjects: sceneObjectNames,
            leftHandJoints: handTrackingSystem?.leftHandJoints ?? [:],
            rightHandJoints: handTrackingSystem?.rightHandJoints ?? [:],
            timestamp: Date()
        )
    }

    /// Save the last captured frame to Photos (for debugging)
    func saveLastFrameToPhotos() async throws {
        vlmLog("saveLastFrameToPhotos called", category: "Save")

        guard let frame = lastCapturedFrame else {
            vlmError("No lastCapturedFrame available", category: "Save")
            throw SceneCaptureError.noFrameAvailable
        }

        vlmLog("Frame exists, timestamp: \(frame.timestamp)", category: "Save")

        guard let pixelBuffer = frame.pixelBuffer else {
            vlmError("Frame exists but pixelBuffer is nil", category: "Save")
            vlmError("This usually means offscreen rendering failed", category: "Save")
            throw SceneCaptureError.noFrameAvailable
        }

        vlmLog("PixelBuffer exists, calling saveToPhotos...", category: "Save")
        try await TextureConverter.saveToPhotos(pixelBuffer)
        vlmLog("Frame saved to Photos successfully", category: "Save")
    }
}

// MARK: - Errors

enum SceneCaptureError: LocalizedError {
    case notInitialized
    case noFrameAvailable
    case captureFailed

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Scene capture not initialized"
        case .noFrameAvailable:
            return "No frame available"
        case .captureFailed:
            return "Failed to capture frame"
        }
    }
}
