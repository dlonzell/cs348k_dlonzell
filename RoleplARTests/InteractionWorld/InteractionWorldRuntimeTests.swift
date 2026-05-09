import XCTest
@testable import RoleplAR

@MainActor
final class InteractionWorldRuntimeTests: XCTestCase {
    func testCafeCounterPlanValidates() throws {
        XCTAssertNoThrow(try InteractionWorldRuntime.validate(CafeCounterDemoPlan.plan))
    }

    func testCafeCounterTasksReferenceExistingObjects() {
        let plan = CafeCounterDemoPlan.plan
        let objectIds = Set(plan.objects.map(\.id))

        for task in plan.tasks {
            for objectId in task.requiredObjectIds {
                XCTAssertTrue(
                    objectIds.contains(objectId),
                    "Task \(task.id) references missing object \(objectId)"
                )
            }
        }
    }

    func testCafeCounterInteractionsHaveSupportedHandlers() {
        for task in CafeCounterDemoPlan.plan.tasks {
            XCTAssertTrue(
                InteractionWorldRuntime.supportedInteractions.contains(task.expectedInteraction.supportKind),
                "Task \(task.id) does not have a supported handler"
            )
        }
    }

    func testSimulatedEventSequenceCompletesAllTasksInOrder() {
        let runtime = InteractionWorldRuntime(plan: CafeCounterDemoPlan.plan)

        XCTAssertEqual(runtime.currentTask?.id, "wave_to_barista")
        XCTAssertTrue(runtime.process(.gesture(.wave, targetId: "barista_marker")))

        XCTAssertEqual(runtime.currentTask?.id, "indicate_menu")
        XCTAssertTrue(runtime.process(.select(objectId: "menu")))

        XCTAssertEqual(runtime.currentTask?.id, "point_at_pastry_case")
        XCTAssertTrue(runtime.process(.gesture(.point, targetId: "pastry_case")))

        XCTAssertEqual(runtime.currentTask?.id, "place_cup_on_tray")
        XCTAssertTrue(runtime.process(.placed(objectId: "coffee_cup", targetId: "tray")))

        XCTAssertEqual(runtime.currentTask?.id, "tap_card_reader")
        XCTAssertTrue(runtime.process(.select(objectId: "card_reader")))

        XCTAssertTrue(runtime.isComplete)
        XCTAssertEqual(runtime.completedTaskIds.count, 5)

        let result = runtime.evaluate()
        XCTAssertEqual(result.objectCoverageSummary, "7/7")
        XCTAssertEqual(result.handlerCoverageSummary, "5/5")
        XCTAssertEqual(result.completionSummary, "5/5")
        XCTAssertNil(result.firstFailedTaskId)
    }

    func testWrongObjectDoesNotCompleteCurrentTask() {
        let runtime = InteractionWorldRuntime(plan: CafeCounterDemoPlan.plan)

        XCTAssertFalse(runtime.process(.select(objectId: "menu")))
        XCTAssertEqual(runtime.currentTask?.id, "wave_to_barista")
        XCTAssertTrue(runtime.completedTaskIds.isEmpty)
        XCTAssertEqual(runtime.eventLog.count, 1)
        XCTAssertFalse(runtime.eventLog[0].matched)
    }

    func testOutOfOrderCorrectEventDoesNotAdvanceQueue() {
        let runtime = InteractionWorldRuntime(plan: CafeCounterDemoPlan.plan)

        XCTAssertFalse(runtime.process(.select(objectId: "card_reader")))
        XCTAssertEqual(runtime.currentTask?.id, "wave_to_barista")
        XCTAssertTrue(runtime.completedTaskIds.isEmpty)

        XCTAssertTrue(runtime.process(.gesture(.wave, targetId: "barista_marker")))
        XCTAssertEqual(runtime.currentTask?.id, "indicate_menu")
    }

    func testManualEvaluationRatingsCanBeRecordedAndCleared() {
        let runtime = InteractionWorldRuntime(plan: CafeCounterDemoPlan.plan)

        XCTAssertEqual(runtime.manualEvaluationSummary, "0/25")
        XCTAssertEqual(
            runtime.manualRating(taskId: "wave_to_barista", metric: .objectRealization),
            .unscored
        )

        runtime.setManualRating(.yes, taskId: "wave_to_barista", metric: .objectRealization)
        runtime.setManualRating(.partial, taskId: "wave_to_barista", metric: .spatialPlausibility)
        runtime.setManualRating(.no, taskId: "indicate_menu", metric: .taskCompletion)

        XCTAssertEqual(runtime.manualEvaluationSummary, "3/25")
        XCTAssertEqual(runtime.manualEvaluationYesCount, 1)
        XCTAssertEqual(
            runtime.manualRating(taskId: "wave_to_barista", metric: .spatialPlausibility),
            .partial
        )

        runtime.setManualRating(.unscored, taskId: "wave_to_barista", metric: .objectRealization)
        XCTAssertEqual(runtime.manualEvaluationSummary, "2/25")

        runtime.reset()
        XCTAssertEqual(runtime.manualEvaluationSummary, "0/25")
    }

