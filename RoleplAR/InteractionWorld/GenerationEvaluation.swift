import Foundation

struct GenerationEvaluation: Codable, Equatable {
    let scenarioId: String
    let succeeded: Bool
    let attemptCount: Int
    let totalTimeSeconds: TimeInterval
    let step1ObjectGeneration: StageEvaluation
    let step3TaskGeneration: StageEvaluation
    let step4Validation: ValidationEvaluation
    let step6Runtime: RuntimeEvaluation?
    let primaryFailureMode: FailureMode?
}

struct StageEvaluation: Codable, Equatable {
    let succeeded: Bool
    let manualNotes: String?
}

struct ValidationEvaluation: Codable, Equatable {
    let succeeded: Bool
    let validationError: InteractionWorldValidationError?
    let manualNotes: String?
}

struct RuntimeEvaluation: Codable, Equatable {
    let completedTasks: Int
    let totalTasks: Int
    let manualNotes: String?
}

struct InteractionWorldRunLog: Codable, Equatable {
    let exportedAt: Date
    let scenario: ScenarioCard
    let generationResult: GenerationResult
    let loadedPlan: InteractionWorldPlan?
    let layoutSummary: InteractionWorldLayoutSummary?
    let generationEvaluation: GenerationEvaluation
    let runtimeEvaluation: InteractionEvaluationResult?
    let manualEvaluation: ManualEvaluationSnapshot?
    let eventLog: [InteractionEventLogSnapshot]
}

struct SavedInteractionWorldScene: Identifiable, Equatable {
    let url: URL
    let exportedAt: Date
    let scenarioId: String
    let scenarioTitle: String
    let objectCount: Int
    let realizedObjectCount: Int

    var id: String {
        url.path
    }

    var fileName: String {
        url.lastPathComponent
    }
}

enum InteractionWorldSavedSceneStore {
    private static let directoryName = "InteractionWorldSavedScenes"

    static func defaultBaseDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func savedScenesDirectory(baseDirectory: URL = defaultBaseDirectory()) -> URL {
        baseDirectory.appendingPathComponent(directoryName, isDirectory: true)
    }

    static func write(
        _ log: InteractionWorldRunLog,
        baseDirectory: URL = defaultBaseDirectory()
    ) throws -> URL {
        let directory = savedScenesDirectory(baseDirectory: baseDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let timestamp = Int(log.exportedAt.timeIntervalSince1970)
        let fileName = "interaction_world_scene_\(log.scenario.id)_\(timestamp).json"
        let url = directory.appendingPathComponent(fileName)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(log)
        try data.write(to: url, options: [.atomic])

        return url
    }

    static func load(url: URL) throws -> InteractionWorldRunLog {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(InteractionWorldRunLog.self, from: data)
    }

    static func list(
        baseDirectory: URL = defaultBaseDirectory()
    ) throws -> [SavedInteractionWorldScene] {
        let directory = savedScenesDirectory(baseDirectory: baseDirectory)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return []
        }

        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )

        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let log = try? load(url: url) else {
                    return nil
                }
                let plan = log.loadedPlan ?? log.generationResult.plan
                let realizedObjectCount = plan?.objects.filter {
                    $0.visualAsset?.status == .realized
                }.count ?? 0
                return SavedInteractionWorldScene(
                    url: url,
                    exportedAt: log.exportedAt,
                    scenarioId: log.scenario.id,
                    scenarioTitle: log.scenario.setting,
                    objectCount: plan?.objects.count ?? 0,
                    realizedObjectCount: realizedObjectCount
                )
            }
            .sorted { lhs, rhs in
                lhs.exportedAt > rhs.exportedAt
            }
    }
}

enum FailureMode: String, Codable, CaseIterable {
    case structuralInvalidJSON
    case structuralDuplicateID
    case structuralMissingReference
    case structuralUnsupportedPrimitive
    case objectMissingRequired
    case objectHallucinated
    case objectImplausibleLayout
    case taskFalseAcceptance
    case taskFalseRejection
    case taskWrongObject
    case behavioralFailedAtRuntime
    case llmCallFailed
}

enum GenerationEvaluator {
    static func evaluate(
        _ result: GenerationResult,
        manualNotes: String? = nil,
        runtimeEvaluation: RuntimeEvaluation? = nil,
        manualFailureMode: FailureMode? = nil
    ) -> GenerationEvaluation {
        let objectGenerationSucceeded = result.succeeded || result.attempts.contains { attempt in
            attempt.rawObjectsJSON != nil && attempt.stage != .objectGeneration
        }

        let taskGenerationSucceeded = result.succeeded || result.attempts.contains { attempt in
            attempt.rawTasksJSON != nil && attempt.stage != .taskGeneration
        }

        let validationError = result.attempts.compactMap(\.validationError).last
        let validationSucceeded = result.succeeded

        return GenerationEvaluation(
            scenarioId: result.scenario.id,
            succeeded: result.succeeded,
            attemptCount: result.attempts.count,
            totalTimeSeconds: result.totalGenerationTimeSeconds,
            step1ObjectGeneration: StageEvaluation(
                succeeded: objectGenerationSucceeded,
                manualNotes: manualNotes
            ),
            step3TaskGeneration: StageEvaluation(
                succeeded: taskGenerationSucceeded,
                manualNotes: manualNotes
            ),
            step4Validation: ValidationEvaluation(
                succeeded: validationSucceeded,
                validationError: validationError,
                manualNotes: manualNotes
            ),
            step6Runtime: runtimeEvaluation,
            primaryFailureMode: manualFailureMode ?? primaryFailureMode(for: result)
        )
    }

    static func primaryFailureMode(for result: GenerationResult) -> FailureMode? {
        guard !result.succeeded else { return nil }

        for attempt in result.attempts.reversed() {
            switch attempt.outcome {
            case .success:
                continue
            case .jsonParseError, .schemaValidationError:
                return .structuralInvalidJSON
            case .llmCallError:
                return .llmCallFailed
            case .planValidationError(let error):
                return failureMode(for: error)
            }
        }

        return nil
    }

    static func failureMode(for error: InteractionWorldValidationError) -> FailureMode {
        switch error {
        case .duplicateObjectId, .duplicateTaskId:
            return .structuralDuplicateID
        case .taskReferencesMissingObject:
            return .structuralMissingReference
        case .unsupportedInteraction:
            return .structuralUnsupportedPrimitive
        }
    }
}

@MainActor
enum InteractionWorldRunLogFactory {
    static func make(
        result: GenerationResult,
        runtime: InteractionWorldRuntime?,
        exportedAt: Date = Date()
    ) -> InteractionWorldRunLog {
        let runtimeEvaluation = runtime?.evaluate()
        let runtimeSummary = runtimeEvaluation.map {
            RuntimeEvaluation(
                completedTasks: $0.completedTasks,
                totalTasks: $0.totalTasks,
                manualNotes: nil
            )
        }

        return InteractionWorldRunLog(
            exportedAt: exportedAt,
            scenario: result.scenario,
            generationResult: result,
            loadedPlan: runtime?.plan,
            layoutSummary: result.layoutSummary,
            generationEvaluation: GenerationEvaluator.evaluate(
                result,
                runtimeEvaluation: runtimeSummary
            ),
            runtimeEvaluation: runtimeEvaluation,
            manualEvaluation: runtime?.manualEvaluationSnapshot(),
            eventLog: runtime?.eventLogSnapshot() ?? []
        )
    }
}
