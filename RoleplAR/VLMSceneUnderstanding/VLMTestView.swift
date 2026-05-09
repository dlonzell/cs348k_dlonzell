import SwiftUI
import RealityKit
import ARKit

/// Test view for the VLM Scene Understanding system
/// Can be used standalone or integrated into RoleplAR's scene flow
struct VLMTestView: View {
    /// Use the shared DeviceSceneManager's coordinator so window and immersive view are in sync
    private var coordinator: VLMSceneCoordinator { DeviceSceneManager.shared.coordinator }
    @EnvironmentObject var dialogueModel: DialogueViewModel
    @EnvironmentObject var narrativeModel: NarrativeModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow

    @State private var isStarted = false
    @State private var showDebug = true
    @State private var showLogs = false
    @State private var showFrames = false
    @State private var errorMessage: String?
    @State private var isImmersiveOpen = false
    @State private var frameSaveStatus: String?
    @State private var useGPT4V = false  // Toggle between FastVLM (default) and GPT-4V

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Main content (scrollable)
                ScrollView {
                    VStack(spacing: 16) {
                        headerView

                        Divider()

                        statusView

                        controlsView

                        if let error = errorMessage {
                            errorView(error)
                        }
                    }
                    .padding()
                }
                .frame(minWidth: 350)

