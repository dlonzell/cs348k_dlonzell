//
//  ActionClassificationTests.swift
//  RoleplARTests
//
//  Tests for ActionClassification data models and parsing
//

import XCTest
@testable import RoleplAR

final class ActionClassificationTests: XCTestCase {

    // MARK: - ActionType Tests

    func testActionTypeRawValues() {
        XCTAssertEqual(ActionType.idle.rawValue, "idle")
        XCTAssertEqual(ActionType.reaching.rawValue, "reaching")
        XCTAssertEqual(ActionType.pickingUp.rawValue, "picking_up")
        XCTAssertEqual(ActionType.holding.rawValue, "holding")
        XCTAssertEqual(ActionType.placing.rawValue, "placing")
        XCTAssertEqual(ActionType.pointing.rawValue, "pointing")
        XCTAssertEqual(ActionType.waving.rawValue, "waving")
        XCTAssertEqual(ActionType.gesturing.rawValue, "gesturing")
        XCTAssertEqual(ActionType.unknown.rawValue, "unknown")
    }

    func testActionTypeDisplayNames() {
        XCTAssertEqual(ActionType.idle.displayName, "Idle")
        XCTAssertEqual(ActionType.pickingUp.displayName, "Picking Up")
        XCTAssertEqual(ActionType.holding.displayName, "Holding")
        XCTAssertEqual(ActionType.placing.displayName, "Placing")
        XCTAssertEqual(ActionType.waving.displayName, "Waving")
    }

    func testActionTypeFromRawValue() {
        XCTAssertEqual(ActionType(rawValue: "idle"), .idle)
        XCTAssertEqual(ActionType(rawValue: "picking_up"), .pickingUp)
        XCTAssertEqual(ActionType(rawValue: "holding"), .holding)
        XCTAssertEqual(ActionType(rawValue: "invalid"), nil)
    }

    func testActionTypeAllCases() {
        XCTAssertEqual(ActionType.allCases.count, 9)
        XCTAssertTrue(ActionType.allCases.contains(.idle))
        XCTAssertTrue(ActionType.allCases.contains(.unknown))
    }

    // MARK: - ActionClassification Tests

    func testActionClassificationInitialization() {
        let classification = ActionClassification(
            action: .pickingUp,
            object: "menu",
            target: "table",
            confidence: 0.85
        )

        XCTAssertEqual(classification.action, .pickingUp)
        XCTAssertEqual(classification.object, "menu")
        XCTAssertEqual(classification.target, "table")
        XCTAssertEqual(classification.confidence, 0.85)
        XCTAssertNotNil(classification.timestamp)
    }

    func testActionClassificationWithoutOptionals() {
        let classification = ActionClassification(
            action: .idle,
            confidence: 0.9
        )

        XCTAssertEqual(classification.action, .idle)
        XCTAssertNil(classification.object)
        XCTAssertNil(classification.target)
        XCTAssertEqual(classification.confidence, 0.9)
    }

    func testActionClassificationEquatable() {
        let timestamp = Date()
        let classification1 = ActionClassification(
            action: .holding,
            object: "menu",
            confidence: 0.8,
            timestamp: timestamp
        )
        let classification2 = ActionClassification(
            action: .holding,
            object: "menu",
            confidence: 0.8,
            timestamp: timestamp
        )

        XCTAssertEqual(classification1, classification2)
    }

    func testActionClassificationCodable() throws {
        let original = ActionClassification(
            action: .placing,
            object: "menu",
            target: "table",
            confidence: 0.75
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ActionClassification.self, from: data)

        XCTAssertEqual(decoded.action, original.action)
        XCTAssertEqual(decoded.object, original.object)
        XCTAssertEqual(decoded.target, original.target)
        XCTAssertEqual(decoded.confidence, original.confidence)
    }

    // MARK: - SceneObject Tests

    func testSceneObjectRawValues() {
        XCTAssertEqual(SceneObject.menu.rawValue, "menu")
        XCTAssertEqual(SceneObject.table.rawValue, "table")
        XCTAssertEqual(SceneObject.teacup.rawValue, "teacup")
        XCTAssertEqual(SceneObject.chopsticks.rawValue, "chopsticks")
    }

    func testSceneObjectDisplayNames() {
        XCTAssertEqual(SceneObject.menu.displayName, "Menu")
        XCTAssertEqual(SceneObject.table.displayName, "Table")
        XCTAssertEqual(SceneObject.teacup.displayName, "Teacup")
    }

    // MARK: - SceneFrame Tests

    func testSceneFrameInitialization() {
        let frame = SceneFrame(
            pixelBuffer: nil,
            sceneObjects: ["menu", "table"],
            leftHandJoints: [:],
            rightHandJoints: [:],
            timestamp: Date()
        )

        XCTAssertNil(frame.pixelBuffer)
        XCTAssertEqual(frame.sceneObjects, ["menu", "table"])
        XCTAssertTrue(frame.leftHandJoints.isEmpty)
        XCTAssertTrue(frame.rightHandJoints.isEmpty)
    }

    func testSceneFrameDefaultValues() {
        let frame = SceneFrame()

        XCTAssertNil(frame.pixelBuffer)
        XCTAssertTrue(frame.sceneObjects.isEmpty)
        XCTAssertTrue(frame.leftHandJoints.isEmpty)
        XCTAssertTrue(frame.rightHandJoints.isEmpty)
    }
}
