//
//  TestHelpers.swift
//  RoleplARTests
//
//  Helper utilities and mocks for VLM testing
//

import XCTest
import simd
@testable import RoleplAR

// MARK: - Mock Scene Analyzer

/// A mock analyzer for testing that returns predictable results
class TestMockAnalyzer: SceneAnalyzer {
    var isAnalyzing: Bool = false

    var predefinedClassification: ActionClassification?
    var analyzeCallCount = 0
    var lastAnalyzedFrame: SceneFrame?

    func analyze(frame: SceneFrame) async throws -> ActionClassification {
        analyzeCallCount += 1
        lastAnalyzedFrame = frame

        if let predefined = predefinedClassification {
            return predefined
        }

        return ActionClassification(action: .idle, confidence: 0.5)
    }

    func reset() {
        analyzeCallCount = 0
        lastAnalyzedFrame = nil
        predefinedClassification = nil
    }
}

// MARK: - Test Fixtures

enum TestFixtures {

    /// Create a test frame with no hand data
    static func emptyFrame(objects: [String] = ["menu", "table"]) -> SceneFrame {
        SceneFrame(
            pixelBuffer: nil,
            sceneObjects: objects,
            leftHandJoints: [:],
            rightHandJoints: [:],
            timestamp: Date()
        )
    }

    /// Create a test frame with right hand at specified position
    static func frameWithRightHand(
        at position: SIMD3<Float>,
        objects: [String] = ["menu", "table"]
    ) -> SceneFrame {
        let transform = makeTransform(position: position)

        return SceneFrame(
            pixelBuffer: nil,
            sceneObjects: objects,
            leftHandJoints: [:],
            rightHandJoints: ["wrist": transform],
            timestamp: Date()
        )
    }

    /// Create a test frame with both hands
    static func frameWithBothHands(
        leftPosition: SIMD3<Float>,
        rightPosition: SIMD3<Float>,
        objects: [String] = ["menu", "table"]
    ) -> SceneFrame {
        let leftTransform = makeTransform(position: leftPosition)
        let rightTransform = makeTransform(position: rightPosition)

        return SceneFrame(
            pixelBuffer: nil,
            sceneObjects: objects,
            leftHandJoints: ["wrist": leftTransform],
            rightHandJoints: ["wrist": rightTransform],
            timestamp: Date()
        )
    }

    /// Create a full hand skeleton with all joints
    static func fullHandJoints(basePosition: SIMD3<Float>) -> [String: simd_float4x4] {
        var joints: [String: simd_float4x4] = [:]

        let jointNames = [
            "wrist",
            "thumbKnuckle", "thumbIntermediateBase", "thumbIntermediateTip", "thumbTip",
            "indexFingerMetacarpal", "indexFingerKnuckle", "indexFingerIntermediateBase",
            "indexFingerIntermediateTip", "indexFingerTip",
            "middleFingerMetacarpal", "middleFingerKnuckle", "middleFingerIntermediateBase",
            "middleFingerIntermediateTip", "middleFingerTip",
            "ringFingerMetacarpal", "ringFingerKnuckle", "ringFingerIntermediateBase",
            "ringFingerIntermediateTip", "ringFingerTip",
            "littleFingerMetacarpal", "littleFingerKnuckle", "littleFingerIntermediateBase",
            "littleFingerIntermediateTip", "littleFingerTip"
        ]

        for (index, name) in jointNames.enumerated() {
            // Offset each joint slightly for variation
            let offset = SIMD3<Float>(
                Float(index % 5) * 0.01,
                Float(index / 5) * 0.01,
                0
            )
            joints[name] = makeTransform(position: basePosition + offset)
        }

        return joints
    }

    /// Helper to create a transform matrix from a position
    static func makeTransform(position: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(position.x, position.y, position.z, 1)
        )
    }

    /// Standard object positions for restaurant scene
    static let menuPosition = SIMD3<Float>(0, 0.8, -1.5)
    static let tablePosition = SIMD3<Float>(0, 0.75, -1.5)
    static let teacupPosition = SIMD3<Float>(0.2, 0.78, -1.4)
}

// MARK: - Test Classifications

enum TestClassifications {

    static let idleHighConfidence = ActionClassification(
        action: .idle,
        confidence: 0.9
    )

    static let pickingUpMenu = ActionClassification(
        action: .pickingUp,
        object: "menu",
        confidence: 0.85
    )

    static let placingMenu = ActionClassification(
        action: .placing,
        object: "menu",
        target: "table",
        confidence: 0.8
    )

    static let holdingMenu = ActionClassification(
        action: .holding,
        object: "menu",
        confidence: 0.9
    )

    static let waving = ActionClassification(
        action: .waving,
        confidence: 0.75
    )

    static let pointing = ActionClassification(
        action: .pointing,
        target: "menu_item",
        confidence: 0.7
    )

    static let lowConfidenceAction = ActionClassification(
        action: .pickingUp,
        object: "menu",
        confidence: 0.3
    )
}

// MARK: - XCTestCase Extensions

extension XCTestCase {

    /// Wait for async operation with timeout
    func waitForAsync(
        timeout: TimeInterval = 2.0,
        operation: @escaping () async throws -> Void
    ) async throws {
        let expectation = XCTestExpectation(description: "Async operation")

        Task {
            try await operation()
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: timeout)
    }

    /// Assert that a closure throws a specific error type
    func assertThrows<T: Error>(
        _ errorType: T.Type,
        _ closure: () async throws -> Void
    ) async {
        do {
            try await closure()
            XCTFail("Expected \(errorType) to be thrown")
        } catch {
            XCTAssertTrue(error is T, "Expected \(errorType) but got \(type(of: error))")
        }
    }
}

// MARK: - Async Test Helpers

/// Helper for testing async sequences
actor AsyncTestCollector<T> {
    private var collected: [T] = []

    func collect(_ value: T) {
        collected.append(value)
    }

    func getCollected() -> [T] {
        return collected
    }

    func reset() {
        collected.removeAll()
    }
}
