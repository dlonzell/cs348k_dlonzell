import SwiftUI
import RealityKit
import ARKit

/// Test view specifically for Vision Pro Simulator testing without hand tracking
/// Objects can be dragged with mouse/trackpad - the VLM actually analyzes the scene
struct SimulatorVLMTestView: View {
    @StateObject private var coordinator = VLMSceneCoordinator()
    @State private var isStarted = false
    @State private var errorMessage: String?
    @State private var showDebug = true

    var body: some View {
        ZStack {
            VStack(spacing: 20) {
                headerView
                Divider()
                statusView
                Spacer()
                controlsView
                if let error = errorMessage {
                    errorView(error)
                }
            }
            .padding()

            if showDebug && isStarted {
                VStack {
                    HStack {
                        Spacer()
                        debugOverlay.frame(width: 220)
                    }
                    Spacer()
                }
                .padding()
            }
        }
        .onDisappear {
            coordinator.stop()
        }
    }

    private var headerView: some View {
        VStack(spacing: 8) {
            Text("Simulator VLM Test")
                .font(.title)
                .fontWeight(.bold)
            Text("VLM analyzes the scene in real-time")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Instructions
            VStack(alignment: .leading, spacing: 4) {
                Text("How to use:")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("1. Tap 'Start System' to begin")
                Text("2. Reach toward, pick up, or place the menu/teacup")
                Text("3. Watch for NPC responses below")
                Text("4. Check 'Analyzer' in debug to see which VLM is active")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(8)
            .background(.regularMaterial.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var statusView: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusRow("System", coordinator.isRunning ? "Running" : "Stopped",
                      color: coordinator.isRunning ? .green : .gray)
            statusRow("Scene State", coordinator.currentSceneState.rawValue.capitalized, color: .blue)

            if let lastAction = coordinator.vlmPipeline.latestClassification {
                Divider()
                statusRow("Last Action", lastAction.action.displayName, color: .orange)
                if let object = lastAction.object {
                    statusRow("Object", object, color: .purple)
                }
                statusRow("Confidence", String(format: "%.0f%%", lastAction.confidence * 100),
                          color: lastAction.confidence > 0.7 ? .green : .yellow)
            }

            if let reaction = coordinator.reactionSystem.lastReaction {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("NPC Response:").font(.caption).foregroundStyle(.secondary)
                    Text(reaction.japaneseText).font(.headline)
                    if let english = reaction.englishHint {
                        Text(english).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var controlsView: some View {
        VStack(spacing: 12) {
            Button {
                Task { await toggleSystem() }
            } label: {
                HStack {
                    Image(systemName: isStarted ? "stop.fill" : "play.fill")
                    Text(isStarted ? "Stop System" : "Start System")
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            .buttonStyle(.borderedProminent)
            .tint(isStarted ? .red : .green)

            HStack(spacing: 12) {
                Button("Greet") { coordinator.triggerGreeting() }
                    .buttonStyle(.bordered).disabled(!isStarted)
                Button("Farewell") { coordinator.triggerFarewell() }
                    .buttonStyle(.bordered).disabled(!isStarted)
                Button("Save Frame") {
                    Task { try? await coordinator.saveDebugFrame() }
                }
                .buttonStyle(.bordered).disabled(!isStarted)
                Toggle("Debug", isOn: $showDebug).toggleStyle(.button)
            }
        }
    }

    private var debugOverlay: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header with status indicator
            HStack {
                Text("VLM Debug").font(.headline)
                Spacer()
                if coordinator.debugInfo.vlmIsAnalyzing {
                    Circle().fill(.cyan).frame(width: 8, height: 8)
                }
            }

            Divider()

            // Analyzer
            Text("ANALYZER").font(.caption2).foregroundStyle(.secondary)
            debugRowWithStatus("Type", coordinator.debugInfo.analyzerName,
                               color: coordinator.debugInfo.analyzerName.contains("GPT") ? .blue : .gray)
            debugRowWithStatus("Status", coordinator.isRunning ? "Running" : "Stopped",
                               color: coordinator.isRunning ? .blue : .orange)

            Divider()

            // Renderer
            Text("RENDERER").font(.caption2).foregroundStyle(.secondary)
            debugRowWithStatus("Frames", "\(coordinator.debugInfo.totalFrames)",
                               color: coordinator.debugInfo.totalFrames > 0 ? .blue : .orange)
            debugRowWithStatus("Analyzed", "\(coordinator.debugInfo.analyzedFrames)",
                               color: coordinator.debugInfo.analyzedFrames > 0 ? .blue : .orange)
            debugRowWithStatus("FPS", String(format: "%.1f", coordinator.debugInfo.fps),
                               color: coordinator.debugInfo.fps > 1 ? .blue : .orange)

            Divider()

            // Detection
            Text("DETECTION").font(.caption2).foregroundStyle(.secondary)
            debugRowWithStatus("Action", coordinator.debugInfo.lastAction, color: .cyan)
            debugRowWithStatus("Object", coordinator.debugInfo.lastObject, color: .purple)
            debugRowWithStatus("Conf", String(format: "%.0f%%", coordinator.debugInfo.confidence * 100),
                               color: coordinator.debugInfo.confidence > 0.7 ? .blue : .orange)

            // GPT-4V response
            if let response = coordinator.debugInfo.vlmLastResponse {
                Divider()
                Text("GPT-4V").font(.caption2).foregroundStyle(.secondary)
                Text(response).font(.caption2).lineLimit(2).foregroundStyle(.blue)
            }

            // Error
            if let error = coordinator.debugInfo.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(error).font(.caption2).foregroundStyle(.orange).lineLimit(1)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func debugRowWithStatus(_ label: String, _ value: String, color: Color) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary).frame(width: 60, alignment: .leading)
            Circle().fill(color).frame(width: 6, height: 6)
            Text(value).fontWeight(.medium)
        }
        .font(.caption)
    }

    private func statusRow(_ label: String, _ value: String, color: Color) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary).frame(width: 100, alignment: .leading)
            Circle().fill(color).frame(width: 8, height: 8)
            Text(value).fontWeight(.medium)
            Spacer()
        }
    }

    private func debugRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
            Text(value).fontWeight(.medium)
        }
        .font(.caption)
    }

