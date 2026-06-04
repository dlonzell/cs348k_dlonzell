import Foundation
import simd

struct ScenarioCard: Identifiable, Codable, Equatable {
    let id: String
    let setting: String
    let learnerRole: String
    let sceneGoal: String
    let localContext: String
    let targetInteractions: [String]
    let expectedObjectCategories: [String]?

    init(
        id: String,
        setting: String,
        learnerRole: String,
        sceneGoal: String,
        localContext: String,
        targetInteractions: [String],
        expectedObjectCategories: [String]? = nil
    ) {
        self.id = id
        self.setting = setting
        self.learnerRole = learnerRole
        self.sceneGoal = sceneGoal
        self.localContext = localContext
        self.targetInteractions = targetInteractions
        self.expectedObjectCategories = expectedObjectCategories
    }
}

struct InteractionWorldPlan: Identifiable, Codable, Equatable {
    let id: String
    let scenario: ScenarioCard
    let objects: [WorldObjectSpec]
    let tasks: [InteractionTask]
}

struct WorldObjectSpec: Identifiable, Codable, Equatable {
    let id: String
    let displayName: String
    let description: String
    let kind: WorldObjectKind
    let position: SIMD3<Float>
    let size: SIMD3<Float>
    let color: WorldObjectColor
    let isInteractive: Bool
    let visualAsset: WorldObjectVisualAsset?
    let assetCard: WorldObjectAssetCard?

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case displayNameSnake = "display_name"
        case description
        case kind
        case category
        case position
        case size
        case color
        case isInteractive
        case isInteractiveSnake = "is_interactive"
        case interactive
        case visualAsset
        case visualAssetSnake = "visual_asset"
        case assetCard
        case assetCardSnake = "asset_card"
    }

    init(
        id: String,
        displayName: String,
        description: String = "",
        kind: WorldObjectKind,
        position: SIMD3<Float>,
        size: SIMD3<Float>,
        color: WorldObjectColor,
        isInteractive: Bool,
        visualAsset: WorldObjectVisualAsset? = nil,
        assetCard: WorldObjectAssetCard? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.kind = kind
        self.position = position
        self.size = size
        self.color = color
        self.isInteractive = isInteractive
        self.visualAsset = visualAsset
        self.assetCard = assetCard
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
            ?? container.decodeIfPresent(String.self, forKey: .displayNameSnake)
            ?? id
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? displayName
        kind = try container.decodeIfPresent(WorldObjectKind.self, forKey: .kind)
            ?? WorldObjectKind.generic(category: container.decodeIfPresent(String.self, forKey: .category) ?? "smallObject")
        position = try container.decode(SIMD3<Float>.self, forKey: .position)
        size = try container.decode(SIMD3<Float>.self, forKey: .size)
        color = try container.decodeIfPresent(WorldObjectColor.self, forKey: .color) ?? .gray
        isInteractive = try container.decodeIfPresent(Bool.self, forKey: .isInteractive)
            ?? container.decodeIfPresent(Bool.self, forKey: .isInteractiveSnake)
            ?? container.decodeIfPresent(Bool.self, forKey: .interactive)
            ?? true
        visualAsset = try container.decodeIfPresent(WorldObjectVisualAsset.self, forKey: .visualAsset)
            ?? container.decodeIfPresent(WorldObjectVisualAsset.self, forKey: .visualAssetSnake)
        assetCard = try container.decodeIfPresent(WorldObjectAssetCard.self, forKey: .assetCard)
            ?? container.decodeIfPresent(WorldObjectAssetCard.self, forKey: .assetCardSnake)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(description, forKey: .description)
        try container.encode(kind, forKey: .kind)
        try container.encode(position, forKey: .position)
        try container.encode(size, forKey: .size)
        try container.encode(color, forKey: .color)
        try container.encode(isInteractive, forKey: .isInteractive)
        try container.encodeIfPresent(visualAsset, forKey: .visualAsset)
        try container.encodeIfPresent(assetCard, forKey: .assetCard)
    }

    func withVisualAsset(_ visualAsset: WorldObjectVisualAsset?) -> WorldObjectSpec {
        WorldObjectSpec(
            id: id,
            displayName: displayName,
            description: description,
            kind: kind,
            position: position,
            size: size,
            color: color,
            isInteractive: isInteractive,
            visualAsset: visualAsset,
            assetCard: assetCard
        )
    }

    func withAssetCard(_ assetCard: WorldObjectAssetCard?) -> WorldObjectSpec {
        WorldObjectSpec(
            id: id,
            displayName: displayName,
            description: description,
            kind: kind,
            position: position,
            size: size,
            color: color,
            isInteractive: isInteractive,
            visualAsset: visualAsset,
            assetCard: assetCard
        )
    }
}

