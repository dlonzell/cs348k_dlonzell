import SwiftUI
import RealityKit
import UIKit

struct InteractionWorldTestView: View {
    @EnvironmentObject private var runtime: InteractionWorldRuntime
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    @StateObject private var generator = InteractionWorldGenerator()
    @State private var isImmersiveOpen = false
    @State private var openError: String?
    @State private var metricInfoPopover: ManualEvaluationMetric?
    @State private var isGenerating = false
    @State private var generationResult: GenerationResult?
    @State private var generationError: String?
    @State private var generationLogURL: URL?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 360)

            Divider()
                .overlay(Color.white.opacity(0.18))

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    controls
                    evaluationCard
                    manualEvaluationPanel
                }
                .padding(22)
            }
            .frame(minWidth: 500)

            Divider()
                .overlay(Color.white.opacity(0.18))

            eventLog
                .frame(width: 300)
        }
        .foregroundStyle(.white)
        .background(windowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .popover(item: $metricInfoPopover) { metric in
            VStack(alignment: .leading, spacing: 10) {
                Text(metric.title)
                    .font(.headline)
                Text(metric.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(width: 320)
        }
        .onDisappear {
            Task {
                if isImmersiveOpen {
                    await dismissImmersiveSpace()
                }
            }
        }
    }

    private var windowBackground: Color {
        Color(red: 0.07, green: 0.075, blue: 0.085).opacity(0.96)
    }

    private var cardBackground: Color {
        Color(red: 0.14, green: 0.15, blue: 0.16).opacity(0.92)
    }

    private var activeRowBackground: Color {
        Color(red: 0.12, green: 0.22, blue: 0.36).opacity(0.86)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            currentTaskCard
            ScrollView {
                taskList
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .background(Color(red: 0.09, green: 0.095, blue: 0.105).opacity(0.94))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Interaction World")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text(runtime.plan.scenario.setting)
                .font(.headline)
            Text(runtime.plan.scenario.sceneGoal)
                .foregroundStyle(.secondary)
            Text(runtime.plan.scenario.localContext)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                Task { await toggleImmersive() }
            } label: {
                Label(
                    isImmersiveOpen ? "Close Micro-world" : "Open Micro-world",
                    systemImage: isImmersiveOpen ? "xmark.circle.fill" : "cube.transparent.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            HStack {
                Button {
                    runtime.process(.gesture(.wave, targetId: "barista_marker"))
                } label: {
                    Label("Mock Wave", systemImage: "hand.wave")
                }
                .buttonStyle(.bordered)

                Button {
                    runtime.process(.gesture(.point, targetId: "pastry_case"))
                } label: {
                    Label("Mock Point", systemImage: "hand.point.up.left")
                }
                .buttonStyle(.bordered)

                Button {
                    runtime.reset()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
            }

            Button {
                Task { await generateCafePlan() }
            } label: {
                Label(
                    isGenerating ? "Generating..." : "Generate Cafe Plan",
                    systemImage: "sparkles"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isGenerating)

            if let openError {
                Text(openError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            generationStatus
        }
    }

    @ViewBuilder
    private var generationStatus: some View {
        if let generationError {
            Text(generationError)
                .font(.caption)
                .foregroundStyle(.red)
        }

        if let generationResult {
            VStack(alignment: .leading, spacing: 4) {
                Text(generationResult.succeeded ? "Generated plan loaded." : "Generation failed.")
                    .font(.caption)
                    .foregroundStyle(generationResult.succeeded ? .green : .yellow)
                Text("Attempts: \(generationResult.attempts.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let lastAttempt = generationResult.attempts.last {
                    Text("Last outcome: \(lastAttempt.outcome.shortDescription)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let generationLogURL {
                    Text("Log: \(generationLogURL.lastPathComponent)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var currentTaskCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Current Task")
                    .font(.headline)
                Spacer()
                Text(runtime.progressText)
                    .font(.headline)
                    .monospacedDigit()
            }

            if let task = runtime.currentTask {
                Text(task.instruction)
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(task.expectedInteraction.displayDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("All tasks complete.")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
            }
        }
        .padding()
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var taskList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Task Queue")
                .font(.headline)

            ForEach(Array(runtime.plan.tasks.enumerated()), id: \.element.id) { index, task in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: taskIcon(index: index, taskId: task.id))
                        .foregroundStyle(taskColor(index: index, taskId: task.id))
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.instruction)
                            .fontWeight(index == runtime.currentTaskIndex ? .semibold : .regular)
                        Text(task.requiredObjectIds.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(8)
                .background(index == runtime.currentTaskIndex ? activeRowBackground : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var evaluationCard: some View {
        let result = runtime.evaluate()

        return VStack(alignment: .leading, spacing: 8) {
            Text("Evaluation")
                .font(.headline)
            metricRow("Object coverage", result.objectCoverageSummary)
            metricRow("Handler coverage", result.handlerCoverageSummary)
            metricRow("Completed tasks", result.completionSummary)
            if let failed = result.firstFailedTaskId {
                metricRow("First incomplete", failed)
            } else {
                metricRow("First incomplete", "none")
            }
        }
        .padding()
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var manualEvaluationPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Manual Evaluation")
                        .font(.headline)
                    Text("Score generated objects, wiring, and runtime behavior after testing the scene.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(runtime.manualEvaluationSummary)
                    .font(.headline)
                    .monospacedDigit()
            }

            scenarioManualRatings
            objectManualRatings

            ForEach(runtime.plan.tasks) { task in
                manualTaskCard(task)
            }
        }
        .padding()
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var scenarioManualRatings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Scenario")
                .font(.subheadline)
                .fontWeight(.semibold)

            HStack {
                Text("Spatial layout")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Spatial layout", selection: scenarioLayoutBinding) {
                    ForEach(ScenarioLayoutRating.allCases) { rating in
                        Text(rating.title).tag(rating)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 130)
            }

            HStack {
                Text("Scenario fidelity")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Scenario fidelity", selection: scenarioFidelityBinding) {
                    ForEach(ScenarioFidelityRating.allCases) { rating in
                        Text(rating.title).tag(rating)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 130)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var objectManualRatings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Generated Objects")
                .font(.subheadline)
                .fontWeight(.semibold)

            ForEach(runtime.plan.objects) { object in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(object.displayName)
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text(object.id)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker(
                        object.displayName,
                        selection: generatedObjectRatingBinding(objectId: object.id)
                    ) {
                        ForEach(GeneratedObjectRating.allCases) { rating in
                            Text(rating.title).tag(rating)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 130)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func manualTaskCard(_ task: InteractionTask) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(task.instruction)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(task.expectedInteraction.displayDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Primitive faithfulness")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker(
                    "Primitive faithfulness",
                    selection: generatedTaskRatingBinding(taskId: task.id)
                ) {
                    ForEach(GeneratedTaskFidelityRating.allCases) { rating in
                        Text(rating.title).tag(rating)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 130)
            }

            ForEach(ManualEvaluationMetric.allCases) { metric in
                manualMetricRow(task: task, metric: metric)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func manualMetricRow(
        task: InteractionTask,
        metric: ManualEvaluationMetric
    ) -> some View {
        HStack(spacing: 10) {
            Button {
                metricInfoPopover = metric
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(metric.description)

            Text(metric.title)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker(metric.title, selection: manualRatingBinding(taskId: task.id, metric: metric)) {
                ForEach(ManualEvaluationRating.allCases) { rating in
                    Text(rating.title).tag(rating)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 116)
            .tint(ratingColor(runtime.manualRating(taskId: task.id, metric: metric)))
        }
    }

    private func manualRatingBinding(
        taskId: String,
        metric: ManualEvaluationMetric
    ) -> Binding<ManualEvaluationRating> {
        Binding {
            runtime.manualRating(taskId: taskId, metric: metric)
        } set: { newValue in
            runtime.setManualRating(newValue, taskId: taskId, metric: metric)
        }
    }

    private var scenarioLayoutBinding: Binding<ScenarioLayoutRating> {
        Binding {
            runtime.scenarioLayoutRating
        } set: { newValue in
            runtime.setScenarioLayoutRating(newValue)
        }
    }

    private var scenarioFidelityBinding: Binding<ScenarioFidelityRating> {
        Binding {
            runtime.scenarioFidelityRating
        } set: { newValue in
            runtime.setScenarioFidelityRating(newValue)
        }
    }

    private func generatedTaskRatingBinding(taskId: String) -> Binding<GeneratedTaskFidelityRating> {
        Binding {
            runtime.generatedTaskRating(taskId: taskId)
        } set: { newValue in
            runtime.setGeneratedTaskRating(newValue, taskId: taskId)
        }
    }

    private func generatedObjectRatingBinding(objectId: String) -> Binding<GeneratedObjectRating> {
        Binding {
            runtime.generatedObjectRating(objectId: objectId)
        } set: { newValue in
            runtime.setGeneratedObjectRating(newValue, objectId: objectId)
        }
    }

    private func ratingColor(_ rating: ManualEvaluationRating) -> Color {
        switch rating {
        case .yes:
            return .green
        case .partial:
            return .yellow
        case .no:
            return .red
        case .unscored:
            return .secondary
        }
    }

    private var eventLog: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Event Log")
                .font(.headline)

            if runtime.eventLog.isEmpty {
                Text("No events yet.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(runtime.eventLog) { entry in
                            VStack(alignment: .leading, spacing: 3) {
                                Label(
                                    entry.matched ? "matched" : "ignored",
                                    systemImage: entry.matched ? "checkmark.circle.fill" : "minus.circle"
                                )
                                .font(.caption)
                                .foregroundStyle(entry.matched ? .green : .secondary)
                                Text(entry.eventDescription)
                                    .font(.subheadline)
                                Text(entry.taskId)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(red: 0.09, green: 0.095, blue: 0.105).opacity(0.94))
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }

    private func taskIcon(index: Int, taskId: String) -> String {
        if runtime.completedTaskIds.contains(taskId) {
            return "checkmark.circle.fill"
        }
        if index == runtime.currentTaskIndex {
            return "circle.inset.filled"
        }
        return "circle"
    }

    private func taskColor(index: Int, taskId: String) -> Color {
        if runtime.completedTaskIds.contains(taskId) {
            return .green
        }
        if index == runtime.currentTaskIndex {
            return .blue
        }
        return .secondary
    }

    private func toggleImmersive() async {
        if isImmersiveOpen {
            await dismissImmersiveSpace()
            isImmersiveOpen = false
            return
        }

        let result = await openImmersiveSpace(id: "interactionWorldImmersive")
        switch result {
        case .opened:
            isImmersiveOpen = true
            openError = nil
        case .error:
            openError = "Could not open the interaction world immersive space."
        case .userCancelled:
            openError = "Opening the immersive space was cancelled."
        @unknown default:
            openError = "Unknown immersive space result."
        }
    }

    private func generateCafePlan() async {
        isGenerating = true
        generationError = nil
        generationResult = nil
        generationLogURL = nil

        do {
            let result = try await generator.generatePlan(for: CafeCounterDemoPlan.scenario)
            generationResult = result
            generationLogURL = try? writeGenerationLog(result)

            if let plan = result.plan {
                runtime.load(plan)
            }
        } catch {
            generationError = error.localizedDescription
        }

        isGenerating = false
    }

    private func writeGenerationLog(_ result: GenerationResult) throws -> URL {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "interaction_world_generation_\(result.scenario.id)_\(Int(Date().timeIntervalSince1970)).json"
        let url = directory.appendingPathComponent(fileName)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(result)
        try data.write(to: url, options: [.atomic])

        return url
    }
}

struct InteractionWorldImmersiveView: View {
    @EnvironmentObject private var runtime: InteractionWorldRuntime
    @StateObject private var sceneManager = InteractionWorldSceneManager()

    var body: some View {
        RealityView { content in
            sceneManager.configure(plan: runtime.plan)
            content.add(sceneManager.rootEntity)
        } update: { _ in
            sceneManager.configure(plan: runtime.plan)
        }
        .gesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    sceneManager.handleSelect(entity: value.entity, runtime: runtime)
                }
        )
        .simultaneousGesture(
            DragGesture()
                .targetedToAnyEntity()
                .onChanged { value in
                    sceneManager.handleDrag(entity: value.entity, value: value, runtime: runtime)
                }
                .onEnded { value in
                    sceneManager.handleDragEnd(entity: value.entity, runtime: runtime)
                }
        )
    }
}

@MainActor
final class InteractionWorldSceneManager: ObservableObject {
    let rootEntity = Entity()

    private var hasConfigured = false
    private var plan: InteractionWorldPlan?
    private var entitiesById: [String: ModelEntity] = [:]
    private var specsById: [String: WorldObjectSpec] = [:]
    private var dragStartPositions: [String: SIMD3<Float>] = [:]

    func configure(plan: InteractionWorldPlan) {
        guard !hasConfigured || self.plan?.id != plan.id else { return }

        self.plan = plan
        rootEntity.children.removeAll()
        entitiesById = [:]
        specsById = Dictionary(uniqueKeysWithValues: plan.objects.map { ($0.id, $0) })
        dragStartPositions = [:]

        for object in plan.objects {
            let entity = makeEntity(for: object)
            rootEntity.addChild(entity)
            entitiesById[object.id] = entity
            addLabel(object.displayName, to: entity, yOffset: object.size.y + 0.035)
        }

        hasConfigured = true
    }

    func handleSelect(entity: Entity, runtime: InteractionWorldRuntime) {
        let objectId = normalizedObjectId(for: entity)
        guard let objectId else { return }

        if case .gesture(.point, let targetId) = runtime.currentTask?.expectedInteraction,
           targetId == objectId {
            runtime.process(.gesture(.point, targetId: objectId))
        } else {
            runtime.process(.select(objectId: objectId))
        }
    }

    func handleDrag(
        entity: Entity,
        value: EntityTargetValue<DragGesture.Value>,
        runtime: InteractionWorldRuntime
    ) {
        guard let objectId = normalizedObjectId(for: entity),
              let modelEntity = entitiesById[objectId],
              isDraggable(objectId: objectId, runtime: runtime) else { return }

        if dragStartPositions[objectId] == nil {
            dragStartPositions[objectId] = modelEntity.position
            runtime.process(.dragStarted(objectId: objectId))
        }

        guard let start = dragStartPositions[objectId] else { return }

        let translation = value.convert(value.translation3D, from: .local, to: .scene)
        modelEntity.position = [
            start.x + Float(translation.x),
            max(0.05, start.y + Float(translation.y)),
            start.z + Float(translation.z)
        ]
    }

    func handleDragEnd(entity: Entity, runtime: InteractionWorldRuntime) {
        guard let objectId = normalizedObjectId(for: entity),
              let modelEntity = entitiesById[objectId],
              isDraggable(objectId: objectId, runtime: runtime) else { return }

        let targetId = placementTarget(for: modelEntity.position, objectId: objectId, runtime: runtime)

        if let targetId, let target = entitiesById[targetId] {
            let objectHeight = specsById[objectId]?.size.y ?? 0.08
            let targetHeight = specsById[targetId]?.size.y ?? 0.02
            modelEntity.position = [
                target.position.x,
                target.position.y + (targetHeight / 2) + (objectHeight / 2) + 0.01,
                target.position.z
            ]
        }

        runtime.process(.placed(objectId: objectId, targetId: targetId))
        dragStartPositions[objectId] = nil
    }

    private func isDraggable(objectId: String, runtime: InteractionWorldRuntime) -> Bool {
        switch runtime.currentTask?.expectedInteraction {
        case .drag(let expectedObjectId):
            return expectedObjectId == objectId
        case .place(let expectedObjectId, _):
            return expectedObjectId == objectId
        default:
            return false
        }
    }

    private func placementTarget(
        for position: SIMD3<Float>,
        objectId: String,
        runtime: InteractionWorldRuntime
    ) -> String? {
        guard case .place(let expectedObjectId, let targetId) = runtime.currentTask?.expectedInteraction,
              expectedObjectId == objectId,
              let target = entitiesById[targetId] else { return nil }

        let dx = position.x - target.position.x
        let dz = position.z - target.position.z
        let distance = sqrt(dx * dx + dz * dz)
        let targetSize = specsById[targetId]?.size ?? [0.18, 0.08, 0.18]
        let threshold = max(0.18, max(targetSize.x, targetSize.z) * 0.75)
        return distance < threshold ? targetId : nil
    }

    private func makeEntity(for object: WorldObjectSpec) -> ModelEntity {
        let material = SimpleMaterial(color: object.color.uiColor, isMetallic: false)
        let mesh: MeshResource

        switch object.kind {
        case .cup:
            mesh = .generateCylinder(height: object.size.y, radius: object.size.x / 2)
        case .generic(let category):
            mesh = genericMesh(for: category, size: object.size)
        case .npcMarker:
            mesh = .generateBox(width: object.size.x, height: object.size.y, depth: object.size.z)
        default:
            mesh = .generateBox(width: object.size.x, height: object.size.y, depth: object.size.z)
        }

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = object.id
        entity.position = object.position

        if object.isInteractive {
            entity.generateCollisionShapes(recursive: true)
            entity.components.set(InputTargetComponent())
        }

        return entity
    }

    private func genericMesh(for category: String, size: SIMD3<Float>) -> MeshResource {
        switch category {
        case "container":
            return .generateCylinder(height: size.y, radius: max(size.x, size.z) / 2)
        case "flatSurface":
            return .generateBox(width: size.x, height: min(size.y, 0.04), depth: size.z)
        case "uprightObject":
            return .generateBox(width: size.x, height: max(size.y, size.x), depth: size.z)
        case "marker":
            return .generateBox(width: size.x, height: size.y, depth: min(size.z, 0.05))
        case "smallObject":
            fallthrough
        default:
            return .generateBox(width: size.x, height: size.y, depth: size.z)
        }
    }

    private func addLabel(_ text: String, to entity: ModelEntity, yOffset: Float) {
        let mesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.002,
            font: .systemFont(ofSize: 0.035),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byWordWrapping
        )
        let material = SimpleMaterial(color: .white, isMetallic: false)
        let label = ModelEntity(mesh: mesh, materials: [material])
        label.name = "\(entity.name)_label"
        label.position = [-0.06, yOffset, 0]
        entity.addChild(label)
    }

    private func normalizedObjectId(for entity: Entity) -> String? {
        if entitiesById[entity.name] != nil {
            return entity.name
        }

        var parent = entity.parent
        while let current = parent {
            if entitiesById[current.name] != nil {
                return current.name
            }
            parent = current.parent
        }

        return nil
    }
}

extension InteractionKind {
    var displayDescription: String {
        switch self {
        case .indicate(let objectId):
            return "indicate \(objectId)"
        case .tap(let objectId):
            return "tap \(objectId)"
        case .drag(let objectId):
            return "drag \(objectId)"
        case .place(let objectId, let targetId):
            return "place \(objectId) on \(targetId)"
        case .gesture(let gesture, let targetId):
            if let targetId {
                return "\(gesture.rawValue) at \(targetId)"
            }
            return gesture.rawValue
        }
    }
}

extension GenerationOutcome {
    var shortDescription: String {
        switch self {
        case .success:
            return "success"
        case .jsonParseError(let message):
            return "JSON parse error: \(message)"
        case .schemaValidationError(let message):
            return "schema error: \(message)"
        case .planValidationError(let error):
            return "validation error: \(error.localizedDescription)"
        case .llmCallError(let message):
            return "LLM error: \(message)"
        }
    }
}

extension WorldObjectColor {
    var uiColor: UIColor {
        switch self {
        case .brown:
            return .brown
        case .red:
            return .systemRed
        case .blue:
            return .systemBlue
        case .cyan:
            return .cyan
        case .yellow:
            return .systemYellow
        case .green:
            return .systemGreen
        case .gray:
            return .systemGray
        case .purple:
            return .systemPurple
        }
    }
}

#Preview(windowStyle: .automatic) {
    InteractionWorldTestView()
        .environmentObject(InteractionWorldRuntime())
}
