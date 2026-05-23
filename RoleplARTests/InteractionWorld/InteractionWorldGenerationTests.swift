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
        XCTAssertTrue(objectPrompt.contains("expectedObjectCategories"))
        XCTAssertTrue(objectPrompt.contains("container|flatSurface|uprightObject|marker|smallObject"))

        let taskPrompt = buildTaskGenerationPrompt(
            scenario: CafeCounterDemoPlan.scenario,
            objects: CafeCounterDemoPlan.plan.objects
        )
        XCTAssertTrue(taskPrompt.contains("Primitive vocabulary"))
        XCTAssertTrue(taskPrompt.contains("expectedInteraction"))
        XCTAssertTrue(taskPrompt.contains("coffee_cup"))
    }

    func testTaskDecoderAcceptsAllSupportedInteractionKinds() throws {
        let tasks = try InteractionWorldGenerator.decodeTasks(from: Self.allInteractionKindsTasksJSON)

        XCTAssertEqual(tasks.count, 5)
        XCTAssertEqual(tasks[0].expectedInteraction, .indicate(objectId: "menu"))
        XCTAssertEqual(tasks[1].expectedInteraction, .tap(objectId: "card_reader"))
        XCTAssertEqual(tasks[2].expectedInteraction, .drag(objectId: "coffee_cup"))
        XCTAssertEqual(tasks[3].expectedInteraction, .place(objectId: "coffee_cup", targetId: "tray"))
        XCTAssertEqual(tasks[4].expectedInteraction, .gesture(.openPalm, targetId: nil))
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

    func testRunLogEncodesRuntimeEvaluationAndManualRatings() throws {
        let result = GenerationResult(
            scenario: CafeCounterDemoPlan.scenario,
            plan: CafeCounterDemoPlan.plan,
            attempts: [
                GenerationAttempt(
                    attemptNumber: 1,
                    stage: .fullPipeline,
                    durationSeconds: 0.25,
                    outcome: .success,
                    rawObjectsJSON: Self.objectsJSON,
                    rawTasksJSON: Self.tasksJSON,
                    validationError: nil
                )
            ],
            totalGenerationTimeSeconds: 0.25
        )
        let runtime = InteractionWorldRuntime(plan: CafeCounterDemoPlan.plan)
        runtime.setManualRating(.yes, taskId: "wave_to_barista", metric: .objectRealization)
        runtime.setGeneratedObjectRating(.expected, objectId: "counter")
        runtime.setGeneratedTaskRating(.faithful, taskId: "wave_to_barista")
        runtime.setScenarioLayoutRating(.plausible)
        runtime.setScenarioFidelityRating(.faithful)

        let log = InteractionWorldRunLogFactory.make(
            result: result,
            runtime: runtime,
            exportedAt: Date(timeIntervalSince1970: 1)
        )
        let data = try JSONEncoder().encode(log)
        let decoded = try JSONDecoder().decode(InteractionWorldRunLog.self, from: data)

        XCTAssertEqual(decoded.scenario.id, CafeCounterDemoPlan.scenario.id)
        XCTAssertEqual(decoded.generationEvaluation.succeeded, true)
        XCTAssertEqual(decoded.loadedPlan?.id, CafeCounterDemoPlan.plan.id)
        XCTAssertEqual(decoded.runtimeEvaluation?.completionSummary, "0/5")
        XCTAssertEqual(decoded.manualEvaluation?.answeredCount, 1)
        XCTAssertEqual(decoded.manualEvaluation?.generatedObjectRatings.first?.rating, .expected)
        XCTAssertEqual(decoded.manualEvaluation?.generatedTaskRatings.first?.rating, .faithful)
    }

    func testSAM3DReconcilerAttachesVisualAssetAndKeepsTasks() throws {
        let remoteURL = URL(string: "https://example.com/cup.ply")!
        let localURL = URL(fileURLWithPath: "/tmp/cup.ply")
        let response = SAM3DSceneRealizationResponse(
            objects: [
                SAM3DRealizedObject(
                    objectId: "coffee_cup",
                    status: .realized,
                    visualFormat: .gaussianSplatPLY,
                    assetURL: remoteURL,
                    position: [0.25, 0.8, -0.6],
                    size: [0.12, 0.18, 0.12],
                    proxyShape: SAM3DProxyShapeSpec(
                        type: "cylinder",
                        size: [0.12, 0.18, 0.12]
                    ),
                    notes: "Segmented and reconstructed"
                )
            ]
        )
        let cachedAsset = SAM3DCachedAsset(
            objectId: "coffee_cup",
            remoteURL: remoteURL,
            localURL: localURL
        )

        let reconciledPlan = SAM3DSceneReconciler.reconcile(
            plan: CafeCounterDemoPlan.plan,
            response: response,
            cachedAssets: [cachedAsset]
        )
        let cup = try XCTUnwrap(reconciledPlan.objects.first { $0.id == "coffee_cup" })

        XCTAssertEqual(reconciledPlan.tasks, CafeCounterDemoPlan.plan.tasks)
        XCTAssertEqual(cup.position, [0.25, 0.8, -0.6])
        XCTAssertEqual(cup.size, [0.12, 0.18, 0.12])
        XCTAssertEqual(cup.visualAsset?.format, .gaussianSplatPLY)
        XCTAssertEqual(cup.visualAsset?.source, .sam3D)
        XCTAssertEqual(cup.visualAsset?.status, .realized)
        XCTAssertEqual(cup.visualAsset?.remoteURL, remoteURL)
        XCTAssertEqual(cup.visualAsset?.localURL, localURL)
    }

    func testSAM3DRealizationRequestRoundTrips() throws {
        let request = SAM3DSceneRealizationRequest(
            scenario: CafeCounterDemoPlan.scenario,
            plan: CafeCounterDemoPlan.plan
        )
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(SAM3DSceneRealizationRequest.self, from: data)

        XCTAssertEqual(decoded.scenario.id, CafeCounterDemoPlan.scenario.id)
        XCTAssertEqual(decoded.plan.id, CafeCounterDemoPlan.plan.id)
    }

    func testValidationRejectsGeneratedTaskMissingObjectReference() {
        let plan = InteractionWorldPlan(
            id: "bad_generated_plan",
            scenario: CafeCounterDemoPlan.scenario,
            objects: [
                WorldObjectSpec(
                    id: "menu",
                    displayName: "Menu",
                    description: "A small cafe menu",
                    kind: .menu,
                    position: [0, 0.7, -0.9],
                    size: [0.2, 0.02, 0.3],
                    color: .red,
                    isInteractive: true
                )
            ],
            tasks: [
                InteractionTask(
                    id: "tap_missing",
                    instruction: "Tap the missing object.",
                    requiredObjectIds: ["missing"],
                    expectedInteraction: .tap(objectId: "missing")
                )
            ]
        )

        XCTAssertThrowsError(try InteractionWorldRuntime.validate(plan)) { error in
            XCTAssertEqual(
                error as? InteractionWorldValidationError,
                .taskReferencesMissingObject(taskId: "tap_missing", objectId: "missing")
            )
        }
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

    private static let allInteractionKindsTasksJSON = """
    {
      "tasks": [
        {
          "id": "indicate_menu",
          "instruction": "Indicate the menu.",
          "requiredObjectIds": ["menu"],
          "expectedInteraction": { "type": "indicate", "objectId": "menu" }
        },
        {
          "id": "tap_reader",
          "instruction": "Tap the card reader.",
          "requiredObjectIds": ["card_reader"],
          "expectedInteraction": { "type": "tap", "objectId": "card_reader" }
        },
        {
          "id": "drag_cup",
          "instruction": "Drag the cup.",
          "requiredObjectIds": ["coffee_cup"],
          "expectedInteraction": { "type": "drag", "objectId": "coffee_cup" }
        },
        {
          "id": "place_cup",
          "instruction": "Place the cup on the tray.",
          "requiredObjectIds": ["coffee_cup", "tray"],
          "expectedInteraction": { "type": "place", "objectId": "coffee_cup", "targetId": "tray" }
        },
        {
          "id": "open_palm",
          "instruction": "Show an open palm.",
          "requiredObjectIds": [],
          "expectedInteraction": { "type": "gesture", "gesture": "openPalm" }
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
