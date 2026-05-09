import ARKit
import RealityKit

/// Manages hand tracking using ARKit's HandTrackingProvider
@MainActor
class HandTrackingSystem: ObservableObject {
    @Published var leftHandJoints: [String: simd_float4x4] = [:]
    @Published var rightHandJoints: [String: simd_float4x4] = [:]
    @Published var isTracking = false

    private var session: ARKitSession?
    private var handTrackingProvider: HandTrackingProvider?
    private var isRunning = false

    /// Start hand tracking
    func start() async {
        guard !isRunning else {
            vlmLog("Hand tracking already running", category: "Hands")
            return
        }

        vlmLog("Checking hand tracking support...", category: "Hands")

        // Check if hand tracking is supported
        guard HandTrackingProvider.isSupported else {
            vlmError("Hand tracking NOT SUPPORTED on this device", category: "Hands")
            return
        }

        vlmLog("Hand tracking is supported", category: "Hands")

        let session = ARKitSession()

        // Check and request authorization for hand tracking
        vlmLog("Checking hand tracking authorization...", category: "Hands")
        var authStatus = await session.queryAuthorization(for: [.handTracking])
        vlmLog("Initial auth status: \(String(describing: authStatus[.handTracking]))", category: "Hands")

        // Request authorization if not yet determined
        if authStatus[.handTracking] == nil {
            vlmLog("Requesting hand tracking authorization...", category: "Hands")
            authStatus = await session.requestAuthorization(for: [.handTracking])
            vlmLog("Auth response: \(String(describing: authStatus[.handTracking]))", category: "Hands")
        }

        guard authStatus[.handTracking] == .allowed else {
            vlmError("Hand tracking NOT AUTHORIZED: \(String(describing: authStatus[.handTracking]))", category: "Hands")
            return
        }

        vlmLog("Hand tracking authorized, starting provider...", category: "Hands")
        let handTrackingProvider = HandTrackingProvider()

        self.session = session
        self.handTrackingProvider = handTrackingProvider

        do {
            try await session.run([handTrackingProvider])
            isRunning = true
            isTracking = true
            vlmLog("Hand tracking STARTED successfully", category: "Hands")

            // Start processing hand updates in a separate Task (don't block start())
            Task {
                await processHandUpdates()
            }
        } catch {
            vlmError("Failed to start hand tracking: \(error)", category: "Hands")
        }
    }

    /// Stop hand tracking
    func stop() {
        isRunning = false
        isTracking = false
        session?.stop()
        session = nil
        handTrackingProvider = nil

        // Clear hand data
        leftHandJoints.removeAll()
        rightHandJoints.removeAll()

        print("Hand tracking stopped")
    }

    /// Process hand tracking updates
    private func processHandUpdates() async {
        guard let provider = handTrackingProvider else { return }

        for await update in provider.anchorUpdates {
            guard isRunning else { break }

            let anchor = update.anchor

            // Skip if hand is not tracked
            guard anchor.isTracked else {
                clearHandData(for: anchor.chirality)
                continue
            }

            // Extract joint transforms
            let jointData = extractJointData(from: anchor)

            // Update based on chirality
            switch anchor.chirality {
            case .left:
                leftHandJoints = jointData
            case .right:
                rightHandJoints = jointData
            @unknown default:
                break
            }
        }
    }

    /// Extract joint positions from a hand anchor
    private func extractJointData(from anchor: HandAnchor) -> [String: simd_float4x4] {
        var jointData: [String: simd_float4x4] = [:]

        guard let skeleton = anchor.handSkeleton else { return jointData }

        // Get world transform for the hand
        let handTransform = anchor.originFromAnchorTransform

        // Process all joints
        for jointName in HandSkeleton.JointName.allCases {
            let joint = skeleton.joint(jointName)

            // Only include tracked joints
            guard joint.isTracked else { continue }

            // Calculate world position: hand transform * joint transform
            let worldTransform = handTransform * joint.anchorFromJointTransform
            jointData[jointName.description] = worldTransform
        }

        return jointData
    }

    /// Clear hand data when tracking is lost
    private func clearHandData(for chirality: HandAnchor.Chirality) {
        switch chirality {
        case .left:
            leftHandJoints.removeAll()
        case .right:
            rightHandJoints.removeAll()
        @unknown default:
            break
        }
    }
}

// Note: HandSkeleton.JointName already conforms to CustomStringConvertible in ARKit
