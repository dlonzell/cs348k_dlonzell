import Foundation
import CoreVideo
import simd

/// Result of VLM action classification
struct ActionClassification: Codable, Equatable {
    /// The detected action type
    let action: ActionType

    /// The object being interacted with (if any)
    let object: String?

    /// The target of the action (if any)
    let target: String?

    /// Confidence score (0.0 - 1.0)
    let confidence: Float

    /// Timestamp when this classification was made
    let timestamp: Date

    /// Free-form summary of what the VLM sees in the scene
    /// This allows the LLM to describe complex interactions naturally
    let sceneSummary: String?

    init(action: ActionType, object: String? = nil, target: String? = nil, confidence: Float, timestamp: Date = Date(), sceneSummary: String? = nil) {
        self.action = action
        self.object = object
        self.target = target
        self.confidence = confidence
        self.timestamp = timestamp
        self.sceneSummary = sceneSummary
    }
}

/// Types of actions the VLM can detect
enum ActionType: String, Codable, CaseIterable {
    case idle = "idle"
    case reaching = "reaching"
    case pickingUp = "picking_up"
    case holding = "holding"
    case placing = "placing"
    case pointing = "pointing"
    case waving = "waving"
    case gesturing = "gesturing"
    case unknown = "unknown"

    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .reaching: return "Reaching"
        case .pickingUp: return "Picking Up"
        case .holding: return "Holding"
        case .placing: return "Placing"
        case .pointing: return "Pointing"
        case .waving: return "Waving"
        case .gesturing: return "Gesturing"
        case .unknown: return "Unknown"
        }
    }
}

/// Objects that can be interacted with in the scene
enum SceneObject: String, Codable, CaseIterable {
    case menu = "menu"
    case table = "table"
    case teacup = "teacup"
    case plate = "plate"
    case chopsticks = "chopsticks"
    case napkin = "napkin"

    var displayName: String {
        rawValue.capitalized
    }
}

/// Protocol for scene analyzers (mock or real VLM)
protocol SceneAnalyzer {
    /// Analyze a frame and return action classification
    func analyze(frame: SceneFrame) async throws -> ActionClassification

    /// Whether the analyzer is currently processing
    var isAnalyzing: Bool { get }
}

/// Represents a captured frame for analysis
struct SceneFrame {
    /// The pixel buffer containing the rendered scene
    let pixelBuffer: CVPixelBuffer?

    /// Objects known to be in the scene (for context)
    let sceneObjects: [String]

    /// Current hand joint positions (for additional context)
    let leftHandJoints: [String: simd_float4x4]
    let rightHandJoints: [String: simd_float4x4]

    /// Timestamp of the frame
    let timestamp: Date

    init(
        pixelBuffer: CVPixelBuffer? = nil,
        sceneObjects: [String] = [],
        leftHandJoints: [String: simd_float4x4] = [:],
        rightHandJoints: [String: simd_float4x4] = [:],
        timestamp: Date = Date()
    ) {
        self.pixelBuffer = pixelBuffer
        self.sceneObjects = sceneObjects
        self.leftHandJoints = leftHandJoints
        self.rightHandJoints = rightHandJoints
        self.timestamp = timestamp
    }
}