struct WorldObjectAssetCard: Codable, Equatable {
    let layoutRole: WorldObjectLayoutRole
    let assetKind: WorldObjectAssetKind
    let supportSurfaceId: String?
    let orientationHint: WorldObjectOrientationHint
    let frontHint: WorldObjectFrontHint
    let targetSize: SIMD3<Float>
    let restingPolicy: WorldObjectRestingPolicy
}

enum WorldObjectLayoutRole: String, Codable, Equatable {
    case surface
    case sourceObject
    case targetContainer
    case payment
    case uprightContext
    case personMarker
    case contextObject
}

enum WorldObjectAssetKind: String, Codable, Equatable {
    case surface
    case smallObject
    case container
    case paymentDevice
    case menu
    case displayFixture
    case personMarker
    case cup
    case tray
}

enum WorldObjectOrientationHint: String, Codable, Equatable {
    case horizontalSurface
    case compact
    case tabletopFlat
    case uprightFacingLearner
    case openTopUpright
    case shallowTray
}

enum WorldObjectFrontHint: String, Codable, Equatable {
    case facesLearner
    case unconstrained
}

enum WorldObjectRestingPolicy: String, Codable, Equatable {
    case bottomOnSupport
    case centerAtPosition
}

struct WorldObjectVisualAsset: Codable, Equatable {
    let format: WorldObjectVisualFormat
    let source: WorldObjectVisualSource
    let status: WorldObjectRealizationStatus
    let remoteURL: URL?
    let localURL: URL?
    let previewRemoteURL: URL?
    let previewLocalURL: URL?
    let realizedPosition: SIMD3<Float>?
    let realizedSize: SIMD3<Float>?
    let canonicalPose: WorldObjectCanonicalPose?
    let notes: String?

    init(
        format: WorldObjectVisualFormat,
        source: WorldObjectVisualSource,
        status: WorldObjectRealizationStatus,
        remoteURL: URL?,
        localURL: URL?,
        previewRemoteURL: URL? = nil,
        previewLocalURL: URL? = nil,
        realizedPosition: SIMD3<Float>? = nil,
        realizedSize: SIMD3<Float>? = nil,
        canonicalPose: WorldObjectCanonicalPose? = nil,
        notes: String?
    ) {
        self.format = format
        self.source = source
        self.status = status
        self.remoteURL = remoteURL
        self.localURL = localURL
        self.previewRemoteURL = previewRemoteURL
        self.previewLocalURL = previewLocalURL
        self.realizedPosition = realizedPosition
        self.realizedSize = realizedSize
        self.canonicalPose = canonicalPose
        self.notes = notes
    }
}

struct WorldObjectCanonicalPose: Codable, Equatable {
    let selectedCandidate: String?
    let upAxis: String?
    let bottomAxis: String?
    let frontAxis: String?
    let restingPose: String?
    let confidence: Float?
    let reason: String?
    let candidateGridURL: URL?
}

enum WorldObjectVisualFormat: String, Codable, Equatable {
    case gaussianSplatPLY
    case usd
    case usdz
    case primitiveProxy
}

enum WorldObjectVisualSource: String, Codable, Equatable {
    case sam3D
    case usdzService
    case handAuthored
    case fallback
}

enum WorldObjectRealizationStatus: String, Codable, Equatable {
    case planned
    case realized
    case fallbackPrimitive
    case failed
}

enum WorldObjectKind: Codable, Equatable, Hashable {
    case counter
    case menu
    case displayCase
    case cup
    case tray
    case cardReader
    case npcMarker
    case generic(category: String)

    static let supportedKindNames = [
        "counter",
        "menu",
        "displayCase",
        "cup",
        "tray",
        "cardReader",
        "npcMarker",
        "generic"
    ]

    static let genericCategories = [
        "container",
        "flatSurface",
        "uprightObject",
        "marker",
        "smallObject"
    ]

    private enum CodingKeys: String, CodingKey {
        case type
        case category
    }

