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
