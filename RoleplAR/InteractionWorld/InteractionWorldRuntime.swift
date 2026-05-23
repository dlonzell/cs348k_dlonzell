import Foundation

@MainActor
final class InteractionWorldRuntime: ObservableObject {
    @Published private(set) var plan: InteractionWorldPlan
    @Published private(set) var currentTaskIndex = 0
    @Published private(set) var completedTaskIds: [String] = []
    @Published private(set) var eventLog: [InteractionLogEntry] = []
    @Published private(set) var manualRatings: [String: [ManualEvaluationMetric: ManualEvaluationRating]] = [:]
    @Published private(set) var generatedTaskRatings: [String: GeneratedTaskFidelityRating] = [:]
    @Published private(set) var generatedObjectRatings: [String: GeneratedObjectRating] = [:]
    @Published private(set) var scenarioLayoutRating: ScenarioLayoutRating = .unscored
    @Published private(set) var scenarioFidelityRating: ScenarioFidelityRating = .unscored

    static let supportedInteractions: Set<InteractionSupportKind> = [
        .indicate,
        .tap,
        .drag,
        .place,
        .gesture
    ]

    init(plan: InteractionWorldPlan = CafeCounterDemoPlan.plan) {
        self.plan = plan
    }

    var currentTask: InteractionTask? {
        guard currentTaskIndex < plan.tasks.count else { return nil }
        return plan.tasks[currentTaskIndex]
    }

    var isComplete: Bool {
        completedTaskIds.count == plan.tasks.count
    }

    var progressText: String {
        "\(completedTaskIds.count)/\(plan.tasks.count)"
    }

    var manualEvaluationTotal: Int {
        plan.tasks.count * ManualEvaluationMetric.allCases.count
    }

    var manualEvaluationAnswered: Int {
        manualRatings.values.reduce(0) { partialResult, ratings in
            partialResult + ratings.values.filter { $0 != .unscored }.count
        }
    }

    var manualEvaluationYesCount: Int {
        manualRatings.values.reduce(0) { partialResult, ratings in
            partialResult + ratings.values.filter { $0 == .yes }.count
        }
    }

    var manualEvaluationSummary: String {
        "\(manualEvaluationAnswered)/\(manualEvaluationTotal)"
    }

    func reset() {
        currentTaskIndex = 0
        completedTaskIds = []
        eventLog = []
        manualRatings = [:]
        generatedTaskRatings = [:]
        generatedObjectRatings = [:]
        scenarioLayoutRating = .unscored
        scenarioFidelityRating = .unscored
    }

    func load(_ plan: InteractionWorldPlan) {
        self.plan = plan
        reset()
    }

    @discardableResult
    func process(_ event: InteractionEvent) -> Bool {
        guard let task = currentTask else { return false }

        let matched = task.expectedInteraction.matches(event)
        eventLog.insert(
            InteractionLogEntry(
                timestamp: Date(),
                taskId: task.id,
                eventDescription: event.displayDescription,
                matched: matched
            ),
            at: 0
        )

        if matched {
            completedTaskIds.append(task.id)
            currentTaskIndex += 1
        }

        return matched
    }

    func evaluate() -> InteractionEvaluationResult {
        let handlerCoveragePassed = plan.tasks.filter {
            Self.supportedInteractions.contains($0.expectedInteraction.supportKind)
        }.count

        let firstFailedTaskId = plan.tasks.first { !completedTaskIds.contains($0.id) }?.id

        return InteractionEvaluationResult(
            objectCoveragePassed: plan.objects.count,
            objectCoverageTotal: plan.objects.count,
            handlerCoveragePassed: handlerCoveragePassed,
            handlerCoverageTotal: plan.tasks.count,
            completedTasks: completedTaskIds.count,
            totalTasks: plan.tasks.count,
            firstFailedTaskId: firstFailedTaskId
        )
    }

    func manualEvaluationSnapshot() -> ManualEvaluationSnapshot {
        let objectRatings = generatedObjectRatings
            .map { GeneratedObjectRatingSnapshot(objectId: $0.key, rating: $0.value) }
            .sorted { $0.objectId < $1.objectId }

        let taskFidelityRatings = generatedTaskRatings
            .map { GeneratedTaskFidelitySnapshot(taskId: $0.key, rating: $0.value) }
            .sorted { $0.taskId < $1.taskId }

        let taskMetricRatings = manualRatings.flatMap { taskId, ratings in
            ratings.map { metric, rating in
                TaskMetricRatingSnapshot(taskId: taskId, metric: metric, rating: rating)
            }
        }
        .sorted { left, right in
            if left.taskId == right.taskId {
                return left.metric.rawValue < right.metric.rawValue
            }
            return left.taskId < right.taskId
        }

        return ManualEvaluationSnapshot(
            scenarioLayoutRating: scenarioLayoutRating,
            scenarioFidelityRating: scenarioFidelityRating,
            generatedObjectRatings: objectRatings,
            generatedTaskRatings: taskFidelityRatings,
            taskMetricRatings: taskMetricRatings,
            answeredCount: manualEvaluationAnswered,
            totalCount: manualEvaluationTotal,
            yesCount: manualEvaluationYesCount
        )
    }

