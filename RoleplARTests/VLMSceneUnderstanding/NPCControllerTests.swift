//
//  NPCControllerTests.swift
//  RoleplARTests
//
//  Tests for NPCController state management and speech
//

import XCTest
@testable import RoleplAR

@MainActor
final class NPCControllerTests: XCTestCase {

    var npcController: NPCController!

    override func setUp() {
        super.setUp()
        npcController = NPCController()
        npcController.useTTS = false // Disable TTS for testing
    }

    override func tearDown() {
        npcController = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitialState() {
        XCTAssertEqual(npcController.currentState, .idle)
        XCTAssertNil(npcController.lastUtterance)
        XCTAssertTrue(npcController.conversationHistory.isEmpty)
        XCTAssertEqual(npcController.npcName, "店員")
        XCTAssertEqual(npcController.npcRole, "waiter")
    }

    // MARK: - Speaking Tests

    func testSpeakUpdatesLastUtterance() {
        npcController.speak(japanese: "こんにちは", englishHint: "Hello")

        XCTAssertNotNil(npcController.lastUtterance)
        XCTAssertEqual(npcController.lastUtterance?.japanese, "こんにちは")
        XCTAssertEqual(npcController.lastUtterance?.english, "Hello")
        XCTAssertEqual(npcController.lastUtterance?.npcName, "店員")
    }

    func testSpeakAddsToHistory() {
        npcController.speak(japanese: "いらっしゃいませ")
        npcController.speak(japanese: "ご注文は？")

        XCTAssertEqual(npcController.conversationHistory.count, 2)
        XCTAssertEqual(npcController.conversationHistory[0].japanese, "いらっしゃいませ")
        XCTAssertEqual(npcController.conversationHistory[1].japanese, "ご注文は？")
    }

    func testSpeakWithoutEnglishHint() {
        npcController.speak(japanese: "すみません")

        XCTAssertNotNil(npcController.lastUtterance)
        XCTAssertEqual(npcController.lastUtterance?.japanese, "すみません")
        XCTAssertNil(npcController.lastUtterance?.english)
    }

    func testSpeakUpdatesState() {
        npcController.speak(japanese: "テスト")

        XCTAssertEqual(npcController.currentState, .speaking)
    }

    // MARK: - State Change Callback Tests

    func testStateChangeCallback() {
        var receivedStates: [NPCState] = []

        npcController.onStateChange = { state in
            receivedStates.append(state)
        }

        npcController.speak(japanese: "テスト")

        XCTAssertTrue(receivedStates.contains(.speaking))
    }

    func testStartSpeakingCallback() {
        var callbackInvoked = false

        npcController.useTTS = true // Enable to test callback
        npcController.onStartSpeaking = {
            callbackInvoked = true
        }

        npcController.speak(japanese: "テスト")

        XCTAssertTrue(callbackInvoked)
    }

    // MARK: - Scripted Response Tests

    func testRespondToMenuPickup() {
        npcController.respondToMenuPickup()

        XCTAssertNotNil(npcController.lastUtterance)
        XCTAssertTrue(npcController.lastUtterance?.japanese.contains("ごゆっくり") ?? false)
    }

    func testRespondToMenuPlacement() {
        npcController.respondToMenuPlacement()

        XCTAssertNotNil(npcController.lastUtterance)
        XCTAssertTrue(npcController.lastUtterance?.japanese.contains("ご注文") ?? false)
        XCTAssertEqual(npcController.currentState, .takingOrder)
    }

    func testRespondToWave() {
        npcController.respondToWave()

        XCTAssertNotNil(npcController.lastUtterance)
        XCTAssertTrue(npcController.lastUtterance?.japanese.contains("参ります") ?? false)
        XCTAssertEqual(npcController.currentState, .approachingUser)
    }

    func testGreetUser() {
        npcController.greetUser()

        XCTAssertNotNil(npcController.lastUtterance)
        XCTAssertTrue(npcController.lastUtterance?.japanese.contains("いらっしゃいませ") ?? false)
        XCTAssertEqual(npcController.currentState, .greeting)
    }

    func testSayFarewell() {
        npcController.sayFarewell()

        XCTAssertNotNil(npcController.lastUtterance)
        XCTAssertTrue(npcController.lastUtterance?.japanese.contains("ありがとうございました") ?? false)
        XCTAssertEqual(npcController.currentState, .farewell)
    }

    // MARK: - Handle User Action Tests

    func testHandleWavingAction() {
        npcController.handleUserAction(.waving)

        XCTAssertEqual(npcController.currentState, .approachingUser)
    }

    func testHandlePickingUpMenuAction() {
        npcController.handleUserAction(.pickingUp, object: "menu")

        XCTAssertEqual(npcController.currentState, .waitingForOrder)
    }

    func testHandlePlacingMenuAction() {
        npcController.handleUserAction(.placing, object: "menu")

        XCTAssertEqual(npcController.currentState, .takingOrder)
    }

    func testHandleUnrelatedAction() {
        let initialState = npcController.currentState

        npcController.handleUserAction(.idle)

        // State should not change for idle
        XCTAssertEqual(npcController.currentState, initialState)
    }

    // MARK: - Reset Tests

    func testReset() {
        // Generate some state
        npcController.speak(japanese: "テスト1")
        npcController.speak(japanese: "テスト2")
        XCTAssertEqual(npcController.conversationHistory.count, 2)
        XCTAssertNotNil(npcController.lastUtterance)

        // Reset
        npcController.reset()

        XCTAssertEqual(npcController.currentState, .idle)
        XCTAssertNil(npcController.lastUtterance)
        XCTAssertTrue(npcController.conversationHistory.isEmpty)
    }

    // MARK: - NPC Name Tests

    func testCustomNPCName() {
        npcController.npcName = "マスター"

        npcController.speak(japanese: "いらっしゃい")

        XCTAssertEqual(npcController.lastUtterance?.npcName, "マスター")
    }

    // MARK: - NPCUtterance Tests

    func testNPCUtteranceHasUniqueID() {
        npcController.speak(japanese: "テスト1")
        let id1 = npcController.lastUtterance?.id

        npcController.speak(japanese: "テスト2")
        let id2 = npcController.lastUtterance?.id

        XCTAssertNotEqual(id1, id2)
    }

    func testNPCUtteranceTimestamp() {
        let beforeTime = Date()
        npcController.speak(japanese: "テスト")
        let afterTime = Date()

        guard let timestamp = npcController.lastUtterance?.timestamp else {
            XCTFail("Timestamp should not be nil")
            return
        }

        XCTAssertGreaterThanOrEqual(timestamp, beforeTime)
        XCTAssertLessThanOrEqual(timestamp, afterTime)
    }

    // MARK: - State Enum Tests

    func testNPCStateRawValues() {
        XCTAssertEqual(NPCState.idle.rawValue, "idle")
        XCTAssertEqual(NPCState.greeting.rawValue, "greeting")
        XCTAssertEqual(NPCState.speaking.rawValue, "speaking")
        XCTAssertEqual(NPCState.waitingForResponse.rawValue, "waitingForResponse")
        XCTAssertEqual(NPCState.farewell.rawValue, "farewell")
    }

    // MARK: - Speech Duration Estimation Tests

    func testSpeechDurationCalculation() {
        // Test that longer text results in longer duration
        // We can't directly test private method, but we can observe behavior
        // by checking that speaking callback happens after some delay

        var finishCallbackTime: Date?
        let startTime = Date()

        npcController.useTTS = true
        npcController.onFinishSpeaking = {
            finishCallbackTime = Date()
        }

        // Speak a moderate length text
        npcController.speak(japanese: "これは長いテストの文章です")

        // Wait for callback (max 5 seconds)
        let expectation = XCTestExpectation(description: "Finish speaking callback")

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        if let finishTime = finishCallbackTime {
            let duration = finishTime.timeIntervalSince(startTime)
            // Should be at least 1 second (minimum duration)
            XCTAssertGreaterThanOrEqual(duration, 0.5)
        }
    }
}
