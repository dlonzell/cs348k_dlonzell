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
        XCTAssertEqual(result.plan?.objects.count, 3)
        XCTAssertEqual(result.plan?.tasks.count, 1)
        XCTAssertEqual(result.layoutSummary?.insertedSurfaceId, "interaction_surface")
        XCTAssertEqual(result.layoutSummary?.objectCount, 3)
        XCTAssertGreaterThan(result.layoutSummary?.relationCount ?? 0, 0)
        XCTAssertTrue(result.plan?.id.hasSuffix("_stage_layout") == true)
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

    func testObjectDecoderToleratesModelColorSynonyms() throws {
        let objects = try InteractionWorldGenerator.decodeObjects(from: Self.cafePaymentObjectsWithColorSynonymsJSON)

        XCTAssertEqual(objects.count, 2)
        XCTAssertEqual(objects[0].id, "card_reader")
        XCTAssertEqual(objects[0].color, .gray)
        XCTAssertEqual(objects[1].id, "receipt")
        XCTAssertEqual(objects[1].color, .gray)
    }

    func testLayoutSolverAddsFallbackSurfaceAndPreservesTaskReferences() throws {
        let layoutResult = InteractionWorldLayoutSolver.solve(Self.layoutProbePlan)
        let solvedPlan = layoutResult.plan

        XCTAssertEqual(layoutResult.summary.insertedSurfaceId, "interaction_surface")
        XCTAssertTrue(solvedPlan.objects.contains { $0.id == "interaction_surface" })
        XCTAssertEqual(solvedPlan.tasks, Self.layoutProbePlan.tasks)
        XCTAssertEqual(layoutResult.summary.strategy, "stage_relation_slots_v1")
        XCTAssertTrue(Self.layoutProbePlan.objects.allSatisfy { original in
            solvedPlan.objects.contains { $0.id == original.id }
        })
        XCTAssertNoThrow(try InteractionWorldRuntime.validate(solvedPlan))
    }

    func testLayoutSolverInfersHolodeckLiteRelations() throws {
        let layoutResult = InteractionWorldLayoutSolver.solve(Self.layoutProbePlan)
        let relations = layoutResult.summary.relations

        XCTAssertTrue(Self.containsRelation(relations, "shopping_basket", .rightOf, "snack_chips"))
        XCTAssertTrue(Self.containsRelation(relations, "shopping_basket", .near, "snack_chips"))
        XCTAssertTrue(Self.containsRelation(relations, "payment_terminal", .behind, "interaction_surface"))
        XCTAssertTrue(Self.containsRelation(relations, "cashier_marker", .behind, "interaction_surface"))
        XCTAssertTrue(Self.containsRelation(relations, "store_menu", .behind, "interaction_surface"))
    }

    func testLayoutSolverAssignsStableStageRoles() throws {
        let layoutResult = InteractionWorldLayoutSolver.solve(Self.layoutProbePlan)
        let summaries = Dictionary(
            uniqueKeysWithValues: layoutResult.summary.objectSummaries.map { ($0.objectId, $0) }
        )

        XCTAssertEqual(summaries["snack_chips"]?.role, "sourceObject")
        XCTAssertEqual(summaries["shopping_basket"]?.role, "targetContainer")
        XCTAssertEqual(summaries["payment_terminal"]?.role, "payment")
        XCTAssertEqual(summaries["cashier_marker"]?.role, "personMarker")
        XCTAssertEqual(summaries["store_menu"]?.role, "uprightContext")

        let snack = try XCTUnwrap(layoutResult.plan.objects.first { $0.id == "snack_chips" })
        let basket = try XCTUnwrap(layoutResult.plan.objects.first { $0.id == "shopping_basket" })
        let terminal = try XCTUnwrap(layoutResult.plan.objects.first { $0.id == "payment_terminal" })

        XCTAssertGreaterThan(snack.position.y, 0.68)
        XCTAssertGreaterThan(basket.position.x, snack.position.x)
        XCTAssertLessThan(terminal.position.z, basket.position.z)
    }

    func testLayoutSolverRecognizesVendorAndMarketStandSynonyms() throws {
        let layoutResult = InteractionWorldLayoutSolver.solve(Self.marketStandSynonymPlan)
        let summaries = Dictionary(
            uniqueKeysWithValues: layoutResult.summary.objectSummaries.map { ($0.objectId, $0) }
        )

        XCTAssertNil(layoutResult.summary.insertedSurfaceId)
        XCTAssertEqual(summaries["market_stand"]?.role, "surface")
        XCTAssertEqual(summaries["vendor_marker"]?.role, "personMarker")

        let marketStand = try XCTUnwrap(layoutResult.plan.objects.first { $0.id == "market_stand" })
        let vendor = try XCTUnwrap(layoutResult.plan.objects.first { $0.id == "vendor_marker" })

        XCTAssertGreaterThan(marketStand.size.x, 1.0)
        XCTAssertLessThan(vendor.position.z, marketStand.position.z)
        XCTAssertGreaterThan(vendor.position.y, marketStand.position.y)
    }

    func testLayoutSolverKeepsDisplayCasesAsTabletopFixtures() throws {
        let layoutResult = InteractionWorldLayoutSolver.solve(Self.displayFixturePlan)
        let summaries = Dictionary(
            uniqueKeysWithValues: layoutResult.summary.objectSummaries.map { ($0.objectId, $0) }
        )

        XCTAssertEqual(summaries["pastry_display"]?.role, "contextObject")
        XCTAssertEqual(summaries["menu"]?.role, "uprightContext")

        let counter = try XCTUnwrap(layoutResult.plan.objects.first { $0.id == "counter" })
        let pastryDisplay = try XCTUnwrap(layoutResult.plan.objects.first { $0.id == "pastry_display" })
        let menu = try XCTUnwrap(layoutResult.plan.objects.first { $0.id == "menu" })
        let counterTopY = counter.position.y + counter.size.y / 2

        XCTAssertEqual(
            pastryDisplay.position.y,
            counterTopY + pastryDisplay.size.y / 2 + 0.015,
            accuracy: 0.001
        )
        XCTAssertLessThan(menu.position.z, pastryDisplay.position.z)
    }

    func testLayoutSolverBuildsAssetCardsAndKeepsSupportedObjectsOnCounter() throws {
        let layoutResult = InteractionWorldLayoutSolver.solve(CafeCounterDemoPlan.plan)
        let counter = try XCTUnwrap(layoutResult.plan.objects.first { $0.id == "counter" })
        let counterTopY = counter.position.y + counter.size.y / 2

        let supportedIds = ["menu", "pastry_case", "coffee_cup", "tray", "card_reader"]
        for objectId in supportedIds {
            let object = try XCTUnwrap(layoutResult.plan.objects.first { $0.id == objectId })
            let card = try XCTUnwrap(object.assetCard)
            let xLimit = counter.size.x / 2 - object.size.x / 2 + 0.001
            let zLimit = counter.size.z / 2 - object.size.z / 2 + 0.001

            XCTAssertEqual(card.supportSurfaceId, "counter")
            XCTAssertEqual(object.position.y, counterTopY + object.size.y / 2 + 0.015, accuracy: 0.001)
            XCTAssertLessThanOrEqual(abs(object.position.x - counter.position.x), xLimit)
            XCTAssertLessThanOrEqual(abs(object.position.z - counter.position.z), zLimit)
        }

        XCTAssertEqual(layoutResult.plan.objects.first { $0.id == "menu" }?.assetCard?.assetKind, .menu)
        XCTAssertEqual(layoutResult.plan.objects.first { $0.id == "menu" }?.assetCard?.orientationHint, .uprightFacingLearner)
        XCTAssertEqual(layoutResult.plan.objects.first { $0.id == "pastry_case" }?.assetCard?.assetKind, .displayFixture)
        XCTAssertEqual(layoutResult.plan.objects.first { $0.id == "pastry_case" }?.assetCard?.orientationHint, .tabletopFlat)
        XCTAssertEqual(layoutResult.plan.objects.first { $0.id == "coffee_cup" }?.assetCard?.assetKind, .cup)
        XCTAssertEqual(layoutResult.plan.objects.first { $0.id == "coffee_cup" }?.assetCard?.orientationHint, .openTopUpright)
        XCTAssertEqual(layoutResult.plan.objects.first { $0.id == "tray" }?.assetCard?.assetKind, .tray)
        XCTAssertEqual(layoutResult.plan.objects.first { $0.id == "tray" }?.assetCard?.orientationHint, .shallowTray)
        XCTAssertEqual(layoutResult.plan.objects.first { $0.id == "card_reader" }?.assetCard?.assetKind, .paymentDevice)
        XCTAssertEqual(layoutResult.plan.objects.first { $0.id == "card_reader" }?.assetCard?.orientationHint, .tabletopFlat)

        let barista = try XCTUnwrap(layoutResult.plan.objects.first { $0.id == "barista_marker" })
        XCTAssertEqual(barista.assetCard?.layoutRole, .personMarker)
        XCTAssertNil(barista.assetCard?.supportSurfaceId)
        XCTAssertEqual(barista.assetCard?.orientationHint, .uprightFacingLearner)
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

    func testSavedSceneStoreWritesListsAndLoadsRunLogs() throws {
        let tempDirectory = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let result = GenerationResult(
            scenario: CafeCounterDemoPlan.scenario,
            plan: CafeCounterDemoPlan.plan,
            attempts: [
                GenerationAttempt(
                    attemptNumber: 1,
                    stage: .fullPipeline,
                    durationSeconds: 0.2,
                    outcome: .success,
                    rawObjectsJSON: nil,
                    rawTasksJSON: nil,
                    validationError: nil
                )
            ],
            totalGenerationTimeSeconds: 0.2
        )
        let log = InteractionWorldRunLogFactory.make(
            result: result,
            runtime: nil,
            exportedAt: Date(timeIntervalSince1970: 2)
        )

        let url = try InteractionWorldSavedSceneStore.write(
            log,
            baseDirectory: tempDirectory
        )
        let scenes = try InteractionWorldSavedSceneStore.list(
            baseDirectory: tempDirectory
        )
        let loaded = try InteractionWorldSavedSceneStore.load(url: url)

        XCTAssertEqual(scenes.count, 1)
        XCTAssertEqual(scenes.first?.scenarioId, CafeCounterDemoPlan.scenario.id)
        XCTAssertEqual(scenes.first?.objectCount, CafeCounterDemoPlan.plan.objects.count)
        XCTAssertEqual(loaded.scenario.id, CafeCounterDemoPlan.scenario.id)
        XCTAssertEqual(loaded.generationResult.plan?.id, CafeCounterDemoPlan.plan.id)
    }

    func testSAM3DReconcilerAttachesVisualAssetAndKeepsTasks() throws {
        let remoteURL = URL(string: "https://example.com/cup.ply")!
        let localURL = URL(fileURLWithPath: "/tmp/cup.ply")
        let previewRemoteURL = URL(string: "https://example.com/cup.png")!
        let previewLocalURL = URL(fileURLWithPath: "/tmp/cup.png")
        let candidateGridURL = URL(string: "https://example.com/cup_pose_candidates.png")!
        let canonicalPose = WorldObjectCanonicalPose(
            selectedCandidate: "E",
            upAxis: "+Z",
            bottomAxis: "-Z",
            frontAxis: "+X",
            restingPose: "open_top_upright",
            confidence: 0.84,
            reason: "Candidate E places the cup opening upward.",
            candidateGridURL: candidateGridURL
        )
        let response = SAM3DSceneRealizationResponse(
            objects: [
                SAM3DRealizedObject(
                    objectId: "coffee_cup",
                    status: .realized,
                    visualFormat: .gaussianSplatPLY,
                    assetURL: remoteURL,
                    previewImageURL: previewRemoteURL,
                    position: [0.25, 0.8, -0.6],
                    size: [0.12, 0.18, 0.12],
                    proxyShape: SAM3DProxyShapeSpec(
                        type: "cylinder",
                        size: [0.12, 0.18, 0.12]
                    ),
                    canonicalPose: canonicalPose,
                    notes: "Segmented and reconstructed"
                )
            ]
        )
        let cachedAsset = SAM3DCachedAsset(
            objectId: "coffee_cup",
            remoteURL: remoteURL,
            localURL: localURL,
            previewRemoteURL: previewRemoteURL,
            previewLocalURL: previewLocalURL
        )

        let reconciledPlan = SAM3DSceneReconciler.reconcile(
            plan: CafeCounterDemoPlan.plan,
            response: response,
            cachedAssets: [cachedAsset]
        )
        let cup = try XCTUnwrap(reconciledPlan.objects.first { $0.id == "coffee_cup" })

        XCTAssertEqual(reconciledPlan.tasks, CafeCounterDemoPlan.plan.tasks)
        XCTAssertEqual(cup.position, [0.30, 0.72, -0.88])
        XCTAssertEqual(cup.size, [0.08, 0.09, 0.08])
        XCTAssertEqual(cup.visualAsset?.format, .gaussianSplatPLY)
        XCTAssertEqual(cup.visualAsset?.source, .sam3D)
        XCTAssertEqual(cup.visualAsset?.status, .realized)
        XCTAssertEqual(cup.visualAsset?.remoteURL, remoteURL)
        XCTAssertEqual(cup.visualAsset?.localURL, localURL)
        XCTAssertEqual(cup.visualAsset?.previewRemoteURL, previewRemoteURL)
        XCTAssertEqual(cup.visualAsset?.previewLocalURL, previewLocalURL)
        XCTAssertEqual(cup.visualAsset?.realizedPosition, [0.25, 0.8, -0.6])
        XCTAssertEqual(cup.visualAsset?.realizedSize, [0.12, 0.18, 0.12])
        XCTAssertEqual(cup.visualAsset?.canonicalPose, canonicalPose)
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

    private static let layoutProbePlan = InteractionWorldPlan(
        id: "layout_probe",
        scenario: PrototypeScenarioCards.convenienceStore,
        objects: [
            WorldObjectSpec(
                id: "snack_chips",
                displayName: "Bag of Chips",
                description: "Small bag of chips the learner can pick up",
                kind: .generic(category: "smallObject"),
                position: [-1.4, 0.25, 0.2],
                size: [0.32, 0.32, 0.28],
                color: .red,
                isInteractive: true
            ),
            WorldObjectSpec(
                id: "shopping_basket",
                displayName: "Shopping Basket",
                description: "Open basket for the snack",
                kind: .generic(category: "container"),
                position: [1.2, 1.2, 0.8],
                size: [0.50, 0.34, 0.42],
                color: .blue,
                isInteractive: true
            ),
            WorldObjectSpec(
                id: "payment_terminal",
                displayName: "Payment Terminal",
                description: "Tap-to-pay terminal",
                kind: .cardReader,
                position: [0.0, 0.0, 1.3],
                size: [0.25, 0.25, 0.25],
                color: .green,
                isInteractive: true
            ),
            WorldObjectSpec(
                id: "cashier_marker",
                displayName: "Cashier",
                description: "Marker for the cashier",
                kind: .npcMarker,
                position: [0.0, 0.0, 0.0],
                size: [0.04, 0.04, 0.04],
                color: .purple,
                isInteractive: true
            ),
            WorldObjectSpec(
                id: "store_menu",
                displayName: "Store Menu",
                description: "Upright sign listing snacks",
                kind: .menu,
                position: [0.0, 0.0, 0.0],
                size: [0.60, 0.60, 0.20],
                color: .yellow,
                isInteractive: true
            )
        ],
        tasks: [
            InteractionTask(
                id: "pick_up_snack",
                instruction: "Pick up the bag of chips.",
                requiredObjectIds: ["snack_chips"],
                expectedInteraction: .tap(objectId: "snack_chips")
            ),
            InteractionTask(
                id: "place_snack",
                instruction: "Place the bag of chips in the shopping basket.",
                requiredObjectIds: ["snack_chips", "shopping_basket"],
                expectedInteraction: .place(objectId: "snack_chips", targetId: "shopping_basket")
            ),
            InteractionTask(
                id: "pay",
                instruction: "Tap the payment terminal.",
                requiredObjectIds: ["payment_terminal"],
                expectedInteraction: .tap(objectId: "payment_terminal")
            ),
            InteractionTask(
                id: "goodbye",
                instruction: "Wave goodbye to the cashier.",
                requiredObjectIds: ["cashier_marker"],
                expectedInteraction: .gesture(.wave, targetId: "cashier_marker")
            )
        ]
    )

    private static let marketStandSynonymPlan = InteractionWorldPlan(
        id: "market_stand_synonyms",
        scenario: PrototypeScenarioCards.marketStand,
        objects: [
            WorldObjectSpec(
                id: "market_stand",
                displayName: "Market Stand",
                description: "Front stall surface for fruit checkout",
                kind: .generic(category: "smallObject"),
                position: [0, 0, 0],
                size: [0.45, 0.12, 0.35],
                color: .brown,
                isInteractive: false
            ),
            WorldObjectSpec(
                id: "apple",
                displayName: "Apple",
                description: "Fruit the learner picks up",
                kind: .generic(category: "smallObject"),
                position: [0, 0, 0],
                size: [0.18, 0.18, 0.18],
                color: .red,
                isInteractive: true
            ),
            WorldObjectSpec(
                id: "vendor_marker",
                displayName: "Vendor Marker",
                description: "Marker for the market seller",
                kind: .generic(category: "marker"),
                position: [0, 0, 0],
                size: [0.10, 0.22, 0.10],
                color: .purple,
                isInteractive: true
            )
        ],
        tasks: [
            InteractionTask(
                id: "pick_up_apple",
                instruction: "Pick up the apple.",
                requiredObjectIds: ["apple"],
                expectedInteraction: .tap(objectId: "apple")
            ),
            InteractionTask(
                id: "wave_vendor",
                instruction: "Wave goodbye to the vendor.",
                requiredObjectIds: ["vendor_marker"],
                expectedInteraction: .gesture(.wave, targetId: "vendor_marker")
            )
        ]
    )

    private static let displayFixturePlan = InteractionWorldPlan(
        id: "display_fixture_probe",
        scenario: CafeCounterDemoPlan.scenario,
        objects: [
            WorldObjectSpec(
                id: "counter",
                displayName: "Cafe Counter",
                description: "Counter surface",
                kind: .counter,
                position: [0, 0, 0],
                size: [0.90, 0.08, 0.42],
                color: .brown,
                isInteractive: false
            ),
            WorldObjectSpec(
                id: "pastry_display",
                displayName: "Pastry Display",
                description: "Clear tabletop display case with pastries",
                kind: .displayCase,
                position: [0, 0, 0],
                size: [0.32, 0.24, 0.26],
                color: .yellow,
                isInteractive: true
            ),
            WorldObjectSpec(
                id: "menu",
                displayName: "Menu",
                description: "Upright menu sign",
                kind: .menu,
                position: [0, 0, 0],
                size: [0.30, 0.34, 0.06],
                color: .blue,
                isInteractive: true
            )
        ],
        tasks: [
            InteractionTask(
                id: "indicate_menu",
                instruction: "Indicate the menu.",
                requiredObjectIds: ["menu"],
                expectedInteraction: .indicate(objectId: "menu")
            )
        ]
    )

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

    private static let cafePaymentObjectsWithColorSynonymsJSON = """
    {
      "objects": [
        {
          "id": "card_reader",
          "displayName": "Card Reader",
          "description": "Electronic card reader for payment",
          "kind": { "type": "cardReader", "category": "uprightObject" },
          "position": [0.2, 0.75, -0.7],
          "size": [0.1, 0.1, 0.1],
          "color": "black",
          "isInteractive": true
        },
        {
          "id": "receipt",
          "displayName": "Receipt",
          "description": "Printed receipt to collect after payment",
          "kind": { "type": "generic", "category": "smallObject" },
          "position": [0.0, 0.75, -0.65],
          "size": [0.15, 0.01, 0.05],
          "color": "white",
          "isInteractive": true
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

    private static func containsRelation(
        _ relations: [InteractionWorldSpatialRelation],
        _ subjectId: String,
        _ kind: InteractionWorldSpatialRelationKind,
        _ objectId: String
    ) -> Bool {
        relations.contains {
            $0.subjectId == subjectId
                && $0.kind == kind
                && $0.objectId == objectId
        }
    }
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