                // Debug overlay (side panel - scrollable for taller content)
                if showDebug && isStarted {
                    ScrollView {
                        VLMDebugOverlay(coordinator: coordinator)
                            .frame(width: 300)
                    }
                    .frame(width: 320)
                    .frame(minHeight: 500)
                    .padding(.vertical)
                }
            }

            // Log viewer (bottom panel)
            if showLogs {
                Divider()
                DebugLogViewer()
                    .frame(height: 200)
            }

            // Frame viewer (bottom panel - larger for better preview)
            if showFrames {
                Divider()
                DebugFrameViewer()
                    .frame(height: 400)
            }
        }
        .onAppear {
            // Connect to existing models
            coordinator.dialogueViewModel = dialogueModel
            coordinator.narrativeModel = narrativeModel
        }
        .onDisappear {
            coordinator.stop()
        }
    }

    // MARK: - Subviews

    private var headerView: some View {
        VStack(spacing: 8) {
            Text("VLM Scene Understanding")
                .font(.title)
                .fontWeight(.bold)

            Text("Test the VLM action recognition pipeline")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Instructions
            VStack(alignment: .leading, spacing: 4) {
                Text("How to use:")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("1. Tap 'Start System' to begin")
                Text("2. Tap 'Open Immersive Scene' to see objects")
                Text("3. Reach toward, pick up, or place the menu/teacup")
                Text("4. Watch for NPC responses below")
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

            statusRow("Scene State", coordinator.currentSceneState.rawValue.capitalized,
                      color: .blue)

            if let lastAction = coordinator.vlmPipeline.latestClassification {
                statusRow("Last Action", lastAction.action.displayName,
                          color: .orange)

                if let object = lastAction.object {
                    statusRow("Object", object, color: .purple)
                }

                statusRow("Confidence",
                          String(format: "%.0f%%", lastAction.confidence * 100),
                          color: lastAction.confidence > 0.7 ? .green : .yellow)
            }

            if let reaction = coordinator.reactionSystem.lastReaction {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last NPC Response:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(reaction.japaneseText)
                        .font(.headline)
                    if let english = reaction.englishHint {
                        Text(english)
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
            // Analyzer selection (only when stopped)
            if !isStarted {
                HStack {
                    Text("Analyzer:")
                        .foregroundStyle(.secondary)
                    Picker("Analyzer", selection: $useGPT4V) {
                        Text("FastVLM (On-Device)").tag(false)
                        Text("GPT-4V (API)").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal)

                // Clear cache button (only show when FastVLM selected)
                if !useGPT4V {
                    Button {
                        coordinator.fastVLMAnalyzer.clearModelCache()
                        errorMessage = "Model cache cleared. Will re-download on next start."
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Clear Model Cache")
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }
            } else {
                // Show current analyzer
                HStack {
                    Image(systemName: useGPT4V ? "cloud.fill" : "cpu.fill")
                    Text(useGPT4V ? "Using GPT-4V (API)" : "Using FastVLM (On-Device)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Main control button
            Button {
                Task {
                    await toggleSystem()
                }
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

            // Secondary controls
            HStack(spacing: 12) {
                Button("Greet") {
                    coordinator.triggerGreeting()
                }
                .buttonStyle(.bordered)
                .disabled(!isStarted)

                Button("Farewell") {
                    coordinator.triggerFarewell()
                }
                .buttonStyle(.bordered)
                .disabled(!isStarted)

                Toggle("Debug", isOn: $showDebug)
                    .toggleStyle(.button)

                Toggle("Logs", isOn: $showLogs)
                    .toggleStyle(.button)
                    .tint(.purple)

                Toggle("Frames", isOn: $showFrames)
                    .toggleStyle(.button)
                    .tint(.cyan)

                Button {
                    openWindow(id: "frameViewer")
                } label: {
                    Image(systemName: "macwindow")
                }
                .buttonStyle(.bordered)
                .help("Open Frame Viewer Window")
            }

            // Save frame button (prominent)
            Button {
                Task {
                    frameSaveStatus = "Saving..."

                    // Check if we have frames first
                    if coordinator.debugInfo.totalFrames == 0 {
                        frameSaveStatus = "No frames captured yet"
                        return
                    }

                    do {
                        try await coordinator.saveDebugFrame()
                        frameSaveStatus = "Saved to Photos!"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            frameSaveStatus = nil
                        }
                    } catch {
                        frameSaveStatus = "Error: \(error.localizedDescription)"
                        print("Save frame error: \(error)")
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "camera.fill")
                    Text(frameSaveStatus ?? "Save Frame to Photos")
                }
                .frame(maxWidth: .infinity)
                .padding(8)
            }
            .buttonStyle(.bordered)
            .tint(frameSaveStatus?.contains("Saved") == true ? .blue :
                  frameSaveStatus?.contains("Error") == true ? .orange : .purple)
            .disabled(!isStarted)

            // Only show manual immersive toggle when system is running
            // (Start/Stop button now handles opening/closing immersive space)
            if isStarted {
                Divider()

                // Manual immersive space toggle (for closing without stopping system)
                Button {
                    Task {
                        if isImmersiveOpen {
                            await dismissImmersiveSpace()
                            isImmersiveOpen = false
                            // Also stop the system since immersive is closed
                            coordinator.stop()
                            isStarted = false
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                        Text("Close Immersive Scene")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
    }

    private func statusRow(_ label: String, _ value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)

            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(value)
                .fontWeight(.medium)

            Spacer()
        }
    }

    private func errorView(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.caption)
        }
        .padding()
        .background(.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Actions

    private func toggleSystem() async {
        print(">>> toggleSystem called, isStarted=\(isStarted)")
        vlmLog("toggleSystem called, isStarted=\(isStarted)", category: "UI")

        if isStarted {
            print(">>> Stopping...")
            vlmLog("Stopping system...", category: "UI")

            // Close immersive space first
            if isImmersiveOpen {
                await dismissImmersiveSpace()
                isImmersiveOpen = false
            }

            coordinator.stop()
            isStarted = false
            vlmLog("System stopped", category: "UI")
        } else {
            print(">>> Entering else branch (will start)")
            do {
                errorMessage = nil
                print(">>> About to log 'Starting system...'")
                vlmLog("Starting system...", category: "UI")

                // Select analyzer type
                #if targetEnvironment(simulator)
                coordinator.analyzerType = .mock
                print(">>> Using MockAnalyzer (simulator)")
                vlmLog("Using MockAnalyzer (simulator)", category: "UI")
                #else
                if useGPT4V {
                    coordinator.analyzerType = .gpt4Vision
                    print(">>> Using GPT-4V (device)")
                    vlmLog("Using GPT-4V (device)", category: "UI")
                } else {
                    coordinator.analyzerType = .fastVLM
                    print(">>> Using FastVLM (device)")
                    vlmLog("Using FastVLM (device)", category: "UI")
                }
                #endif

                // Open immersive space which triggers startVLM()
                // The VLMImmersiveTestView.task calls sceneManager.startVLM()
                if !isImmersiveOpen {
                    let result = await openImmersiveSpace(id: "vlmImmersive")
                    if case .opened = result {
                        isImmersiveOpen = true
                        isStarted = true
                        print(">>> SUCCESS - immersive space opened and system started")
                        vlmLog("System started successfully!", category: "UI")
                    } else {
                        throw NSError(domain: "VLMTestView", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to open immersive space"])
                    }
                } else {
                    isStarted = true
                }
            } catch {
                print(">>> CATCH - error: \(error)")
                vlmError("Start failed: \(error)", category: "UI")
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Immersive Test View

/// Immersive space version that shows the actual scene with drag support
/// Hand tracking is started directly here (required for ARKit hand tracking)
struct VLMImmersiveTestView: View {
    @ObservedObject private var sceneManager = DeviceSceneManager.shared
    @EnvironmentObject var dialogueModel: DialogueViewModel

    // Hand tracking - MUST be started in immersive space context
    @State private var handTrackingSession = ARKitSession()
    @State private var handTrackingProvider = HandTrackingProvider()

    var body: some View {
        RealityView { content in
            content.add(sceneManager.rootEntity)
        } update: { content in
            // Hand visualization updates happen via hand tracking task
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
        // Process hand updates
        .task {
            await processHandUpdates()
        }
        .onDisappear {
            sceneManager.stopVLM()
            handTrackingSession.stop()
        }
    }

    private func startHandTracking() async {
        vlmLog("Starting hand tracking in VLMImmersiveTestView...", category: "Hands")

        guard HandTrackingProvider.isSupported else {
            vlmError("Hand tracking NOT SUPPORTED", category: "Hands")
            return
        }

        // Check and REQUEST authorization (not just query)
        var authStatus = await handTrackingSession.queryAuthorization(for: [.handTracking])
        vlmLog("Initial hand tracking auth: \(String(describing: authStatus[.handTracking]))", category: "Hands")

        if authStatus[.handTracking] != .allowed {
            vlmLog("Requesting hand tracking authorization...", category: "Hands")
            authStatus = await handTrackingSession.requestAuthorization(for: [.handTracking])
            vlmLog("After request, auth: \(String(describing: authStatus[.handTracking]))", category: "Hands")
        }

        guard authStatus[.handTracking] == .allowed else {
            vlmError("Hand tracking not authorized: \(String(describing: authStatus[.handTracking]))", category: "Hands")
            return
        }

        do {
            try await handTrackingSession.run([handTrackingProvider])
            vlmLog("Hand tracking STARTED successfully!", category: "Hands")
        } catch {
            vlmError("Failed to start hand tracking: \(error)", category: "Hands")
        }
    }

    private func processHandUpdates() async {
        for await update in handTrackingProvider.anchorUpdates {
            // Check for task cancellation
            if Task.isCancelled {
                vlmLog("Hand tracking task cancelled", category: "Hands")
                break
            }

            let anchor = update.anchor

            guard anchor.isTracked else {
                await MainActor.run {
                    sceneManager.clearHand(chirality: anchor.chirality)
                }
                continue
            }

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

// MARK: - Device Scene Manager

/// Manages scene objects with drag support and hand visualization for device
@MainActor
class DeviceSceneManager: ObservableObject {
    /// Shared instance so window and immersive view use the same coordinator/pipeline
    static let shared = DeviceSceneManager()

    let coordinator = VLMSceneCoordinator()
    let rootEntity = Entity()

    // Scene objects
    private var table: ModelEntity!
    private var menu: ModelEntity!
    private var teacup: ModelEntity!
    private var baseballBat: ModelEntity?
    private var baseball: ModelEntity?

    // Hand visualization (minimal - just fingertip spheres)
    private var leftHandIndicator: ModelEntity?
    private var rightHandIndicator: ModelEntity?

    // Rest positions (lowered for comfortable reach, further away)
    private let tableY: Float = 0.55
    private let tableZ: Float = -0.85
    private var menuRestPosition: SIMD3<Float> { [0, tableY + 0.05, tableZ] }
    private var teacupRestPosition: SIMD3<Float> { [0.2, tableY + 0.04, tableZ] }
    private var baseballBatRestPosition: SIMD3<Float> { [-0.25, tableY + 0.05, tableZ] }
    private var baseballRestPosition: SIMD3<Float> { [-0.15, tableY + 0.04, tableZ] }

    // Drag state
    private var dragStartPositions: [String: SIMD3<Float>] = [:]
    private var dragGrabOffsets: [String: SIMD3<Float>] = [:]  // Offset from grab point to object center

    init() {
        setupScene()
        setupHandIndicators()
    }

    private func setupScene() {
        // Ground plane
        let ground = ModelEntity(
            mesh: .generatePlane(width: 2, depth: 2),
            materials: [SimpleMaterial(color: .gray.withAlphaComponent(0.2), isMetallic: false)]
        )
        ground.position = [0, 0, tableZ]
        ground.name = "ground"
        rootEntity.addChild(ground)

        // Table (lowered)
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

        // Teacup (cyan, draggable)
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

    /// Load USDZ objects asynchronously
    func loadUSDZObjects() async {
        // Load baseball bat
        if let batURL = Bundle.main.url(forResource: "Baseball_Bat_new", withExtension: "usdz") {
            do {
                let batEntity = try await Entity(contentsOf: batURL)

                // Use the root entity directly as a wrapper
                baseballBat = ModelEntity()
                baseballBat?.addChild(batEntity)

                baseballBat?.position = baseballBatRestPosition
                baseballBat?.name = "baseballBat"
                baseballBat?.scale = [0.6, 0.6, 0.6]  // 2x bigger than before

                // Remove any physics from USDZ to make it easy to drag
                removePhysicsRecursively(from: baseballBat!)

                // Simple box collision for easy dragging - HORIZONTAL orientation
                // Width = long axis (bat length), Height & Depth = bat thickness
                let collisionWidth: Float = 0.5   // Long axis (horizontal)
                let collisionHeight: Float = 0.1  // Thin vertically
                let collisionDepth: Float = 0.1   // Thin in depth
                let collisionYOffset: Float = 0.40  // Offset upward to align with bat (increased from 0.25)

                // Create collision shape with vertical offset
                let collisionShape = ShapeResource.generateBox(width: collisionWidth, height: collisionHeight, depth: collisionDepth)
                    .offsetBy(translation: [0, collisionYOffset, 0])
                baseballBat?.components.set(CollisionComponent(shapes: [collisionShape]))
                baseballBat?.components.set(InputTargetComponent())

                // DEBUG: Add visible collision box overlay (offset to match)
                let debugMaterial = SimpleMaterial(color: .yellow.withAlphaComponent(0.3), isMetallic: false)
                let debugBox = ModelEntity(
                    mesh: .generateBox(width: collisionWidth, height: collisionHeight, depth: collisionDepth),
                    materials: [debugMaterial]
                )
                debugBox.name = "debugCollision"
                debugBox.position.y = collisionYOffset  // Match the collision offset
                baseballBat?.addChild(debugBox)

                if let bat = baseballBat {
                    rootEntity.addChild(bat)
                    vlmLog("Loaded baseball bat USDZ with debug collision box", category: "Scene")
                }
            } catch {
                vlmError("Failed to load baseball bat: \(error)", category: "Scene")
            }
        } else {
            vlmError("Baseball_Bat_new.usdz not found in bundle", category: "Scene")
        }

        // Load baseball
        if let ballURL = Bundle.main.url(forResource: "Worn_Baseball_Ball", withExtension: "usdz") {
            do {
                let ballEntity = try await Entity(contentsOf: ballURL)

                // Use the root entity directly as a wrapper
                baseball = ModelEntity()
                baseball?.addChild(ballEntity)

                baseball?.position = baseballRestPosition
                baseball?.name = "baseball"
                baseball?.scale = [0.1, 0.1, 0.1]  // 5x smaller than before

                // Remove any physics from USDZ to make it easy to drag
                removePhysicsRecursively(from: baseball!)

                // Simple sphere collision for easy dragging
                baseball?.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.04)]))
                baseball?.components.set(InputTargetComponent())

                if let ball = baseball {
                    rootEntity.addChild(ball)
                    vlmLog("Loaded baseball USDZ", category: "Scene")
                }
            } catch {
                vlmError("Failed to load baseball: \(error)", category: "Scene")
            }
        } else {
            vlmError("Worn_Baseball_Ball.usdz not found in bundle", category: "Scene")
        }
    }

    /// Remove physics components from an entity and all its children
    private func removePhysicsRecursively(from entity: Entity) {
        entity.components.remove(PhysicsBodyComponent.self)
        entity.components.remove(PhysicsMotionComponent.self)
        for child in entity.children {
            removePhysicsRecursively(from: child)
        }
    }

    /// Remove collision components from an entity's children (but not the entity itself)
    /// This prevents USDZ internal collision from interfering with our custom collision
    private func removeCollisionRecursively(from entity: Entity) {
        for child in entity.children {
            child.components.remove(CollisionComponent.self)
            child.components.remove(PhysicsBodyComponent.self)
            removeCollisionRecursively(from: child)
        }
    }

    private func setupHandIndicators() {
        // Minimal hand visualization - small spheres for index fingertips
        // These are purely visual and should NOT interact with other objects
        let indicatorMaterial = SimpleMaterial(color: .cyan.withAlphaComponent(0.8), isMetallic: false)

        let left = ModelEntity(
            mesh: .generateSphere(radius: 0.015),
            materials: [indicatorMaterial]
        )
        left.name = "leftHand"
        left.isEnabled = false
        // Explicitly ensure no collision or input on hand indicators
        left.components.remove(CollisionComponent.self)
        left.components.remove(InputTargetComponent.self)
        left.components.remove(PhysicsBodyComponent.self)
        rootEntity.addChild(left)
        leftHandIndicator = left

        let right = ModelEntity(
            mesh: .generateSphere(radius: 0.015),
            materials: [indicatorMaterial]
        )
        right.name = "rightHand"
        right.isEnabled = false
        // Explicitly ensure no collision or input on hand indicators
        right.components.remove(CollisionComponent.self)
        right.components.remove(InputTargetComponent.self)
        right.components.remove(PhysicsBodyComponent.self)
        rootEntity.addChild(right)
        rightHandIndicator = right
    }

    func startVLM() async {
        do {
            #if targetEnvironment(simulator)
            coordinator.analyzerType = .mock
            #else
            coordinator.analyzerType = .fastVLM  // Default to FastVLM for on-device inference
            #endif

            // Load USDZ objects first
            await loadUSDZObjects()

            try await coordinator.start()
            coordinator.vlmPipeline.setSceneObjects(["menu", "table", "teacup", "baseballBat", "baseball"])

            // Sync objects to offscreen renderer
            await syncObjectsToRenderer()

            // Note: Hand tracking is now started directly in the immersive view
            print("DeviceSceneManager: VLM started with \(coordinator.analyzerType)")
        } catch {
            print("DeviceSceneManager: Failed to start - \(error)")
        }
    }

    func stopVLM() {
        coordinator.stop()
    }

    private func syncObjectsToRenderer() async {
        // Create copies for offscreen renderer using UnlitMaterial for visibility
        var tableMaterial = UnlitMaterial()
        tableMaterial.color = .init(tint: .brown)
        let offscreenTable = ModelEntity(
            mesh: .generateBox(width: 0.7, height: 0.04, depth: 0.5),
            materials: [tableMaterial]
        )
        offscreenTable.position = table.position

        var menuMaterial = UnlitMaterial()
        menuMaterial.color = .init(tint: .red)
        let offscreenMenu = ModelEntity(
            mesh: .generateBox(width: 0.18, height: 0.015, depth: 0.25),
            materials: [menuMaterial]
        )
        offscreenMenu.position = menu.position
        offscreenMenu.name = "menu"

        var teacupMaterial = UnlitMaterial()
        teacupMaterial.color = .init(tint: .cyan)
        let offscreenTeacup = ModelEntity(
            mesh: .generateCylinder(height: 0.07, radius: 0.035),
            materials: [teacupMaterial]
        )
        offscreenTeacup.position = teacup.position
        offscreenTeacup.name = "teacup"

        coordinator.vlmPipeline.addSceneObject(offscreenTable, name: "table")
        coordinator.vlmPipeline.addSceneObject(offscreenMenu, name: "menu")
        coordinator.vlmPipeline.addSceneObject(offscreenTeacup, name: "teacup")

        // Add baseball bat as a visible primitive (USDZ doesn't render well without proper lighting)
        // Use UnlitMaterial so it's always visible in offscreen render
        if let bat = baseballBat {
            var batMaterial = UnlitMaterial()
            batMaterial.color = .init(tint: .brown)  // Wood-colored bat
            let offscreenBat = ModelEntity(
                mesh: .generateBox(width: 0.5, height: 0.1, depth: 0.1),  // Match collision box shape
                materials: [batMaterial]
            )
            // Match the visible bat position with the same Y offset as collision box
            offscreenBat.position = bat.position + SIMD3<Float>(0, 0.40, 0)
            offscreenBat.name = "baseballBat"
            coordinator.vlmPipeline.addSceneObject(offscreenBat, name: "baseballBat")
        }

        // Add baseball as a visible sphere primitive
        if let ball = baseball {
            var ballMaterial = UnlitMaterial()
            ballMaterial.color = .init(tint: .white)  // White baseball
            let offscreenBall = ModelEntity(
                mesh: .generateSphere(radius: 0.025),  // Baseball-sized sphere
                materials: [ballMaterial]
            )
            offscreenBall.position = ball.position
            offscreenBall.name = "baseball"
            coordinator.vlmPipeline.addSceneObject(offscreenBall, name: "baseball")
        }

        vlmLog("Synced objects to offscreen renderer", category: "Render")
    }

    // MARK: - Hand Visualization (updated directly from immersive view)

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

    // MARK: - Drag Handling

    func handleDrag(entity: Entity, value: EntityTargetValue<DragGesture.Value>) {
        let name = entity.name
        guard !name.isEmpty, name != "table", name != "ground" else { return }

        // On first drag, store the start position
        if dragStartPositions[name] == nil {
            dragStartPositions[name] = entity.position

            // Calculate grab offset: where in the object's local space was grabbed
            // This keeps the object positioned relative to where it was grabbed
            let grabPointWorld = value.convert(value.startLocation3D, from: .local, to: .scene)
            let objectCenter = entity.position
            dragGrabOffsets[name] = SIMD3<Float>(
                objectCenter.x - Float(grabPointWorld.x),
                objectCenter.y - Float(grabPointWorld.y),
                objectCenter.z - Float(grabPointWorld.z)
            )
            vlmLog("Drag start: \(name) at \(objectCenter), grab offset: \(dragGrabOffsets[name]!)", category: "Drag")
        }

        // Get current hand/grab position in world space
        let currentGrabWorld = value.convert(value.location3D, from: .local, to: .scene)

        // Apply the grab offset so object stays relative to where it was grabbed
        let grabOffset = dragGrabOffsets[name] ?? .zero

        let newPosition = SIMD3<Float>(
            Float(currentGrabWorld.x) + grabOffset.x,
            max(tableY + 0.05, Float(currentGrabWorld.y) + grabOffset.y), // Keep above table
            Float(currentGrabWorld.z) + grabOffset.z
        )

        entity.position = newPosition

        // Update offscreen renderer object position
        updateOffscreenObject(name: name, position: newPosition)
    }

    func handleDragEnd(entity: Entity, value: EntityTargetValue<DragGesture.Value>) {
        let name = entity.name
        guard !name.isEmpty else { return }

        dragStartPositions.removeValue(forKey: name)
        dragGrabOffsets.removeValue(forKey: name)

        // If close to table, snap to rest position
        if entity.position.y < tableY + 0.15 {
            let restPosition: SIMD3<Float>
            switch name {
            case "menu":
                restPosition = menuRestPosition
            case "teacup":
                restPosition = teacupRestPosition
            case "baseballBat":
                restPosition = baseballBatRestPosition
            case "baseball":
                restPosition = baseballRestPosition
            default:
                restPosition = entity.position
            }
            entity.position = restPosition
            updateOffscreenObject(name: name, position: restPosition)
            vlmLog("Drag end: \(name) snapped to rest at \(restPosition)", category: "Drag")
        } else {
            vlmLog("Drag end: \(name) released at \(entity.position)", category: "Drag")
        }
    }

    private func updateOffscreenObject(name: String, position: SIMD3<Float>) {
        // Only update if coordinator is running (avoids errors when dragging before start)
        guard coordinator.isRunning else { return }

        // Apply Y offset for bat to match visible collision box position
        var adjustedPosition = position
        if name == "baseballBat" {
            adjustedPosition.y += 0.40
        }

        // Update the position in the offscreen renderer
        // This ensures GPT-4V sees the current object positions
        coordinator.vlmPipeline.updateSceneObjectPosition(name: name, position: adjustedPosition)

        // Also update mock analyzer if using it (for heuristic detection)
        if let mockAnalyzer = coordinator.vlmPipeline.mockAnalyzer {
            mockAnalyzer.updateObjectPosition(name, position: adjustedPosition)
        }
    }
}

// MARK: - Preview

#Preview(windowStyle: .automatic) {
    VLMTestView()
        .environmentObject(DialogueViewModel())
        .environmentObject(NarrativeModel())
}