    init(from decoder: Decoder) throws {
        if let singleValue = try? decoder.singleValueContainer(),
           let rawValue = try? singleValue.decode(String.self) {
            self = try Self.from(type: rawValue, category: nil)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let category = try container.decodeIfPresent(String.self, forKey: .category)
        self = try Self.from(type: type, category: category)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(typeName, forKey: .type)

        if case .generic(let category) = self {
            try container.encode(category, forKey: .category)
        }
    }

    private static func from(type: String, category: String?) throws -> WorldObjectKind {
        switch type {
        case "counter":
            return .counter
        case "menu":
            return .menu
        case "displayCase", "display_case":
            return .displayCase
        case "cup":
            return .cup
        case "tray":
            return .tray
        case "cardReader", "card_reader":
            return .cardReader
        case "npcMarker", "npc_marker":
            return .npcMarker
        case "generic":
            return .generic(category: category ?? "smallObject")
        default:
            return .generic(category: category ?? type)
        }
    }

    var typeName: String {
        switch self {
        case .counter:
            return "counter"
        case .menu:
            return "menu"
        case .displayCase:
            return "displayCase"
        case .cup:
            return "cup"
        case .tray:
            return "tray"
        case .cardReader:
            return "cardReader"
        case .npcMarker:
            return "npcMarker"
        case .generic:
            return "generic"
        }
    }
}

enum WorldObjectColor: String, Codable, CaseIterable {
    case brown
    case red
    case blue
    case cyan
    case yellow
    case green
    case gray
    case purple

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = (try? container.decode(String.self))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch rawValue {
        case "brown", "wood", "tan", "beige":
            self = .brown
        case "red", "pink":
            self = .red
        case "blue", "navy":
            self = .blue
        case "cyan", "teal":
            self = .cyan
        case "yellow", "gold", "orange":
            self = .yellow
        case "green":
            self = .green
        case "purple", "violet":
            self = .purple
        default:
            self = .gray
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct InteractionTask: Identifiable, Codable, Equatable {
    let id: String
    let instruction: String
    let requiredObjectIds: [String]
    let expectedInteraction: InteractionKind
}

enum InteractionKind: Codable, Equatable {
    case indicate(objectId: String)
    case tap(objectId: String)
    case drag(objectId: String)
    case place(objectId: String, targetId: String)
    case gesture(GestureKind, targetId: String?)

    private enum CodingKeys: String, CodingKey {
        case type
        case objectId
        case targetId
        case gesture
        case kind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "indicate":
            self = .indicate(objectId: try container.decode(String.self, forKey: .objectId))
        case "tap":
            self = .tap(objectId: try container.decode(String.self, forKey: .objectId))
        case "drag":
            self = .drag(objectId: try container.decode(String.self, forKey: .objectId))
        case "place":
            self = .place(
                objectId: try container.decode(String.self, forKey: .objectId),
                targetId: try container.decode(String.self, forKey: .targetId)
            )
        case "gesture":
            let gesture = try container.decodeIfPresent(GestureKind.self, forKey: .gesture)
                ?? container.decode(GestureKind.self, forKey: .kind)
            self = .gesture(
                gesture,
                targetId: try container.decodeIfPresent(String.self, forKey: .targetId)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown InteractionKind type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .indicate(let objectId):
            try container.encode("indicate", forKey: .type)
            try container.encode(objectId, forKey: .objectId)
        case .tap(let objectId):
            try container.encode("tap", forKey: .type)
            try container.encode(objectId, forKey: .objectId)
        case .drag(let objectId):
            try container.encode("drag", forKey: .type)
            try container.encode(objectId, forKey: .objectId)
        case .place(let objectId, let targetId):
            try container.encode("place", forKey: .type)
            try container.encode(objectId, forKey: .objectId)
            try container.encode(targetId, forKey: .targetId)
        case .gesture(let gesture, let targetId):
            try container.encode("gesture", forKey: .type)
            try container.encode(gesture, forKey: .gesture)
            try container.encodeIfPresent(targetId, forKey: .targetId)
        }
    }
}

enum GestureKind: String, Codable, CaseIterable {
    case wave
    case point
    case thumbsUp
    case openPalm
}

enum InteractionEvent: Equatable {
    case select(objectId: String)
    case dragStarted(objectId: String)
    case placed(objectId: String, targetId: String?)
    case gesture(GestureKind, targetId: String?)

    var objectId: String? {
        switch self {
        case .select(let objectId), .dragStarted(let objectId):
            return objectId
        case .placed(let objectId, _):
            return objectId
        case .gesture:
            return nil
        }
    }
}

struct InteractionLogEntry: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let taskId: String
    let eventDescription: String
    let matched: Bool
}

struct InteractionEvaluationResult: Codable, Equatable {
    let objectCoveragePassed: Int
    let objectCoverageTotal: Int
    let handlerCoveragePassed: Int
    let handlerCoverageTotal: Int
    let completedTasks: Int
    let totalTasks: Int
    let firstFailedTaskId: String?

    var objectCoverageSummary: String {
        "\(objectCoveragePassed)/\(objectCoverageTotal)"
    }

    var handlerCoverageSummary: String {
        "\(handlerCoveragePassed)/\(handlerCoverageTotal)"
    }

    var completionSummary: String {
        "\(completedTasks)/\(totalTasks)"
    }
}

enum ManualEvaluationMetric: String, Codable, CaseIterable, Identifiable, Hashable {
    case objectRealization
    case spatialPlausibility
    case contextSufficiency
    case affordanceInstrumentation
    case taskCompletion

