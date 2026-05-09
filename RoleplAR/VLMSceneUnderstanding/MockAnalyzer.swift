import Foundation
import simd

/// Mock scene analyzer for testing the VLM pipeline without the actual model
class MockAnalyzer: SceneAnalyzer, ObservableObject {
    @Published private(set) var isAnalyzing = false
    @Published var lastClassification: ActionClassification?

    /// Simulated delay to mimic VLM inference time (in seconds)
    var simulatedDelay: TimeInterval = 0.1

    /// Whether to use heuristic-based detection from hand positions
    var useHeuristicDetection = true

    /// Whether to use object position tracking (for simulator testing without hands)
    var useObjectPositionTracking = false

    /// Known objects in the scene for mock detection
    var sceneObjects: [String] = ["menu", "table"]

    /// Distance threshold for "near object" detection (in meters)
    private let nearThreshold: Float = 0.15

    /// Previous hand positions for motion detection
    private var previousLeftWrist: simd_float3?
    private var previousRightWrist: simd_float3?

    /// Object positions for tracking mode (updated externally)
    var objectPositions: [String: simd_float3] = [:]
    private var previousObjectPositions: [String: simd_float3] = [:]

    /// Injected classification for manual testing
    var injectedClassification: ActionClassification?

    func analyze(frame: SceneFrame) async throws -> ActionClassification {
        isAnalyzing = true
        defer { isAnalyzing = false }

        // Simulate inference delay
        try await Task.sleep(nanoseconds: UInt64(simulatedDelay * 1_000_000_000))

        let classification: ActionClassification

        // Check for injected classification first (for manual testing)
        if let injected = injectedClassification {
            classification = injected
            injectedClassification = nil // Clear after use
        } else if useObjectPositionTracking {
            classification = objectPositionClassification()
        } else if useHeuristicDetection {
            classification = heuristicClassification(from: frame)
        } else {
            classification = randomClassification(sceneObjects: frame.sceneObjects)
        }

        await MainActor.run {
            lastClassification = classification
        }

        return classification
    }

    /// Inject a classification manually (for simulator testing)
    func injectClassification(_ classification: ActionClassification) {
        injectedClassification = classification
    }

    /// Classification based on object position changes (for simulator without hands)
    private func objectPositionClassification() -> ActionClassification {
        // Check for object movement
        for (objectName, currentPos) in objectPositions {
            if let previousPos = previousObjectPositions[objectName] {
                let movement = simd_distance(currentPos, previousPos)

                // Object is being moved
                if movement > 0.02 { // 2cm movement threshold
                    let tableHeight: Float = 0.75

                    // Moving up = picking up
                    if currentPos.y > previousPos.y + 0.05 {
                        previousObjectPositions = objectPositions
                        return ActionClassification(
                            action: .pickingUp,
                            object: objectName,
                            confidence: 0.80
                        )
                    }

                    // Moving down toward table = placing
                    if currentPos.y < previousPos.y - 0.03 && currentPos.y < tableHeight + 0.15 {
                        previousObjectPositions = objectPositions
                        return ActionClassification(
                            action: .placing,
                            object: objectName,
                            target: "table",
                            confidence: 0.78
                        )
                    }

                    // Lateral movement while elevated = holding
                    if currentPos.y > tableHeight + 0.1 {
                        previousObjectPositions = objectPositions
                        return ActionClassification(
                            action: .holding,
                            object: objectName,
                            confidence: 0.75
                        )
                    }
                }
            }
        }

        previousObjectPositions = objectPositions
        return ActionClassification(action: .idle, confidence: 0.6)
    }

    /// Update object position (call from the view when objects move)
    func updateObjectPosition(_ objectName: String, position: simd_float3) {
        objectPositions[objectName] = position
    }