    func testGenericObjectPlanValidatesAndConfiguresScene() throws {
        let plan = InteractionWorldPlan(
            id: "generic_object_test",
            scenario: CafeCounterDemoPlan.scenario,
            objects: [
                WorldObjectSpec(
                    id: "ramen_bowl",
                    displayName: "Ramen Bowl",
                    description: "Ceramic ramen bowl with steam",
                    kind: .generic(category: "container"),
                    position: [0, 0.72, -0.8],
                    size: [0.16, 0.08, 0.16],
                    color: .yellow,
                    isInteractive: true
                )
            ],
            tasks: [
                InteractionTask(
                    id: "tap_ramen_bowl",
                    instruction: "Tap the ramen bowl.",
                    requiredObjectIds: ["ramen_bowl"],
                    expectedInteraction: .tap(objectId: "ramen_bowl")
                )
            ]
        )

        XCTAssertNoThrow(try InteractionWorldRuntime.validate(plan))

        let sceneManager = InteractionWorldSceneManager()
        sceneManager.configure(plan: plan)
        XCTAssertEqual(sceneManager.rootEntity.children.count, 1)
    }

    func testInteractionKindJSONRoundTrip() throws {
        let interactions: [InteractionKind] = [
            .indicate(objectId: "menu"),
            .tap(objectId: "card_reader"),
            .drag(objectId: "coffee_cup"),
            .place(objectId: "coffee_cup", targetId: "tray"),
            .gesture(.wave, targetId: "barista_marker"),
            .gesture(.openPalm, targetId: nil)
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for interaction in interactions {
            let data = try encoder.encode(interaction)
            let decoded = try decoder.decode(InteractionKind.self, from: data)
            XCTAssertEqual(decoded, interaction)
        }
    }

    func testWorldObjectSpecJSONRoundTripForTypedAndGenericKinds() throws {
        let objects = [
            WorldObjectSpec(
                id: "menu",
                displayName: "Menu",
                description: "A laminated cafe menu",
                kind: .menu,
                position: [-0.2, 0.7, -0.9],
                size: [0.2, 0.02, 0.3],
                color: .red,
                isInteractive: true
            ),
            WorldObjectSpec(
                id: "umbrella_stand",
                displayName: "Umbrella Stand",
                description: "A narrow stand for umbrellas near the entrance",
                kind: .generic(category: "uprightObject"),
                position: [0.4, 0.55, -1.1],
                size: [0.12, 0.5, 0.12],
                color: .gray,
                isInteractive: false
            )
        ]

        let data = try JSONEncoder().encode(objects)
        let decoded = try JSONDecoder().decode([WorldObjectSpec].self, from: data)

        XCTAssertEqual(decoded, objects)
    }

    func testMalformedPlansReturnSpecificValidationErrors() {
        let duplicateObjectPlan = InteractionWorldPlan(
            id: "duplicate_object",
            scenario: CafeCounterDemoPlan.scenario,
            objects: [
                CafeCounterDemoPlan.plan.objects[0],
                CafeCounterDemoPlan.plan.objects[0]
            ],
            tasks: []
        )

        XCTAssertThrowsError(try InteractionWorldRuntime.validate(duplicateObjectPlan)) { error in
            XCTAssertEqual(error as? InteractionWorldValidationError, .duplicateObjectId("counter"))
        }

        let missingReferencePlan = InteractionWorldPlan(
            id: "missing_reference",
            scenario: CafeCounterDemoPlan.scenario,
            objects: [CafeCounterDemoPlan.plan.objects[0]],
            tasks: [
                InteractionTask(
                    id: "tap_missing",
                    instruction: "Tap a missing object.",
                    requiredObjectIds: ["missing_object"],
                    expectedInteraction: .tap(objectId: "missing_object")
                )
            ]
        )

        XCTAssertThrowsError(try InteractionWorldRuntime.validate(missingReferencePlan)) { error in
            XCTAssertEqual(
                error as? InteractionWorldValidationError,
                .taskReferencesMissingObject(taskId: "tap_missing", objectId: "missing_object")
            )
        }
    }
}
