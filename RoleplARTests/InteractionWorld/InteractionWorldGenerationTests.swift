import XCTest
@testable import RoleplAR

@MainActor
final class InteractionWorldGenerationTests: XCTestCase {
    func testGeneratorReturnsValidPlanForSuccessfulResponses() async throws {
        let generator = InteractionWorldGenerator(
            client: StubLLMClient(responses: [
                .success(Self.objectsJSON),
                .success(Self.tasksJSON)
            ])
        )

        let result = try await generator.generatePlan(for: CafeCounterDemoPlan.scenario)

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.attempts.count, 1)
        XCTAssertEqual(result.plan?.objects.count, 2)
        XCTAssertEqual(result.plan?.tasks.count, 1)
        XCTAssertEqual(result.attempts[0].outcome, .success)
    }

    func testGeneratorRetriesMalformedJSONResponse() async throws {
        let generator = InteractionWorldGenerator(
            client: StubLLMClient(responses: [
                .success("{ not json"),
                .success(Self.objectsJSON),
                .success(Self.tasksJSON)
            ])
        )

        let result = try await generator.generatePlan(for: CafeCounterDemoPlan.scenario)

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.attempts.count, 2)

        guard case .jsonParseError = result.attempts[0].outcome else {
            return XCTFail("Expected first attempt to record a JSON parse error.")
        }
    }

    func testGeneratorReturnsFailureAfterAttemptLimit() async throws {
        let generator = InteractionWorldGenerator(
            client: StubLLMClient(responses: [
                .success("{ not json"),
                .success("{ still not json")
            ]),
            maxAttempts: 2
        )

        let result = try await generator.generatePlan(for: CafeCounterDemoPlan.scenario)

        XCTAssertFalse(result.succeeded)
        XCTAssertNil(result.plan)
        XCTAssertEqual(result.attempts.count, 2)
    }

    func testPromptConstructionContainsScenarioAndSchema() {
        let objectPrompt = buildObjectGenerationPrompt(scenario: CafeCounterDemoPlan.scenario)
        XCTAssertTrue(objectPrompt.contains(CafeCounterDemoPlan.scenario.id))
        XCTAssertTrue(objectPrompt.contains("targetInteractions"))
        XCTAssertTrue(objectPrompt.contains("container|flatSurface|uprightObject|marker|smallObject"))

        let taskPrompt = buildTaskGenerationPrompt(
            scenario: CafeCounterDemoPlan.scenario,
            objects: CafeCounterDemoPlan.plan.objects
        )
        XCTAssertTrue(taskPrompt.contains("Primitive vocabulary"))
        XCTAssertTrue(taskPrompt.contains("expectedInteraction"))
        XCTAssertTrue(taskPrompt.contains("coffee_cup"))
    }

    func testGenerationEvaluationClassifiesValidationErrors() {
        let attempt = GenerationAttempt(
            attemptNumber: 1,
            stage: .validation,
            durationSeconds: 0.5,
            outcome: .planValidationError(
                .taskReferencesMissingObject(taskId: "tap_missing", objectId: "missing")
            ),
            rawObjectsJSON: Self.objectsJSON,
            rawTasksJSON: Self.tasksJSON,
            validationError: .taskReferencesMissingObject(taskId: "tap_missing", objectId: "missing")
        )

        let result = GenerationResult(
            scenario: CafeCounterDemoPlan.scenario,
            plan: nil,
            attempts: [attempt],
            totalGenerationTimeSeconds: 0.5
        )

        let evaluation = GenerationEvaluator.evaluate(result)
        XCTAssertFalse(evaluation.succeeded)
        XCTAssertEqual(evaluation.primaryFailureMode, .structuralMissingReference)
        XCTAssertFalse(evaluation.step4Validation.succeeded)
    }

    private static let objectsJSON = """
    {
      "objects": [
        {
          "id": "menu",
          "displayName": "Menu",
          "description": "A small cafe menu",
          "kind": { "type": "menu" },
          "position": [-0.2, 0.7, -0.9],
          "size": [0.2, 0.02, 0.3],
          "color": "red",
          "isInteractive": true
        },
        {
          "id": "ramen_bowl",
          "displayName": "Ramen Bowl",
          "description": "A ceramic ramen bowl",
          "kind": { "type": "generic", "category": "container" },
          "position": [0.1, 0.72, -0.8],
          "size": [0.16, 0.08, 0.16],
          "color": "yellow",
          "isInteractive": true
        }
      ]
    }
    """

    private static let tasksJSON = """
    {
      "tasks": [
        {
          "id": "tap_menu",
          "instruction": "Tap the menu.",
          "requiredObjectIds": ["menu"],
          "expectedInteraction": { "type": "tap", "objectId": "menu" }
        }
      ]
    }
    """
}

private actor StubLLMClient: InteractionWorldLLMClient {
    private var responses: [Result<String, Error>]

    init(responses: [Result<String, Error>]) {
        self.responses = responses
    }

    func completeJSON(prompt: String) async throws -> String {
        guard !responses.isEmpty else {
            throw StubLLMError.noResponse
        }

        let response = responses.removeFirst()
        switch response {
        case .success(let json):
            return json
        case .failure(let error):
            throw error
        }
    }
}

private enum StubLLMError: LocalizedError {
    case noResponse

    var errorDescription: String? {
        "No stubbed LLM response available."
    }
}