    /// Heuristic-based classification using hand positions
    private func heuristicClassification(from frame: SceneFrame) -> ActionClassification {
        // Check if we have hand data
        let hasLeftHand = !frame.leftHandJoints.isEmpty
        let hasRightHand = !frame.rightHandJoints.isEmpty

        guard hasLeftHand || hasRightHand else {
            return ActionClassification(action: .idle, confidence: 0.9)
        }

        // Get wrist positions
        let leftWrist = frame.leftHandJoints["wrist"].map { extractPosition(from: $0) }
        let rightWrist = frame.rightHandJoints["wrist"].map { extractPosition(from: $0) }

        // Get fingertip positions for gesture detection
        let leftIndexTip = frame.leftHandJoints["indexFingerTip"].map { extractPosition(from: $0) }
        let rightIndexTip = frame.rightHandJoints["indexFingerTip"].map { extractPosition(from: $0) }

        // Detect motion
        var isMoving = false
        if let current = rightWrist, let previous = previousRightWrist {
            let movement = simd_distance(current, previous)
            isMoving = movement > 0.02 // 2cm movement threshold
        }
        previousRightWrist = rightWrist
        previousLeftWrist = leftWrist

        // Simple heuristics for action detection
        // In reality, the VLM would do this visually

        // Check hand height relative to table (assuming table at y=0.75m)
        let tableHeight: Float = 0.75
        let menuPosition = simd_float3(0, 0.8, -1.5) // Approximate menu position

        if let wrist = rightWrist ?? leftWrist {
            // Hand moving at face level = waving (check first for high positions)
            if wrist.y > 1.2 && isMoving {
                return ActionClassification(
                    action: .waving,
                    confidence: 0.65
                )
            }

            // Hand near menu position = picking up or holding
            let distanceToMenu = simd_distance(wrist, menuPosition)
            if distanceToMenu < nearThreshold {
                if isMoving {
                    return ActionClassification(
                        action: .pickingUp,
                        object: "menu",
                        confidence: 0.75
                    )
                } else {
                    return ActionClassification(
                        action: .holding,
                        object: "menu",
                        confidence: 0.8
                    )
                }
            }

            // Hand extended and index finger pointing = pointing
            if let indexTip = rightIndexTip ?? leftIndexTip {
                let fingerExtension = simd_distance(wrist, indexTip)
                if fingerExtension > 0.15 { // Extended finger
                    return ActionClassification(
                        action: .pointing,
                        confidence: 0.6
                    )
                }
            }

            // Hand above table level and moving = placing
            if wrist.y > tableHeight + 0.1 && isMoving {
                return ActionClassification(
                    action: .placing,
                    object: "menu",
                    target: "table",
                    confidence: 0.7
                )
            }

            // Hand moving toward object = reaching
            if isMoving && wrist.y > tableHeight {
                return ActionClassification(
                    action: .reaching,
                    object: nearestObject(to: wrist),
                    confidence: 0.6
                )
            }
        }

        // Default to idle
        return ActionClassification(action: .idle, confidence: 0.5)
    }

    /// Random classification for basic testing
    private func randomClassification(sceneObjects: [String]) -> ActionClassification {
        let actions: [ActionType] = [.idle, .reaching, .pickingUp, .holding, .placing]
        let action = actions.randomElement() ?? .idle

        let object: String? = (action != .idle && action != .waving) ? sceneObjects.randomElement() : nil
        let target: String? = (action == .placing) ? "table" : nil

        return ActionClassification(
            action: action,
            object: object,
            target: target,
            confidence: Float.random(in: 0.6...0.95)
        )
    }

    /// Extract position from transform matrix
    private func extractPosition(from transform: simd_float4x4) -> simd_float3 {
        return simd_float3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
    }

    /// Find nearest object to a position
    private func nearestObject(to position: simd_float3) -> String? {
        // In a real implementation, this would check actual object positions
        // For mock, just return menu if hand is in the general area
        let menuArea = simd_float3(0, 0.8, -1.5)
        if simd_distance(position, menuArea) < 0.5 {
            return "menu"
        }
        return nil
    }
}