    private func errorView(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text(message).font(.caption)
        }
        .padding()
        .background(.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func toggleSystem() async {
        if isStarted {
            coordinator.stop()
            isStarted = false
        } else {
            do {
                errorMessage = nil
                try await coordinator.start()
                coordinator.vlmPipeline.setSceneObjects(["menu", "table", "teacup"])
                isStarted = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Immersive View with VLM Integration

/// Immersive view that syncs draggable objects with the VLM's OffscreenRenderer
/// The VLM actually analyzes the rendered scene to detect interactions
/// Hand tracking is started directly here (required for ARKit hand tracking to work)
struct SimulatorImmersiveVLMView: View {
    @StateObject private var sceneManager = SimulatorSceneManager()
    @EnvironmentObject var dialogueModel: DialogueViewModel

    // Hand tracking - MUST be started in immersive space context
    @State private var handTrackingSession = ARKitSession()
    @State private var handTrackingProvider = HandTrackingProvider()

    var body: some View {
        RealityView { content in
            // Add the scene manager's root entity which contains all objects
            content.add(sceneManager.rootEntity)
        } update: { content in
            // Updates happen through the sceneManager
        }
        .gesture(
            DragGesture()
                .targetedToAnyEntity()
                .onChanged { value in
                    sceneManager.handleDrag(entity: value.entity, value: value)
                }
                .onEnded { value in
                    sceneManager.handleDragEnd(entity: value.entity, value: value)
                }
        )
        .task {
            sceneManager.coordinator.dialogueViewModel = dialogueModel
            await sceneManager.startVLM()
        }
        // Start hand tracking DIRECTLY in immersive space
        .task {
            await startHandTracking()
        }
        // Process hand updates in a separate task
        .task {
            await processHandUpdates()
        }
        .onDisappear {
            sceneManager.stopVLM()
            handTrackingSession.stop()
        }
    }

    /// Start hand tracking - must be called from within immersive space
    private func startHandTracking() async {
        vlmLog("Starting hand tracking in immersive space...", category: "Hands")

        // Check support
        guard HandTrackingProvider.isSupported else {
            vlmError("Hand tracking NOT SUPPORTED", category: "Hands")
            return
        }

        // Check and REQUEST authorization (not just query)
        var authStatus = await handTrackingSession.queryAuthorization(for: [.handTracking])
        vlmLog("Initial hand tracking auth: \(String(describing: authStatus[.handTracking]))", category: "Hands")

        // Request authorization if not yet determined or denied
        if authStatus[.handTracking] != .allowed {
            vlmLog("Requesting hand tracking authorization...", category: "Hands")
            authStatus = await handTrackingSession.requestAuthorization(for: [.handTracking])
            vlmLog("After request, auth: \(String(describing: authStatus[.handTracking]))", category: "Hands")
        }

        guard authStatus[.handTracking] == .allowed else {
            vlmError("Hand tracking not authorized: \(String(describing: authStatus[.handTracking]))", category: "Hands")
            return
        }

        // Run the session
        do {
            try await handTrackingSession.run([handTrackingProvider])
            vlmLog("Hand tracking STARTED successfully in immersive space!", category: "Hands")
        } catch {
            vlmError("Failed to start hand tracking: \(error)", category: "Hands")
        }
    }

    /// Process hand tracking updates and update the scene
    private func processHandUpdates() async {
        vlmLog("Starting hand update processing loop...", category: "Hands")

        for await update in handTrackingProvider.anchorUpdates {
            // Check for task cancellation
            if Task.isCancelled {
                vlmLog("Hand tracking task cancelled", category: "Hands")
                break
            }

            let anchor = update.anchor

            // Skip if not tracked
            guard anchor.isTracked else {
                await MainActor.run {
                    sceneManager.clearHand(chirality: anchor.chirality)
                }
                continue
            }

            // Update hand indicator position
            if let skeleton = anchor.handSkeleton {
                let indexTip = skeleton.joint(.indexFingerTip)
                if indexTip.isTracked {
                    let handTransform = anchor.originFromAnchorTransform
                    let jointTransform = indexTip.anchorFromJointTransform
                    let worldTransform = handTransform * jointTransform
                    let position = SIMD3<Float>(worldTransform.columns.3.x, worldTransform.columns.3.y, worldTransform.columns.3.z)

                    await MainActor.run {
                        sceneManager.updateHandIndicator(chirality: anchor.chirality, position: position)
                    }
                }
            }
        }
    }
}

// MARK: - Scene Manager

/// Manages the scene objects and syncs them with the VLM pipeline
@MainActor
class SimulatorSceneManager: ObservableObject {
    let coordinator = VLMSceneCoordinator()
    let rootEntity = Entity()

    // Scene objects - visible AND tracked by VLM
    private var table: ModelEntity!
    private var menu: ModelEntity!
    private var teacup: ModelEntity!
    private var ground: ModelEntity!

    // Hand indicators (cyan spheres at fingertips)
    private var leftHandIndicator: ModelEntity?
    private var rightHandIndicator: ModelEntity?

    // Track original positions for detecting movement (lowered, further away)
    private let tableY: Float = 0.55
    private let tableZ: Float = -0.85
    private var menuRestPosition: SIMD3<Float> { [0, tableY + 0.05, tableZ] }
    private var teacupRestPosition: SIMD3<Float> { [0.2, tableY + 0.04, tableZ] }

    // Track drag state
    private var isDragging: [String: Bool] = [:]
    private var lastDragTime: Date = Date()

    init() {
        setupScene()
        setupHandIndicators()
    }

    private func setupHandIndicators() {
        let indicatorMaterial = SimpleMaterial(color: .cyan.withAlphaComponent(0.8), isMetallic: false)

        let left = ModelEntity(
            mesh: .generateSphere(radius: 0.015),
            materials: [indicatorMaterial]
        )
        left.name = "leftHand"
        left.isEnabled = false
        rootEntity.addChild(left)
        leftHandIndicator = left

        let right = ModelEntity(
            mesh: .generateSphere(radius: 0.015),
            materials: [indicatorMaterial]
        )
        right.name = "rightHand"
        right.isEnabled = false
        rootEntity.addChild(right)
        rightHandIndicator = right
    }

    // MARK: - Hand Tracking

    func updateHandIndicator(chirality: HandAnchor.Chirality, position: SIMD3<Float>) {
        switch chirality {
        case .left:
            leftHandIndicator?.position = position
            leftHandIndicator?.isEnabled = true
        case .right:
            rightHandIndicator?.position = position
            rightHandIndicator?.isEnabled = true
        @unknown default:
            break
        }
    }

    func clearHand(chirality: HandAnchor.Chirality) {
        switch chirality {
        case .left:
            leftHandIndicator?.isEnabled = false
        case .right:
            rightHandIndicator?.isEnabled = false
        @unknown default:
            break
        }
    }

    private func setupScene() {
        // Ground plane (lowered for comfort)
        ground = ModelEntity(
            mesh: .generatePlane(width: 2, depth: 2),
            materials: [SimpleMaterial(color: .gray.withAlphaComponent(0.2), isMetallic: false)]
        )
        ground.position = [0, 0, tableZ]
        ground.name = "ground"
        rootEntity.addChild(ground)

        // Table (lowered for comfortable reach)
        table = ModelEntity(
            mesh: .generateBox(width: 0.7, height: 0.04, depth: 0.5),
            materials: [SimpleMaterial(color: .brown, isMetallic: false)]
        )
        table.position = [0, tableY, tableZ]
        table.name = "table"
        rootEntity.addChild(table)

        // Menu (red, draggable)
        menu = ModelEntity(
            mesh: .generateBox(width: 0.18, height: 0.015, depth: 0.25),
            materials: [SimpleMaterial(color: .red, isMetallic: false)]
        )
        menu.position = menuRestPosition
        menu.name = "menu"
        menu.generateCollisionShapes(recursive: true)
        menu.components.set(InputTargetComponent())
        rootEntity.addChild(menu)

        // Teacup (cyan cylinder, draggable)
        teacup = ModelEntity(
            mesh: .generateCylinder(height: 0.07, radius: 0.035),
            materials: [SimpleMaterial(color: .cyan, isMetallic: false)]
        )
        teacup.position = teacupRestPosition
        teacup.name = "teacup"
        teacup.generateCollisionShapes(recursive: true)
        teacup.components.set(InputTargetComponent())
        rootEntity.addChild(teacup)
    }

    func startVLM() async {
        do {
            // Try to use FastVLM (on-device) first, fall back to GPT-4V if model not found
            coordinator.analyzerType = .fastVLM

            // Start the VLM pipeline
            try await coordinator.start()

            // Set scene objects so VLM knows what to look for
            coordinator.vlmPipeline.setSceneObjects(["menu", "table", "teacup"])

            // Add objects to the OffscreenRenderer so the VLM can see them
            await syncObjectsToRenderer()

            print("VLM started with FastVLM - real on-device VLM analyzing rendered frames")
        } catch {
            print("FastVLM failed: \(error)")
            print("Falling back to GPT-4 Vision...")

            // Fall back to GPT-4V if FastVLM model not available
            do {
                coordinator.analyzerType = .gpt4Vision
                try await coordinator.start()
                coordinator.vlmPipeline.setSceneObjects(["menu", "table", "teacup"])
                await syncObjectsToRenderer()
                coordinator.debugInfo.analyzerName = "GPT-4V (API)"
                print("VLM started with GPT-4 Vision (fallback)")
            } catch {
                print("GPT-4V also failed: \(error)")
                print("Falling back to mock analyzer...")

                // Last resort: mock analyzer
                coordinator.analyzerType = .mock
                try? await coordinator.start()
                coordinator.vlmPipeline.setSceneObjects(["menu", "table", "teacup"])
                await syncObjectsToRenderer()
                coordinator.debugInfo.analyzerName = "Mock (heuristics)"
            }
        }
    }

    func stopVLM() {
        coordinator.stop()
    }

    /// Sync visible objects to the OffscreenRenderer
    private func syncObjectsToRenderer() async {
        // The VLM pipeline has a SceneCapture which has an OffscreenRenderer
        // We need to add matching entities there so the VLM "sees" the same scene
        // Use UnlitMaterial for visibility without complex lighting

        // Create copies of objects for the offscreen renderer
        var tableMaterial = UnlitMaterial()
        tableMaterial.color = .init(tint: .brown)
        let offscreenTable = ModelEntity(
            mesh: .generateBox(width: 0.8, height: 0.05, depth: 0.6),
            materials: [tableMaterial]
        )
        offscreenTable.position = table.position

        var menuMaterial = UnlitMaterial()
        menuMaterial.color = .init(tint: .red)
        let offscreenMenu = ModelEntity(
            mesh: .generateBox(width: 0.2, height: 0.02, depth: 0.3),
            materials: [menuMaterial]
        )
        offscreenMenu.position = menu.position
        offscreenMenu.name = "menu"

        var teacupMaterial = UnlitMaterial()
        teacupMaterial.color = .init(tint: .cyan)
        let offscreenTeacup = ModelEntity(
            mesh: .generateCylinder(height: 0.08, radius: 0.04),
            materials: [teacupMaterial]
        )
        offscreenTeacup.position = teacup.position
        offscreenTeacup.name = "teacup"

        // Add to VLM pipeline
        coordinator.vlmPipeline.addSceneObject(offscreenTable, name: "table")
        coordinator.vlmPipeline.addSceneObject(offscreenMenu, name: "menu")
        coordinator.vlmPipeline.addSceneObject(offscreenTeacup, name: "teacup")

        vlmLog("Synced objects to offscreen renderer at positions: table=\(table.position), menu=\(menu.position), teacup=\(teacup.position)", category: "Render")
    }

    func handleDrag(entity: Entity, value: EntityTargetValue<DragGesture.Value>) {
        let name = entity.name
        guard !name.isEmpty, name != "table", name != "ground" else { return }

        let translation = value.convert(value.translation3D, from: .local, to: .scene)
        let newPosition = SIMD3<Float>(
            Float(translation.x),
            max(tableY + 0.05, Float(translation.y)), // Keep above table
            Float(translation.z)
        )

        // Update visible entity position
        entity.position = newPosition

        // Track if we just started dragging
        let wasAlreadyDragging = isDragging[name] ?? false
        isDragging[name] = true

        // Update the MockAnalyzer with new object position
        // The VLM's object position tracking will detect the movement and classify it
        if let mockAnalyzer = getAnalyzer() {
            mockAnalyzer.updateObjectPosition(name, position: newPosition)

            // For immediate feedback on first drag, inject picking_up
            // Otherwise, let the VLM's position tracking detect ongoing movement
            if !wasAlreadyDragging {
                // VLM will see object moved up = picking_up
                print("VLM: Object '\(name)' lifted - position tracking will detect movement")
            }
        }

        lastDragTime = Date()
    }

    func handleDragEnd(entity: Entity, value: EntityTargetValue<DragGesture.Value>) {
        let name = entity.name
        guard !name.isEmpty else { return }

        isDragging[name] = false

        // Snap to table if close enough
        if entity.position.y < tableY + 0.15 {
            // Snap to rest position
            if name == "menu" {
                entity.position = menuRestPosition
            } else if name == "teacup" {
                entity.position = teacupRestPosition
            }

            // Update position - VLM will detect object returned to table = placing
            if let mockAnalyzer = getAnalyzer() {
                mockAnalyzer.updateObjectPosition(name, position: entity.position)
                print("VLM: Object '\(name)' placed on table - position tracking will detect")
            }
        }
    }

    private func getAnalyzer() -> MockAnalyzer? {
        // Access the mock analyzer from the VLM pipeline
        return coordinator.vlmPipeline.mockAnalyzer
    }
}

// MARK: - Preview

#Preview(windowStyle: .automatic) {
    SimulatorVLMTestView()
}
