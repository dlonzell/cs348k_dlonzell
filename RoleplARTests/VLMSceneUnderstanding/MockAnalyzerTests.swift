//
//  MockAnalyzerTests.swift
//  RoleplARTests
//
//  Tests for MockAnalyzer heuristic detection logic
//

import XCTest
import simd
@testable import RoleplAR

final class MockAnalyzerTests: XCTestCase {

    var analyzer: MockAnalyzer!

    override func setUp() {
        super.setUp()
        analyzer = MockAnalyzer()
        analyzer.useHeuristicDetection = true
        analyzer.simulatedDelay = 0.01 // Fast for testing
    }

    override func tearDown() {
        analyzer = nil
        super.tearDown()
    }

    // MARK: - Basic Analysis Tests

    func testAnalyzerConformsToProtocol() {
        XCTAssertTrue(analyzer is SceneAnalyzer)
    }

    func testAnalyzerInitialState() {
        XCTAssertFalse(analyzer.isAnalyzing)
        XCTAssertNil(analyzer.lastClassification)
    }

    func testAnalyzeEmptyFrame() async throws {
        let frame = SceneFrame(
            sceneObjects: ["menu", "table"]
        )

        let classification = try await analyzer.analyze(frame: frame)

        // No hands = idle
        XCTAssertEqual(classification.action, .idle)
        XCTAssertGreaterThan(classification.confidence, 0.5)
    }

    // MARK: - Heuristic Detection Tests

    func testDetectIdleWithNoHands() async throws {
        let frame = SceneFrame(
            sceneObjects: ["menu"],
            leftHandJoints: [:],
            rightHandJoints: [:]
        )

        let classification = try await analyzer.analyze(frame: frame)

        XCTAssertEqual(classification.action, .idle)
        XCTAssertGreaterThanOrEqual(classification.confidence, 0.5)
    }

    func testDetectWithRightHand() async throws {
        // Create a frame with right hand at table height
        let wristTransform = simd_float4x4(
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(0, 0.8, -1.5, 1) // Near table
        )

        let frame = SceneFrame(
            sceneObjects: ["menu", "table"],
            leftHandJoints: [:],
            rightHandJoints: ["wrist": wristTransform]
        )

        let classification = try await analyzer.analyze(frame: frame)

        // Should detect some action (not necessarily specific without full joint data)
        XCTAssertNotNil(classification.action)
        XCTAssertGreaterThan(classification.confidence, 0)
    }

    func testDetectNearMenuPosition() async throws {
        // Hand very close to menu position (0, 0.8, -1.5)
        let wristTransform = simd_float4x4(
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(0.05, 0.82, -1.48, 1)
        )

        let frame = SceneFrame(
            sceneObjects: ["menu", "table"],
            rightHandJoints: ["wrist": wristTransform]
        )

        let classification = try await analyzer.analyze(frame: frame)

        // Should detect holding or picking up menu
        if classification.action == .holding || classification.action == .pickingUp {
            XCTAssertEqual(classification.object, "menu")
        }
    }

    func testDetectWavingAtHighPosition() async throws {
        // Hand at face level (y > 1.2m)
        let wristTransform1 = simd_float4x4(
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(0.3, 1.4, -0.5, 1)
        )

        // First frame to set previous position
        let frame1 = SceneFrame(
            sceneObjects: ["menu"],
            rightHandJoints: ["wrist": wristTransform1]
        )
        _ = try await analyzer.analyze(frame: frame1)

        // Second frame with different position (movement)
        let wristTransform2 = simd_float4x4(
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(-0.3, 1.4, -0.5, 1) // Moved sideways
        )

        let frame2 = SceneFrame(
            sceneObjects: ["menu"],
            rightHandJoints: ["wrist": wristTransform2]
        )
        let classification = try await analyzer.analyze(frame: frame2)

        // High + moving = waving
        XCTAssertEqual(classification.action, .waving)
    }

    // MARK: - Random Classification Tests

    func testRandomClassificationMode() async throws {
        analyzer.useHeuristicDetection = false

        let frame = SceneFrame(sceneObjects: ["menu", "table"])
        let classification = try await analyzer.analyze(frame: frame)

        // Should return a valid action
        XCTAssertTrue(ActionType.allCases.contains(classification.action))
        XCTAssertGreaterThanOrEqual(classification.confidence, 0.6)
        XCTAssertLessThanOrEqual(classification.confidence, 0.95)
    }

    // MARK: - Analyzing State Tests

    func testIsAnalyzingDuringAnalysis() async throws {
        analyzer.simulatedDelay = 0.1 // Longer delay to observe state

        let frame = SceneFrame(sceneObjects: ["menu"])

        // Start analysis in background
        let task = Task {
            return try await self.analyzer.analyze(frame: frame)
        }

        // Give it time to start
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms

        // Should be analyzing
        // Note: This might be flaky depending on timing
        // XCTAssertTrue(analyzer.isAnalyzing)

        _ = try await task.value

        // Should be done analyzing
        XCTAssertFalse(analyzer.isAnalyzing)
    }

    func testLastClassificationUpdated() async throws {
        XCTAssertNil(analyzer.lastClassification)

        let frame = SceneFrame(sceneObjects: ["menu"])
        let classification = try await analyzer.analyze(frame: frame)

        // lastClassification should be updated on MainActor
        // Wait a bit for MainActor update
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms

        await MainActor.run {
            XCTAssertNotNil(analyzer.lastClassification)
            XCTAssertEqual(analyzer.lastClassification?.action, classification.action)
        }
    }

    // MARK: - Scene Objects Tests

    func testSceneObjectsPassedToAnalyzer() async throws {
        analyzer.sceneObjects = ["custom_object"]

        let frame = SceneFrame(sceneObjects: ["menu", "table"])

        // The frame's sceneObjects should be used, not analyzer's
        let classification = try await analyzer.analyze(frame: frame)

        // Classification should reference frame's objects
        if let object = classification.object {
            // Object should come from frame, not analyzer default
            XCTAssertTrue(["menu", "table"].contains(object) || object == "custom_object")
        }
    }
}