    var id: String { rawValue }

    var title: String {
        switch self {
        case .objectRealization:
            return "Object realized"
        case .spatialPlausibility:
            return "Spatially plausible"
        case .contextSufficiency:
            return "Context sufficient"
        case .affordanceInstrumentation:
            return "Affordance works"
        case .taskCompletion:
            return "Task completes"
        }
    }

    var description: String {
        switch self {
        case .objectRealization:
            return "The required object or objects for this interaction are visible in the generated 3D scene and are recognizable enough to support the scenario."
        case .spatialPlausibility:
            return "The objects are positioned at a reasonable distance, height, and relation to each other for the learner to perform the action."
        case .contextSufficiency:
            return "The immediate surrounding objects make the interaction semantically understandable, not just mechanically possible."
        case .affordanceInstrumentation:
            return "The relevant objects have the expected input/collision/gesture handler so the system can detect the interaction."
        case .taskCompletion:
            return "A tester can actually complete this task in the simulator or device using the available interaction primitive."
        }
    }
}

enum ManualEvaluationRating: String, Codable, CaseIterable, Identifiable {
    case unscored
    case yes
    case partial
    case no

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unscored:
            return "Unset"
        case .yes:
            return "Yes"
        case .partial:
            return "Partial"
        case .no:
            return "No"
        }
    }
}

enum GeneratedTaskFidelityRating: String, CaseIterable, Identifiable, Codable {
    case unscored
    case faithful
    case compromise
    case missed
    case invalid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unscored:
            return "Unset"
        case .faithful:
            return "Faithful"
        case .compromise:
            return "Compromise"
        case .missed:
            return "Missed"
        case .invalid:
            return "Invalid"
        }
    }
}

enum GeneratedObjectRating: String, CaseIterable, Identifiable, Codable {
    case unscored
    case expected
    case acceptable
    case hallucinated

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unscored:
            return "Unset"
        case .expected:
            return "Expected"
        case .acceptable:
            return "Acceptable"
        case .hallucinated:
            return "Hallucinated"
        }
    }
}

enum ScenarioLayoutRating: String, CaseIterable, Identifiable, Codable {
    case unscored
    case plausible
    case partiallyPlausible
    case implausible

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unscored:
            return "Unset"
        case .plausible:
            return "Plausible"
        case .partiallyPlausible:
            return "Partial"
        case .implausible:
            return "Implausible"
        }
    }
}

enum ScenarioFidelityRating: String, CaseIterable, Identifiable, Codable {
    case unscored
    case faithful
    case partiallyFaithful
    case notFaithful

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unscored:
            return "Unset"
        case .faithful:
            return "Faithful"
        case .partiallyFaithful:
            return "Partial"
        case .notFaithful:
            return "Not faithful"
        }
    }
}

struct ManualEvaluationSnapshot: Codable, Equatable {
    let scenarioLayoutRating: ScenarioLayoutRating
    let scenarioFidelityRating: ScenarioFidelityRating
    let generatedObjectRatings: [GeneratedObjectRatingSnapshot]
    let generatedTaskRatings: [GeneratedTaskFidelitySnapshot]
    let taskMetricRatings: [TaskMetricRatingSnapshot]
    let answeredCount: Int
    let totalCount: Int
    let yesCount: Int
}

struct GeneratedObjectRatingSnapshot: Codable, Equatable {
    let objectId: String
    let rating: GeneratedObjectRating
}

struct GeneratedTaskFidelitySnapshot: Codable, Equatable {
    let taskId: String
    let rating: GeneratedTaskFidelityRating
}

struct TaskMetricRatingSnapshot: Codable, Equatable {
    let taskId: String
    let metric: ManualEvaluationMetric
    let rating: ManualEvaluationRating
}

struct InteractionEventLogSnapshot: Codable, Equatable {
    let timestamp: Date
    let taskId: String
    let eventDescription: String
    let matched: Bool
}

enum InteractionWorldValidationError: Error, Equatable, LocalizedError, Codable {
    case duplicateObjectId(String)
    case duplicateTaskId(String)
    case taskReferencesMissingObject(taskId: String, objectId: String)
    case unsupportedInteraction(taskId: String, interaction: InteractionKind)

    var errorDescription: String? {
        switch self {
        case .duplicateObjectId(let objectId):
            return "Duplicate object id: \(objectId)"
        case .duplicateTaskId(let taskId):
            return "Duplicate task id: \(taskId)"
        case .taskReferencesMissingObject(let taskId, let objectId):
            return "Task \(taskId) references missing object \(objectId)"
        case .unsupportedInteraction(let taskId, let interaction):
            return "Task \(taskId) uses unsupported interaction \(interaction)"
        }
    }
}
