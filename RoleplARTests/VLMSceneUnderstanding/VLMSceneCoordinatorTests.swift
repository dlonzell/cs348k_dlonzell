//
//  VLMSceneCoordinatorTests.swift
//  RoleplARTests
//
//  Integration tests for VLMSceneCoordinator
//

import XCTest
@testable import RoleplAR

@MainActor
final class VLMSceneCoordinatorTests: XCTestCase {

    var coordinator: VLMSceneCoordinator!

    override func setUp() {
        super.setUp()
        coordinator = VLMSceneCoordinator()
        coordinator.useMockAnalyzer = true
    }

    override func tearDown() {
        coordinator.stop()
        coordinator = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitialState() {
        XCTAssertFalse(coordinator.isRunning)
        XCTAssertEqual(coordinator.currentSceneState, .greeting)
        XCTAssertNotNil(coordinator.vlmPipeline)
        XCTAssertNotNil(coordinator.reactionSystem)
        XCTAssertNotNil(coordinator.npcController)
    }

    func testDefaultConfiguration() {
        XCTAssertTrue(coordinator.useMockAnalyzer)
        XCTAssertEqual(coordinator.captureResolution, 512)
    }

    // MARK: - Debug Info Tests

    func testDebugInfoInitialState() {
        let debugInfo = coordinator.debugInfo

        XCTAssertEqual(debugInfo.lastAction, "-")
        XCTAssertEqual(debugInfo.lastObject, "-")
        XCTAssertEqual(debugInfo.confidence, 0)
        XCTAssertEqual(debugInfo.fps, 0)
        XCTAssertEqual(debugInfo.totalFrames, 0)
        XCTAssertNil(debugInfo.lastLearningMoment)
    }

    // MARK: - Manual Trigger Tests

    func testTriggerGreeting() {
        var reactionTriggered = false

        coordinator.reactionSystem.onNPCSpeak = { japanese, _ in
            if japanese.contains("いらっしゃいませ") {
                reactionTriggered = true
            }
        }

        coordinator.triggerGreeting()

        XCTAssertTrue(reactionTriggered)
    }

    func testTriggerFarewell() {
        var reactionTriggered = false

        coordinator.reactionSystem.onNPCSpeak = { japanese, _ in
            if japanese.contains("ありがとうございました") {
                reactionTriggered = true
            }
        }

        coordinator.triggerFarewell()

        XCTAssertTrue(reactionTriggered)
    }

    // MARK: - Stop Tests

    func testStopResetsState() {
        // Manually set some state
        coordinator.triggerGreeting()

        // Stop
        coordinator.stop()

        XCTAssertFalse(coordinator.isRunning)
    }

    // MARK: - DialogueViewModel Integration Tests

    func testDialogueViewModelConnection() {
        let dialogueVM = DialogueViewModel()

        coordinator.dialogueViewModel = dialogueVM

        // Should propagate to npcController
        XCTAssertNotNil(coordinator.npcController.dialogueViewModel)
    }

    // MARK: - Scene State Tests

    func testSceneStateUpdatesOnReaction() {
        // Process a menu placement action
        let classification = ActionClassification(
            action: .placing,
            object: "menu",
            target: "table",
            confidence: 0.8
        )

        coordinator.reactionSystem.process(classification)

        XCTAssertEqual(coordinator.currentSceneState, .readyToOrder)
    }

    // MARK: - Binding Tests

    func testVLMPipelineToReactionSystemBinding() {
        // Create a classification
        let classification = ActionClassification(
            action: .waving,
            confidence: 0.9
        )

        var reactionReceived = false
        coordinator.reactionSystem.onNPCSpeak = { _, _ in
            reactionReceived = true
        }

        // Simulate VLM pipeline callback
        coordinator.vlmPipeline.onActionClassified?(classification)

        // Reaction system should have processed it
        XCTAssertTrue(reactionReceived)
    }

    // MARK: - Debug Info Update Tests

    func testDebugInfoUpdatesOnClassification() {
        let classification = ActionClassification(
            action: .pickingUp,
            object: "menu",
            confidence: 0.85
        )

        // Simulate classification received
        coordinator.vlmPipeline.onActionClassified?(classification)

        // Check debug info was updated
        XCTAssertEqual(coordinator.debugInfo.lastAction, "Picking Up")
        XCTAssertEqual(coordinator.debugInfo.lastObject, "menu")
        XCTAssertEqual(coordinator.debugInfo.confidence, 0.85)
    }

    // MARK: - Scene Context Tests

    func testSetupSceneUpdatesContext() {
        coordinator.setupScene(objects: ["custom_object"], context: .shop)

        XCTAssertEqual(coordinator.reactionSystem.sceneContext, .shop)
    }
}

// MARK: - DebugInfo Tests

final class DebugInfoTests: XCTestCase {

    func testDebugInfoDefaultValues() {
        let debugInfo = DebugInfo()

        XCTAssertEqual(debugInfo.lastAction, "-")
        XCTAssertEqual(debugInfo.lastObject, "-")
        XCTAssertEqual(debugInfo.confidence, 0)
        XCTAssertEqual(debugInfo.fps, 0)
        XCTAssertEqual(debugInfo.totalFrames, 0)
        XCTAssertNil(debugInfo.lastLearningMoment)
    }

    func testDebugInfoMutation() {
        var debugInfo = DebugInfo()

        debugInfo.lastAction = "Test Action"
        debugInfo.lastObject = "Test Object"
        debugInfo.confidence = 0.75
        debugInfo.fps = 5.0
        debugInfo.totalFrames = 100
        debugInfo.lastLearningMoment = "Test learning"

        XCTAssertEqual(debugInfo.lastAction, "Test Action")
        XCTAssertEqual(debugInfo.lastObject, "Test Object")
        XCTAssertEqual(debugInfo.confidence, 0.75)
        XCTAssertEqual(debugInfo.fps, 5.0)
        XCTAssertEqual(debugInfo.totalFrames, 100)
        XCTAssertEqual(debugInfo.lastLearningMoment, "Test learning")
    }
}