    func eventLogSnapshot() -> [InteractionEventLogSnapshot] {
        eventLog.map {
            InteractionEventLogSnapshot(
                timestamp: $0.timestamp,
                taskId: $0.taskId,
                eventDescription: $0.eventDescription,
                matched: $0.matched
            )
        }
    }

    func manualRating(
        taskId: String,
        metric: ManualEvaluationMetric
    ) -> ManualEvaluationRating {
        manualRatings[taskId]?[metric] ?? .unscored
    }

    func setManualRating(
        _ rating: ManualEvaluationRating,
        taskId: String,
        metric: ManualEvaluationMetric
    ) {
        if rating == .unscored {
            manualRatings[taskId]?[metric] = nil
            if manualRatings[taskId]?.isEmpty == true {
                manualRatings[taskId] = nil
            }
            return
        }

        var ratingsForTask = manualRatings[taskId] ?? [:]
        ratingsForTask[metric] = rating
        manualRatings[taskId] = ratingsForTask
    }

    func generatedTaskRating(taskId: String) -> GeneratedTaskFidelityRating {
        generatedTaskRatings[taskId] ?? .unscored
    }

    func setGeneratedTaskRating(_ rating: GeneratedTaskFidelityRating, taskId: String) {
        if rating == .unscored {
            generatedTaskRatings[taskId] = nil
        } else {
            generatedTaskRatings[taskId] = rating
        }
    }

    func generatedObjectRating(objectId: String) -> GeneratedObjectRating {
        generatedObjectRatings[objectId] ?? .unscored
    }

    func setGeneratedObjectRating(_ rating: GeneratedObjectRating, objectId: String) {
        if rating == .unscored {
            generatedObjectRatings[objectId] = nil
        } else {
            generatedObjectRatings[objectId] = rating
        }
    }

    func setScenarioLayoutRating(_ rating: ScenarioLayoutRating) {
        scenarioLayoutRating = rating
    }

    func setScenarioFidelityRating(_ rating: ScenarioFidelityRating) {
        scenarioFidelityRating = rating
    }

    static func validate(_ plan: InteractionWorldPlan) throws {
        var objectIds = Set<String>()
        for object in plan.objects {
            guard objectIds.insert(object.id).inserted else {
                throw InteractionWorldValidationError.duplicateObjectId(object.id)
            }
        }

        var taskIds = Set<String>()
        for task in plan.tasks {
            guard taskIds.insert(task.id).inserted else {
                throw InteractionWorldValidationError.duplicateTaskId(task.id)
            }

            for objectId in task.requiredObjectIds where !objectIds.contains(objectId) {
                throw InteractionWorldValidationError.taskReferencesMissingObject(
                    taskId: task.id,
                    objectId: objectId
                )
            }

            guard supportedInteractions.contains(task.expectedInteraction.supportKind) else {
                throw InteractionWorldValidationError.unsupportedInteraction(
                    taskId: task.id,
                    interaction: task.expectedInteraction
                )
            }
        }
    }
}

enum InteractionSupportKind: Hashable {
    case indicate
    case tap
    case drag
    case place
    case gesture
}

extension InteractionKind {
    var supportKind: InteractionSupportKind {
        switch self {
        case .indicate:
            return .indicate
        case .tap:
            return .tap
        case .drag:
            return .drag
        case .place:
            return .place
        case .gesture:
            return .gesture
        }
    }

    func matches(_ event: InteractionEvent) -> Bool {
        switch (self, event) {
        case (.indicate(let expectedId), .select(let objectId)):
            return expectedId == objectId
        case (.tap(let expectedId), .select(let objectId)):
            return expectedId == objectId
        case (.drag(let expectedId), .dragStarted(let objectId)):
            return expectedId == objectId
        case (.place(let expectedObjectId, let expectedTargetId), .placed(let objectId, let targetId)):
            return expectedObjectId == objectId && expectedTargetId == targetId
        case (.gesture(let expectedGesture, let expectedTargetId), .gesture(let gesture, let targetId)):
            return expectedGesture == gesture && expectedTargetId == targetId
        default:
            return false
        }
    }
}

extension InteractionEvent {
    var displayDescription: String {
        switch self {
        case .select(let objectId):
            return "select \(objectId)"
        case .dragStarted(let objectId):
            return "drag \(objectId)"
        case .placed(let objectId, let targetId):
            return "place \(objectId) on \(targetId ?? "unknown")"
        case .gesture(let gesture, let targetId):
            if let targetId {
                return "\(gesture.rawValue) at \(targetId)"
            }
            return gesture.rawValue
        }
    }
}
