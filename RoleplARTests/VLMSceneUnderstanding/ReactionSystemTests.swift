//
//  ReactionSystemTests.swift
//  RoleplARTests
//
//  Tests for ReactionSystem action-to-response mapping
//

import XCTest
@testable import RoleplAR

@MainActor
final class ReactionSystemTests: XCTestCase {

    var reactionSystem: ReactionSystem!

    override func setUp() {
        super.setUp()
        reactionSystem = ReactionSystem()
        reactionSystem.reactionCooldown = 0 // Disable cooldown for testing
    }

    override func tearDown() {
        reactionSystem = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitialState() {
        XCTAssertNil(reactionSystem.lastReaction)
        XCTAssertTrue(reactionSystem.reactionHistory.isEmpty)
        XCTAssertTrue(reactionSystem.isEnabled)
        XCTAssertEqual(reactionSystem.sceneContext, .restaurant)
    }

    // MARK: - Menu Pickup Tests

    func testMenuPickupReaction() {
        var receivedJapanese: String?
        var receivedEnglish: String?

        reactionSystem.onNPCSpeak = { japanese, english in
            receivedJapanese = japanese
            receivedEnglish = english
        }

        let classification = ActionClassification(
            action: .pickingUp,
            object: "menu",
            confidence: 0.8
        )

        reactionSystem.process(classification)

        XCTAssertNotNil(reactionSystem.lastReaction)
        XCTAssertEqual(reactionSystem.lastReaction?.japaneseText, "ごゆっくりどうぞ。")
        XCTAssertEqual(receivedJapanese, "ごゆっくりどうぞ。")
        XCTAssertEqual(receivedEnglish, "Please take your time.")
    }

    func testMenuPlacementReaction() {
        var sceneStateChanged: SceneState?

        reactionSystem.onSceneStateChange = { state in
            sceneStateChanged = state
        }

        let classification = ActionClassification(
            action: .placing,
            object: "menu",
            target: "table",
            confidence: 0.8
        )

        reactionSystem.process(classification)

        XCTAssertNotNil(reactionSystem.lastReaction)
        XCTAssertEqual(reactionSystem.lastReaction?.japaneseText, "ご注文はお決まりですか？")
        XCTAssertEqual(sceneStateChanged, .readyToOrder)
    }

    // MARK: - Teacup Tests

    func testTeacupPickupReaction() {
        let classification = ActionClassification(
            action: .pickingUp,
            object: "teacup",
            confidence: 0.8
        )

        reactionSystem.process(classification)

        XCTAssertNotNil(reactionSystem.lastReaction)
        XCTAssertTrue(reactionSystem.lastReaction?.japaneseText.contains("お茶") ?? false)
    }

    // MARK: - Waving Tests

    func testWavingReaction() {
        var sceneStateChanged: SceneState?

        reactionSystem.onSceneStateChange = { state in
            sceneStateChanged = state
        }

        let classification = ActionClassification(
            action: .waving,
            confidence: 0.8
        )

        reactionSystem.process(classification)

        XCTAssertNotNil(reactionSystem.lastReaction)
        XCTAssertEqual(reactionSystem.lastReaction?.japaneseText, "はい、少々お待ちください。")
        XCTAssertEqual(sceneStateChanged, .callingWaiter)
    }

    // MARK: - Pointing Tests

    func testPointingReaction() {
        let classification = ActionClassification(
            action: .pointing,
            target: "menu_item",
            confidence: 0.8
        )

        reactionSystem.process(classification)

        XCTAssertNotNil(reactionSystem.lastReaction)
        XCTAssertEqual(reactionSystem.lastReaction?.japaneseText, "はい、こちらですね。")
    }

    // MARK: - Confidence Threshold Tests

    func testLowConfidenceIgnored() {
        let classification = ActionClassification(
            action: .pickingUp,
            object: "menu",
            confidence: 0.3 // Below threshold
        )

        reactionSystem.process(classification)

        XCTAssertNil(reactionSystem.lastReaction)
    }

    func testConfidenceAtThreshold() {
        reactionSystem.confidenceThreshold = 0.6

        let classification = ActionClassification(
            action: .pickingUp,
            object: "menu",
            confidence: 0.6 // Exactly at threshold
        )

        reactionSystem.process(classification)

        XCTAssertNotNil(reactionSystem.lastReaction)
    }

    // MARK: - Cooldown Tests

    func testCooldownPreventsRepeatedReactions() {
        reactionSystem.reactionCooldown = 5.0 // 5 second cooldown

        let classification = ActionClassification(
            action: .pickingUp,
            object: "menu",
            confidence: 0.8
        )

        // First reaction
        reactionSystem.process(classification)
        XCTAssertEqual(reactionSystem.reactionHistory.count, 1)

        // Second reaction should be blocked by cooldown
        reactionSystem.process(classification)
        XCTAssertEqual(reactionSystem.reactionHistory.count, 1)
    }

    func testDifferentActionsNotAffectedByCooldown() {
        reactionSystem.reactionCooldown = 5.0

        // First action
        let pickUp = ActionClassification(
            action: .pickingUp,
            object: "menu",
            confidence: 0.8
        )
        reactionSystem.process(pickUp)

        // Different action should not be blocked
        let wave = ActionClassification(
            action: .waving,
            confidence: 0.8
        )
        reactionSystem.process(wave)

        XCTAssertEqual(reactionSystem.reactionHistory.count, 2)
    }

    // MARK: - Enabled State Tests

    func testDisabledSystemIgnoresActions() {
        reactionSystem.isEnabled = false

        let classification = ActionClassification(
            action: .pickingUp,
            object: "menu",
            confidence: 0.8
        )

        reactionSystem.process(classification)

        XCTAssertNil(reactionSystem.lastReaction)
        XCTAssertTrue(reactionSystem.reactionHistory.isEmpty)
    }

    // MARK: - Greeting and Farewell Tests

    func testTriggerGreeting() {
        var receivedJapanese: String?

        reactionSystem.onNPCSpeak = { japanese, _ in
            receivedJapanese = japanese
        }

        reactionSystem.triggerGreeting()

        XCTAssertNotNil(reactionSystem.lastReaction)
        XCTAssertTrue(receivedJapanese?.contains("いらっしゃいませ") ?? false)
    }

    func testTriggerFarewell() {
        var sceneStateChanged: SceneState?

        reactionSystem.onSceneStateChange = { state in
            sceneStateChanged = state
        }

        reactionSystem.triggerFarewell()

        XCTAssertNotNil(reactionSystem.lastReaction)
        XCTAssertTrue(reactionSystem.lastReaction?.japaneseText.contains("ありがとうございました") ?? false)
        XCTAssertEqual(sceneStateChanged, .farewell)
    }

    // MARK: - Learning Moment Tests

    func testLearningMomentCallback() {
        var receivedLearningMoment: LearningMoment?

        reactionSystem.onLearningMoment = { moment in
            receivedLearningMoment = moment
        }

        let classification = ActionClassification(
            action: .pickingUp,
            object: "menu",
            confidence: 0.8
        )

        reactionSystem.process(classification)

        XCTAssertNotNil(receivedLearningMoment)
        XCTAssertTrue(receivedLearningMoment?.note.contains("ゆっくり") ?? false)
    }

    // MARK: - Reset Tests

    func testReset() {
        // Generate some state
        reactionSystem.triggerGreeting()
        XCTAssertNotNil(reactionSystem.lastReaction)
        XCTAssertFalse(reactionSystem.reactionHistory.isEmpty)

        // Reset
        reactionSystem.reset()

        XCTAssertNil(reactionSystem.lastReaction)
        XCTAssertTrue(reactionSystem.reactionHistory.isEmpty)
    }

    // MARK: - Idle Action Tests

    func testIdleActionNoReaction() {
        let classification = ActionClassification(
            action: .idle,
            confidence: 0.9
        )

        reactionSystem.process(classification)

        // Idle should not trigger a reaction
        XCTAssertNil(reactionSystem.lastReaction)
    }

    // MARK: - Unknown Object Tests

    func testUnknownObjectNoReaction() {
        let classification = ActionClassification(
            action: .pickingUp,
            object: "unknown_object",
            confidence: 0.8
        )

        reactionSystem.process(classification)

        // Unknown objects should not trigger reactions
        XCTAssertNil(reactionSystem.lastReaction)
    }
}
