import Foundation

@MainActor
final class InteractionWorldGenerator: ObservableObject {
    private let client: InteractionWorldLLMClient
    private let maxAttempts: Int

    init(
        client: InteractionWorldLLMClient = OpenAIInteractionWorldLLMClient(),
        maxAttempts: Int = 3
    ) {
        self.client = client
        self.maxAttempts = maxAttempts
    }

    func generatePlan(for scenario: ScenarioCard) async throws -> GenerationResult {
        let pipelineStart = Date()
        var attempts: [GenerationAttempt] = []

        for attemptNumber in 1...maxAttempts {
            let attemptStart = Date()
            var rawObjectsJSON: String?
            var rawTasksJSON: String?

            do {
                rawObjectsJSON = try await client.completeJSON(
                    prompt: buildObjectGenerationPrompt(scenario: scenario)
                )
            } catch {
                attempts.append(
                    GenerationAttempt(
                        attemptNumber: attemptNumber,
                        stage: .objectGeneration,
                        durationSeconds: Date().timeIntervalSince(attemptStart),
                        outcome: .llmCallError(message: error.localizedDescription),
                        rawObjectsJSON: rawObjectsJSON,
                        rawTasksJSON: rawTasksJSON,
                        validationError: nil
                    )
                )
                continue
            }

            let objects: [WorldObjectSpec]
            do {
                objects = try Self.decodeObjects(from: rawObjectsJSON ?? "")
            } catch let failure as GenerationDecodingFailure {
                attempts.append(
                    GenerationAttempt(
                        attemptNumber: attemptNumber,
                        stage: .objectGeneration,
                        durationSeconds: Date().timeIntervalSince(attemptStart),
                        outcome: failure.outcome,
                        rawObjectsJSON: rawObjectsJSON,
                        rawTasksJSON: rawTasksJSON,
                        validationError: nil
                    )
                )
                continue
            }

            do {
                rawTasksJSON = try await client.completeJSON(
                    prompt: buildTaskGenerationPrompt(scenario: scenario, objects: objects)
                )
            } catch {
                attempts.append(
                    GenerationAttempt(
                        attemptNumber: attemptNumber,
                        stage: .taskGeneration,
                        durationSeconds: Date().timeIntervalSince(attemptStart),
                        outcome: .llmCallError(message: error.localizedDescription),
                        rawObjectsJSON: rawObjectsJSON,
                        rawTasksJSON: rawTasksJSON,
                        validationError: nil
                    )
                )
                continue
            }

            let tasks: [InteractionTask]
            do {
                tasks = try Self.decodeTasks(from: rawTasksJSON ?? "")
            } catch let failure as GenerationDecodingFailure {
                attempts.append(
                    GenerationAttempt(
                        attemptNumber: attemptNumber,
                        stage: .taskGeneration,
                        durationSeconds: Date().timeIntervalSince(attemptStart),
                        outcome: failure.outcome,
                        rawObjectsJSON: rawObjectsJSON,
                        rawTasksJSON: rawTasksJSON,
                        validationError: nil
                    )
                )
                continue
            }

            let generatedPlan = InteractionWorldPlan(
                id: "\(scenario.id)_generated_attempt_\(attemptNumber)",
                scenario: scenario,
                objects: objects,
                tasks: tasks
            )
            let layoutResult = InteractionWorldLayoutSolver.solve(generatedPlan)
            let plan = layoutResult.plan

            do {
                try InteractionWorldRuntime.validate(plan)
            } catch let validationError as InteractionWorldValidationError {
                attempts.append(
                    GenerationAttempt(
                        attemptNumber: attemptNumber,
                        stage: .validation,
                        durationSeconds: Date().timeIntervalSince(attemptStart),
                        outcome: .planValidationError(validationError),
                        rawObjectsJSON: rawObjectsJSON,
                        rawTasksJSON: rawTasksJSON,
                        validationError: validationError
                    )
                )
                continue
            }

            attempts.append(
                GenerationAttempt(
                    attemptNumber: attemptNumber,
                    stage: .fullPipeline,
                    durationSeconds: Date().timeIntervalSince(attemptStart),
                    outcome: .success,
                    rawObjectsJSON: rawObjectsJSON,
                    rawTasksJSON: rawTasksJSON,
                    validationError: nil
                )
            )

            return GenerationResult(
                scenario: scenario,
                plan: plan,
                attempts: attempts,
                totalGenerationTimeSeconds: Date().timeIntervalSince(pipelineStart),
                layoutSummary: layoutResult.summary
            )
        }

        return GenerationResult(
            scenario: scenario,
            plan: nil,
            attempts: attempts,
            totalGenerationTimeSeconds: Date().timeIntervalSince(pipelineStart)
        )
    }

    func generateObjects(for scenario: ScenarioCard) async throws -> [WorldObjectSpec] {
        let rawJSON = try await client.completeJSON(
            prompt: buildObjectGenerationPrompt(scenario: scenario)
        )
        return try Self.decodeObjects(from: rawJSON)
    }

    func generateTasks(
        for scenario: ScenarioCard,
        objects: [WorldObjectSpec]
    ) async throws -> [InteractionTask] {
        let rawJSON = try await client.completeJSON(
            prompt: buildTaskGenerationPrompt(scenario: scenario, objects: objects)
        )
        return try Self.decodeTasks(from: rawJSON)
    }

    static func decodeObjects(from rawJSON: String) throws -> [WorldObjectSpec] {
        let data = try sanitizedData(from: rawJSON)
        do {
            return try JSONDecoder().decode(ObjectGenerationResponse.self, from: data).objects
        } catch {
            do {
                return try JSONDecoder().decode([WorldObjectSpec].self, from: data)
            } catch {
                throw GenerationDecodingFailure(
                    outcome: .schemaValidationError(message: error.localizedDescription)
                )
            }
        }
    }

    static func decodeTasks(from rawJSON: String) throws -> [InteractionTask] {
        let data = try sanitizedData(from: rawJSON)
        do {
            return try JSONDecoder().decode(TaskGenerationResponse.self, from: data).tasks
        } catch {
            do {
                return try JSONDecoder().decode([InteractionTask].self, from: data)
            } catch {
                throw GenerationDecodingFailure(
                    outcome: .schemaValidationError(message: error.localizedDescription)
                )
            }
        }
    }

    private static func sanitizedData(from rawJSON: String) throws -> Data {
        let trimmed = rawJSON
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = trimmed.data(using: .utf8) else {
            throw GenerationDecodingFailure(
                outcome: .jsonParseError(message: "Could not convert response to UTF-8 data.")
            )
        }

        do {
            _ = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw GenerationDecodingFailure(
                outcome: .jsonParseError(message: error.localizedDescription)
            )
        }

        return data
    }
}

protocol InteractionWorldLLMClient {
    func completeJSON(prompt: String) async throws -> String
}

struct OpenAIInteractionWorldLLMClient: InteractionWorldLLMClient {
    var model = "gpt-4o"

    func completeJSON(prompt: String) async throws -> String {
        guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
              !apiKey.isEmpty else {
            throw GenerationLLMError.missingAPIKey
        }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            InteractionWorldOpenAIChatRequest(
                model: model,
                messages: [
                    InteractionWorldOpenAIChatMessage(
                        role: "system",
                        content: "You generate strict JSON for an interactive 3D language-learning scene pipeline. Return JSON only."
                    ),
                    InteractionWorldOpenAIChatMessage(role: "user", content: prompt)
                ],
                temperature: 0.2,
                responseFormat: InteractionWorldOpenAIResponseFormat(type: "json_object")
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GenerationLLMError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GenerationLLMError.requestFailed(statusCode: httpResponse.statusCode, body: body)
        }

        let decoded = try JSONDecoder().decode(InteractionWorldOpenAIChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw GenerationLLMError.missingContent
        }

        return content
    }
}

struct GenerationResult: Codable, Equatable {
    let scenario: ScenarioCard
    let plan: InteractionWorldPlan?
    let attempts: [GenerationAttempt]
    let totalGenerationTimeSeconds: TimeInterval
    let layoutSummary: InteractionWorldLayoutSummary?

    var succeeded: Bool {
        plan != nil
    }

    init(
        scenario: ScenarioCard,
        plan: InteractionWorldPlan?,
        attempts: [GenerationAttempt],
        totalGenerationTimeSeconds: TimeInterval,
        layoutSummary: InteractionWorldLayoutSummary? = nil
    ) {
        self.scenario = scenario
        self.plan = plan
        self.attempts = attempts
        self.totalGenerationTimeSeconds = totalGenerationTimeSeconds
        self.layoutSummary = layoutSummary
    }
}

struct InteractionWorldLayoutResult: Codable, Equatable {
    let plan: InteractionWorldPlan
    let summary: InteractionWorldLayoutSummary
}

struct InteractionWorldLayoutSummary: Codable, Equatable {
    let strategy: String
    let insertedSurfaceId: String?
    let relations: [InteractionWorldSpatialRelation]
    let objectSummaries: [InteractionWorldLayoutObjectSummary]

    var objectCount: Int {
        objectSummaries.count
    }

    var relationCount: Int {
        relations.count
    }
}

struct InteractionWorldLayoutObjectSummary: Codable, Equatable {
    let objectId: String
    let displayName: String
    let role: String
    let rawPosition: SIMD3<Float>
    let finalPosition: SIMD3<Float>
    let rawSize: SIMD3<Float>
    let finalSize: SIMD3<Float>
}

enum InteractionWorldSpatialRelationKind: String, Codable, Equatable, CaseIterable {
    case on
    case inside
    case near
    case far
    case leftOf
    case rightOf
    case inFrontOf
    case behind
    case centerAligned
    case facing

    var displayName: String {
        switch self {
        case .on:
            return "on"
        case .inside:
            return "inside"
        case .near:
            return "near"
        case .far:
            return "far from"
        case .leftOf:
            return "left of"
        case .rightOf:
            return "right of"
        case .inFrontOf:
            return "in front of"
        case .behind:
            return "behind"
        case .centerAligned:
            return "center aligned with"
        case .facing:
            return "facing"
        }
    }
}

struct InteractionWorldSpatialRelation: Codable, Equatable, Identifiable {
    var id: String {
        "\(subjectId)_\(kind.rawValue)_\(objectId)"
    }

    let subjectId: String
    let kind: InteractionWorldSpatialRelationKind
    let objectId: String
    let source: String
}

struct GenerationAttempt: Codable, Equatable {
    let attemptNumber: Int
    let stage: GenerationStage
    let durationSeconds: TimeInterval
    let outcome: GenerationOutcome
    let rawObjectsJSON: String?
    let rawTasksJSON: String?
    let validationError: InteractionWorldValidationError?
}

enum GenerationStage: String, Codable, Equatable {
    case objectGeneration
    case taskGeneration
    case validation
    case fullPipeline
}

enum GenerationOutcome: Codable, Equatable {
    case success
    case jsonParseError(message: String)
    case schemaValidationError(message: String)
    case planValidationError(InteractionWorldValidationError)
    case llmCallError(message: String)
}

enum GenerationLLMError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidResponse
    case requestFailed(statusCode: Int, body: String)
    case missingContent

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OPENAI_API_KEY is not set."
        case .invalidResponse:
            return "The OpenAI response was not an HTTP response."
        case .requestFailed(let statusCode, let body):
            return "OpenAI request failed with status \(statusCode): \(body)"
        case .missingContent:
            return "OpenAI response did not contain a message."
        }
    }
}

struct GenerationDecodingFailure: Error {
    let outcome: GenerationOutcome
}

func buildObjectGenerationPrompt(scenario: ScenarioCard) -> String {
    let expectedCategories = scenario.expectedObjectCategories ?? []

    return """
    You are a scene designer for a language-learning practice app running in spatial computing.

    Given the ScenarioCard below, generate the physical objects needed immediately around a standing learner. The learner stands at the origin and faces -z. Positions and sizes are in meters. Put reachable objects between hip and shoulder height. Counters and tables should usually be around y=0.6 to y=0.8. Keep objects in a compact area in front of the learner.

    The output is consumed by a strict Swift JSON decoder. Every object MUST include every required field listed in the schema. Use snake_case IDs. Do not include comments, Markdown, nulls, or extra wrapper text.

    ScenarioCard:
    {
      "id": "\(scenario.id)",
      "setting": "\(scenario.setting)",
      "learnerRole": "\(scenario.learnerRole)",
      "sceneGoal": "\(scenario.sceneGoal)",
      "localContext": "\(scenario.localContext)",
      "targetInteractions": \(jsonString(for: scenario.targetInteractions)),
      "expectedObjectCategories": \(jsonString(for: expectedCategories))
    }

    If expectedObjectCategories is non-empty, try to cover each category with one visible object. This is a researcher hint, not a separate output field.

    Model object identity, not spatial relationships. If an interaction involves a movable item and a container/surface, create them as separate objects:
    - good: "apple" and "fruit_basket"
    - bad: "apple_basket"
    - good: "bag_of_chips" and "shopping_basket"
    - bad: "chips_in_basket"

    The first item the learner picks up, drags, places, taps, or indicates should usually be a standalone smallObject with its own ID. Containers, counters, trays, baskets, menus, payment terminals, and NPC markers should be separate context/target objects. Do not merge a source object with its destination or support surface.

    Return strict JSON with this schema:
    {
      "objects": [
        {
          "id": "snake_case_unique_id",
          "displayName": "Human-readable label",
          "description": "One-line natural-language description of the object",
          "kind": { "type": "counter|menu|displayCase|cup|tray|cardReader|npcMarker|generic", "category": "container|flatSurface|uprightObject|marker|smallObject" },
          "position": [x, y, z],
          "size": [width, height, depth],
          "color": "brown|red|blue|cyan|yellow|green|gray|purple",
          "isInteractive": true
        }
      ]
    }

    For generated objects that are not one of the named kinds, use:
    { "type": "generic", "category": "container|flatSurface|uprightObject|marker|smallObject" }

    Use named kinds only when the object truly matches that category. Use generic for everything else. Make all objects that appear in targetInteractions interactive. Include enough context objects to make each action understandable, but keep the scene compact.

    Example:
    {
      "objects": [
        {
          "id": "counter",
          "displayName": "Counter",
          "description": "Wooden cafe counter surface within reach",
          "kind": { "type": "counter" },
          "position": [0.0, 0.62, -0.95],
          "size": [0.95, 0.08, 0.52],
          "color": "brown",
          "isInteractive": false
        },
        {
          "id": "ramen_bowl",
          "displayName": "Ramen Bowl",
          "description": "Ceramic ramen bowl with visible noodles and steam",
          "kind": { "type": "generic", "category": "container" },
          "position": [0.18, 0.72, -0.82],
          "size": [0.16, 0.08, 0.16],
          "color": "yellow",
          "isInteractive": true
        }
      ]
    }

    Return JSON only. The top-level JSON object must contain exactly one "objects" array.
    """
}

func buildTaskGenerationPrompt(
    scenario: ScenarioCard,
    objects: [WorldObjectSpec]
) -> String {
    let objectSummaries = objects.map { object in
        TaskPromptObjectSummary(
            id: object.id,
            displayName: object.displayName,
            description: object.description,
            kind: object.kind.typeName,
            position: object.position,
            size: object.size
        )
    }

    return """
    You are wiring interactions for a language-learning practice scene. Generate a task queue that covers the scenario's targetInteractions using only the available primitive vocabulary.

    The output is consumed by a strict Swift JSON decoder. Every task MUST include every required field listed in the schema. Reference only object IDs from Available objects. Do not invent objects. Do not include comments, Markdown, nulls, or extra wrapper text.

    ScenarioCard:
    {
      "id": "\(scenario.id)",
      "setting": "\(scenario.setting)",
      "learnerRole": "\(scenario.learnerRole)",
      "sceneGoal": "\(scenario.sceneGoal)",
      "localContext": "\(scenario.localContext)",
      "targetInteractions": \(jsonString(for: scenario.targetInteractions))
    }

    Available objects:
    \(jsonString(for: objectSummaries))

    Primitive vocabulary:
    - indicate: { "type": "indicate", "objectId": "existing_object_id" }
    - tap: { "type": "tap", "objectId": "existing_object_id" }
    - drag: { "type": "drag", "objectId": "existing_object_id" }
    - place: { "type": "place", "objectId": "existing_object_id", "targetId": "existing_target_object_id" }
    - gesture: { "type": "gesture", "gesture": "wave|point|thumbsUp|openPalm", "targetId": "optional_existing_object_id" }

    Primitive selection guidance:
    - Use indicate or tap for gaze-pinch selection of a visible object.
    - Use drag for moving an object without a target.
    - Use place when an object must end near/on another object.
    - For place, objectId must be the movable source item and targetId must be the destination/surface/container. Do not use a combined source/target object ID.
    - Use gesture only for social or hand-shape actions such as wave, point, thumbsUp, or openPalm.
    - If a target interaction cannot be represented perfectly, choose the closest primitive and make the instruction honest.

    Return strict JSON with this schema:
    {
      "tasks": [
        {
          "id": "snake_case_unique_task_id",
          "instruction": "Short instruction shown to the learner",
          "requiredObjectIds": ["object_ids_from_the_available_list_only"],
          "expectedInteraction": { "type": "tap", "objectId": "object_id" }
        }
      ]
    }

    Example:
    {
      "tasks": [
        {
          "id": "point_at_pastry_case",
          "instruction": "Point at the pastry display.",
          "requiredObjectIds": ["pastry_case"],
          "expectedInteraction": { "type": "gesture", "gesture": "point", "targetId": "pastry_case" }
        },
        {
          "id": "place_cup_on_tray",
          "instruction": "Place the drink on the tray.",
          "requiredObjectIds": ["coffee_cup", "tray"],
          "expectedInteraction": { "type": "place", "objectId": "coffee_cup", "targetId": "tray" }
        }
      ]
    }

    Cover the targetInteractions in order. The task count should usually match the targetInteractions count. Reference only object IDs from Available objects. The top-level JSON object must contain exactly one "tasks" array. Return JSON only.
    """
}

enum InteractionWorldLayoutSolver {
    static func applyStageLayout(to plan: InteractionWorldPlan) -> InteractionWorldPlan {
        solve(plan).plan
    }

    static func solve(_ plan: InteractionWorldPlan) -> InteractionWorldLayoutResult {
        var objects = plan.objects
        let originalObjectIds = Set(objects.map(\.id))
        var insertedSurfaceId: String?
        if objects.first(where: isSurface(_:)) == nil {
            let fallbackSurface = makeFallbackSurface(existingIds: Set(objects.map(\.id)))
            insertedSurfaceId = fallbackSurface.id
            objects.insert(fallbackSurface, at: 0)
        }

        guard let surfaceIndex = objects.firstIndex(where: isSurface(_:)) else {
            return InteractionWorldLayoutResult(
                plan: plan,
                summary: InteractionWorldLayoutSummary(
                    strategy: "stage_surface_slots_v1",
                    insertedSurfaceId: insertedSurfaceId,
                    relations: [],
                    objectSummaries: []
                )
            )
        }

        let rawObjects = objects
        let rawById = Dictionary(uniqueKeysWithValues: rawObjects.map { ($0.id, $0) })
        let rawSurface = objects[surfaceIndex]
        let surface = copy(
            rawSurface,
            position: [0.0, 0.62, -0.95],
            size: [
                max(rawSurface.size.x, 1.05),
                max(min(rawSurface.size.y, 0.10), 0.06),
                max(rawSurface.size.z, 0.52)
            ]
        )
        objects[surfaceIndex] = surface

        let targetIds = placementTargetIds(in: plan.tasks)
        let placedObjectIds = placedObjectIds(in: plan.tasks)
        let surfaceTopY = surface.position.y + surface.size.y / 2
        var slotCounters: [StageRole: Int] = [:]
        var rolesById: [String: StageRole] = [surface.id: .surface]

        objects = objects.map { object in
            guard object.id != surface.id else { return surface }

            let role = stageRole(
                for: object,
                placedObjectIds: placedObjectIds,
                targetIds: targetIds
            )
            rolesById[object.id] = role
            let slot = nextSlot(for: role, counters: &slotCounters)
            let size = normalizedSize(for: object, role: role)
            let position = SIMD3<Float>(
                slot.x,
                surfaceTopY + size.y / 2 + 0.015,
                slot.y
            )

            if role == .personMarker {
                return copy(object, position: [slot.x, 1.05, slot.y], size: size)
            }

            return copy(object, position: position, size: size)
        }

        let relations = inferRelations(
            for: plan,
            objects: objects,
            originalObjectIds: originalObjectIds,
            surfaceId: surface.id,
            rolesById: rolesById
        )
        objects = applyRelations(
            relations,
            to: objects,
            surfaceId: surface.id,
            surfaceTopY: surfaceTopY,
            rolesById: rolesById
        )
        objects = enforceSurfaceSupport(
            objects,
            surfaceId: surface.id,
            surfaceTopY: surfaceTopY,
            rolesById: rolesById
        )
        objects = repairSurfaceOverlaps(
            objects,
            surfaceId: surface.id,
            surfaceTopY: surfaceTopY,
            rolesById: rolesById
        )
        objects = enforceSurfaceSupport(
            objects,
            surfaceId: surface.id,
            surfaceTopY: surfaceTopY,
            rolesById: rolesById
        )
        objects = applyAssetCards(
            to: objects,
            surfaceId: surface.id,
            rolesById: rolesById
        )

        let objectSummaries = objects.compactMap { finalObject -> InteractionWorldLayoutObjectSummary? in
            guard let rawObject = rawById[finalObject.id],
                  let role = rolesById[finalObject.id] else {
                return nil
            }
            return summary(raw: rawObject, final: finalObject, role: role)
        }

        let solvedPlan = InteractionWorldPlan(
            id: "\(plan.id)_stage_layout",
            scenario: plan.scenario,
            objects: objects,
            tasks: plan.tasks
        )

        return InteractionWorldLayoutResult(
            plan: solvedPlan,
            summary: InteractionWorldLayoutSummary(
                strategy: "stage_relation_slots_v1",
                insertedSurfaceId: insertedSurfaceId,
                relations: relations,
                objectSummaries: objectSummaries
            )
        )
    }

    private enum StageRole: String, Hashable {
        case surface
        case sourceObject
        case targetContainer
        case payment
        case uprightContext
        case personMarker
        case contextObject
    }

    private static func stageRole(
        for object: WorldObjectSpec,
        placedObjectIds: Set<String>,
        targetIds: Set<String>
    ) -> StageRole {
        if isPersonMarker(object) {
            return .personMarker
        }
        if isPaymentObject(object) {
            return .payment
        }
        if isDisplayFixture(object) {
            return .contextObject
        }
        if targetIds.contains(object.id) || isContainer(object) {
            return .targetContainer
        }
        if isUprightContext(object) {
            return .uprightContext
        }
        if placedObjectIds.contains(object.id) || isSmallManipulable(object) {
            return .sourceObject
        }
        return .contextObject
    }

    private static func nextSlot(
        for role: StageRole,
        counters: inout [StageRole: Int]
    ) -> SIMD2<Float> {
        let index = counters[role, default: 0]
        counters[role] = index + 1

        let slots: [SIMD2<Float>]
        switch role {
        case .surface:
            slots = [
                [0.0, -0.95]
            ]
        case .sourceObject:
            slots = [
                [-0.36, -0.72],
                [-0.16, -0.72],
                [0.04, -0.72],
                [-0.30, -0.88]
            ]
        case .targetContainer:
            slots = [
                [0.24, -0.78],
                [0.42, -0.92],
                [0.08, -0.88]
            ]
        case .payment:
            slots = [
                [0.42, -1.08],
                [0.30, -1.12]
            ]
        case .uprightContext:
            slots = [
                [-0.42, -1.10],
                [-0.24, -1.12],
                [0.0, -1.14]
            ]
        case .personMarker:
            slots = [
                [0.0, -1.38],
                [0.34, -1.36],
                [-0.34, -1.36]
            ]
        case .contextObject:
            slots = [
                [0.0, -0.86],
                [-0.44, -0.92],
                [0.44, -0.76],
                [0.16, -1.04]
            ]
        }

        if index < slots.count {
            return slots[index]
        }

        let overflow = Float(index - slots.count + 1)
        return [min(0.48, -0.48 + overflow * 0.16), -0.66 - overflow * 0.08]
    }

    private static func inferRelations(
        for plan: InteractionWorldPlan,
        objects: [WorldObjectSpec],
        originalObjectIds: Set<String>,
        surfaceId: String,
        rolesById: [String: StageRole]
    ) -> [InteractionWorldSpatialRelation] {
        var relations: [InteractionWorldSpatialRelation] = []

        func append(
            subjectId: String,
            _ kind: InteractionWorldSpatialRelationKind,
            objectId: String,
            source: String
        ) {
            guard subjectId != objectId else { return }
            relations.append(
                InteractionWorldSpatialRelation(
                    subjectId: subjectId,
                    kind: kind,
                    objectId: objectId,
                    source: source
                )
            )
        }

        for object in objects where object.id != surfaceId {
            guard let role = rolesById[object.id] else { continue }
            switch role {
            case .surface:
                break
            case .personMarker:
                append(subjectId: object.id, .behind, objectId: surfaceId, source: "roleDefaults")
                append(subjectId: object.id, .facing, objectId: surfaceId, source: "roleDefaults")
            case .uprightContext:
                append(subjectId: object.id, .on, objectId: surfaceId, source: "roleDefaults")
                append(subjectId: object.id, .behind, objectId: surfaceId, source: "roleDefaults")
            case .payment:
                append(subjectId: object.id, .on, objectId: surfaceId, source: "roleDefaults")
                append(subjectId: object.id, .rightOf, objectId: surfaceId, source: "roleDefaults")
            case .sourceObject, .targetContainer, .contextObject:
                append(subjectId: object.id, .on, objectId: surfaceId, source: "roleDefaults")
            }
        }

        for task in plan.tasks {
            switch task.expectedInteraction {
            case .place(let objectId, let targetId):
                append(subjectId: objectId, .on, objectId: surfaceId, source: "task:\(task.id)")
                append(subjectId: targetId, .on, objectId: surfaceId, source: "task:\(task.id)")
                append(subjectId: targetId, .rightOf, objectId: objectId, source: "task:\(task.id)")
                append(subjectId: targetId, .near, objectId: objectId, source: "task:\(task.id)")
            case .tap(let objectId):
                if rolesById[objectId] == .payment {
                    append(subjectId: objectId, .behind, objectId: surfaceId, source: "task:\(task.id)")
                }
            case .indicate(let objectId):
                if rolesById[objectId] == .uprightContext {
                    append(subjectId: objectId, .behind, objectId: surfaceId, source: "task:\(task.id)")
                }
            case .drag(let objectId):
                append(subjectId: objectId, .on, objectId: surfaceId, source: "task:\(task.id)")
            case .gesture:
                break
            }
        }

        if !originalObjectIds.contains(surfaceId) {
            for object in objects where object.id != surfaceId && rolesById[object.id] != .personMarker {
                append(subjectId: object.id, .near, objectId: surfaceId, source: "fallbackSurface")
            }
        }

        var seen: Set<String> = []
        return relations.filter { relation in
            let key = relation.id
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private static func applyRelations(
        _ relations: [InteractionWorldSpatialRelation],
        to objects: [WorldObjectSpec],
        surfaceId: String,
        surfaceTopY: Float,
        rolesById: [String: StageRole]
    ) -> [WorldObjectSpec] {
        var adjustedObjects = objects
        for relation in relations {
            guard let subjectIndex = adjustedObjects.firstIndex(where: { $0.id == relation.subjectId }),
                  let target = adjustedObjects.first(where: { $0.id == relation.objectId }),
                  adjustedObjects[subjectIndex].id != surfaceId else {
                continue
            }

            var subject = adjustedObjects[subjectIndex]
            let role = rolesById[subject.id] ?? .contextObject
            var position = subject.position

            switch relation.kind {
            case .on:
                if target.id == surfaceId || rolesById[target.id] == .surface {
                    position.y = surfaceTopY + subject.size.y / 2 + 0.015
                }
            case .inside:
                position.x = target.position.x
                position.z = target.position.z
                position.y = max(position.y, target.position.y + subject.size.y / 2 + 0.02)
            case .rightOf:
                if target.id != surfaceId {
                    position.x = target.position.x + target.size.x / 2 + subject.size.x / 2 + 0.08
                    position.z = target.position.z
                } else {
                    position.x = max(position.x, 0.28)
                }
            case .leftOf:
                if target.id != surfaceId {
                    position.x = target.position.x - target.size.x / 2 - subject.size.x / 2 - 0.08
                    position.z = target.position.z
                } else {
                    position.x = min(position.x, -0.28)
                }
            case .behind:
                let offset = target.id == surfaceId
                    ? target.size.z / 2 + subject.size.z / 2 + 0.12
                    : target.size.z / 2 + subject.size.z / 2 + 0.10
                position.z = target.position.z - offset
            case .inFrontOf:
                let offset = target.size.z / 2 + subject.size.z / 2 + 0.10
                position.z = target.position.z + offset
            case .centerAligned:
                position.x = target.position.x
            case .near, .facing, .far:
                break
            }

            if role == .personMarker {
                position.y = 1.05
            } else if role != .surface {
                position.y = surfaceTopY + subject.size.y / 2 + 0.015
            }
            subject = copy(subject, position: clampStagePosition(position, role: role), size: subject.size)
            adjustedObjects[subjectIndex] = subject
        }

        return adjustedObjects
    }

    private static func enforceSurfaceSupport(
        _ objects: [WorldObjectSpec],
        surfaceId: String,
        surfaceTopY: Float,
        rolesById: [String: StageRole]
    ) -> [WorldObjectSpec] {
        guard let surface = objects.first(where: { $0.id == surfaceId }) else {
            return objects
        }

        return objects.map { object in
            let role = rolesById[object.id] ?? .contextObject
            guard object.id != surfaceId, role != .personMarker else {
                return object
            }

            let xLimit = max(0.0, surface.size.x / 2 - object.size.x / 2 - 0.035)
            let zLimit = max(0.0, surface.size.z / 2 - object.size.z / 2 - 0.035)
            let position = SIMD3<Float>(
                Swift.max(surface.position.x - xLimit, Swift.min(surface.position.x + xLimit, object.position.x)),
                surfaceTopY + object.size.y / 2 + 0.015,
                Swift.max(surface.position.z - zLimit, Swift.min(surface.position.z + zLimit, object.position.z))
            )
            return copy(object, position: position, size: object.size)
        }
    }

    private static func repairSurfaceOverlaps(
        _ objects: [WorldObjectSpec],
        surfaceId: String,
        surfaceTopY: Float,
        rolesById: [String: StageRole]
    ) -> [WorldObjectSpec] {
        var repaired: [WorldObjectSpec] = []

        for object in objects {
            guard object.id != surfaceId else {
                repaired.append(object)
                continue
            }

            let role = rolesById[object.id] ?? .contextObject
            guard role != .personMarker else {
                repaired.append(object)
                continue
            }

            var candidate = object
            for attempt in 0..<8 where repaired.contains(where: { overlaps(candidate, $0, rolesById: rolesById) }) {
                var position = candidate.position
                let direction: Float = attempt.isMultiple(of: 2) ? 1 : -1
                position.x += direction * (0.08 + Float(attempt / 2) * 0.04)
                if attempt >= 4 {
                    position.z -= 0.08
                }
                position.y = surfaceTopY + candidate.size.y / 2 + 0.015
                candidate = copy(candidate, position: clampStagePosition(position, role: role), size: candidate.size)
            }
            repaired.append(candidate)
        }

        return repaired
    }

    private static func overlaps(
        _ lhs: WorldObjectSpec,
        _ rhs: WorldObjectSpec,
        rolesById: [String: StageRole]
    ) -> Bool {
        guard rolesById[rhs.id] != .surface,
              rolesById[lhs.id] != .personMarker,
              rolesById[rhs.id] != .personMarker else {
            return false
        }

        let padding: Float = 0.025
        let lhsMinX = lhs.position.x - lhs.size.x / 2 - padding
        let lhsMaxX = lhs.position.x + lhs.size.x / 2 + padding
        let lhsMinZ = lhs.position.z - lhs.size.z / 2 - padding
        let lhsMaxZ = lhs.position.z + lhs.size.z / 2 + padding
        let rhsMinX = rhs.position.x - rhs.size.x / 2 - padding
        let rhsMaxX = rhs.position.x + rhs.size.x / 2 + padding
        let rhsMinZ = rhs.position.z - rhs.size.z / 2 - padding
        let rhsMaxZ = rhs.position.z + rhs.size.z / 2 + padding

        return lhsMinX < rhsMaxX
            && lhsMaxX > rhsMinX
            && lhsMinZ < rhsMaxZ
            && lhsMaxZ > rhsMinZ
    }

    private static func clampStagePosition(
        _ position: SIMD3<Float>,
        role: StageRole
    ) -> SIMD3<Float> {
        let xLimit: Float = role == .personMarker ? 0.60 : 0.55
        let zMin: Float = role == .personMarker ? -1.55 : -1.30
        let zMax: Float = -0.58

        return [
            Swift.max(-xLimit, Swift.min(xLimit, position.x)),
            position.y,
            Swift.max(zMin, Swift.min(zMax, position.z))
        ]
    }

    private static func summary(
        raw: WorldObjectSpec,
        final: WorldObjectSpec,
        role: StageRole
    ) -> InteractionWorldLayoutObjectSummary {
        InteractionWorldLayoutObjectSummary(
            objectId: final.id,
            displayName: final.displayName,
            role: role.rawValue,
            rawPosition: raw.position,
            finalPosition: final.position,
            rawSize: raw.size,
            finalSize: final.size
        )
    }

    private static func normalizedSize(
        for object: WorldObjectSpec,
        role: StageRole
    ) -> SIMD3<Float> {
        switch role {
        case .surface:
            return object.size
        case .sourceObject:
            return clampSize(object.size, min: [0.10, 0.06, 0.08], max: [0.20, 0.18, 0.20])
        case .targetContainer:
            return clampSize(object.size, min: [0.18, 0.08, 0.16], max: [0.34, 0.22, 0.30])
        case .payment:
            return clampSize(object.size, min: [0.14, 0.05, 0.10], max: [0.22, 0.12, 0.18])
        case .uprightContext:
            return clampSize(object.size, min: [0.16, 0.14, 0.04], max: [0.30, 0.34, 0.08])
        case .personMarker:
            return clampSize(object.size, min: [0.08, 0.18, 0.08], max: [0.18, 0.34, 0.18])
        case .contextObject:
            return clampSize(object.size, min: [0.12, 0.08, 0.10], max: [0.28, 0.24, 0.24])
        }
    }

    private static func applyAssetCards(
        to objects: [WorldObjectSpec],
        surfaceId: String,
        rolesById: [String: StageRole]
    ) -> [WorldObjectSpec] {
        objects.map { object in
            guard let role = rolesById[object.id] else { return object }
            return object.withAssetCard(assetCard(for: object, role: role, surfaceId: surfaceId))
        }
    }

    private static func assetCard(
        for object: WorldObjectSpec,
        role: StageRole,
        surfaceId: String
    ) -> WorldObjectAssetCard {
        let assetKind = assetKind(for: object, role: role)
        return WorldObjectAssetCard(
            layoutRole: layoutRole(for: role),
            assetKind: assetKind,
            supportSurfaceId: supportSurfaceId(for: role, surfaceId: surfaceId),
            orientationHint: orientationHint(for: assetKind),
            frontHint: frontHint(for: assetKind),
            targetSize: targetSize(for: object, assetKind: assetKind),
            restingPolicy: role == .surface ? .centerAtPosition : .bottomOnSupport
        )
    }

    private static func layoutRole(for role: StageRole) -> WorldObjectLayoutRole {
        switch role {
        case .surface:
            return .surface
        case .sourceObject:
            return .sourceObject
        case .targetContainer:
            return .targetContainer
        case .payment:
            return .payment
        case .uprightContext:
            return .uprightContext
        case .personMarker:
            return .personMarker
        case .contextObject:
            return .contextObject
        }
    }

    private static func supportSurfaceId(for role: StageRole, surfaceId: String) -> String? {
        switch role {
        case .surface, .personMarker:
            return nil
        case .sourceObject, .targetContainer, .payment, .uprightContext, .contextObject:
            return surfaceId
        }
    }

    private static func assetKind(for object: WorldObjectSpec, role: StageRole) -> WorldObjectAssetKind {
        if role == .surface {
            return .surface
        }
        if role == .payment {
            return .paymentDevice
        }
        if role == .personMarker {
            return .personMarker
        }
        if isDisplayFixture(object) {
            return .displayFixture
        }
        if isUprightContext(object) {
            return .menu
        }
        if object.kind == .cup || containsAny(object, ["cup", "coffee"]) {
            return .cup
        }
        if object.kind == .tray || containsAny(object, ["tray", "plate"]) {
            return .tray
        }
        if isContainer(object) {
            return .container
        }
        return .smallObject
    }

    private static func orientationHint(for assetKind: WorldObjectAssetKind) -> WorldObjectOrientationHint {
        switch assetKind {
        case .surface:
            return .horizontalSurface
        case .paymentDevice, .displayFixture:
            return .tabletopFlat
        case .menu, .personMarker:
            return .uprightFacingLearner
        case .cup, .container:
            return .openTopUpright
        case .tray:
            return .shallowTray
        case .smallObject:
            return .compact
        }
    }

    private static func frontHint(for assetKind: WorldObjectAssetKind) -> WorldObjectFrontHint {
        switch assetKind {
        case .paymentDevice, .displayFixture, .menu, .personMarker:
            return .facesLearner
        case .surface, .smallObject, .container, .cup, .tray:
            return .unconstrained
        }
    }

    private static func targetSize(
        for object: WorldObjectSpec,
        assetKind: WorldObjectAssetKind
    ) -> SIMD3<Float> {
        switch assetKind {
        case .surface:
            return object.size
        case .paymentDevice:
            return clampSize(object.size, min: [0.16, 0.045, 0.12], max: [0.22, 0.08, 0.18])
        case .displayFixture:
            return clampSize(object.size, min: [0.22, 0.12, 0.18], max: [0.36, 0.22, 0.28])
        case .menu:
            return clampSize(object.size, min: [0.24, 0.26, 0.035], max: [0.36, 0.42, 0.07])
        case .personMarker:
            return clampSize(object.size, min: [0.10, 0.22, 0.10], max: [0.18, 0.36, 0.18])
        case .cup:
            return clampSize(object.size, min: [0.08, 0.09, 0.08], max: [0.14, 0.16, 0.14])
        case .tray:
            return clampSize(object.size, min: [0.22, 0.035, 0.16], max: [0.40, 0.08, 0.30])
        case .container:
            return clampSize(object.size, min: [0.18, 0.10, 0.16], max: [0.34, 0.24, 0.30])
        case .smallObject:
            return clampSize(object.size, min: [0.08, 0.06, 0.08], max: [0.20, 0.18, 0.20])
        }
    }

    private static func placementTargetIds(in tasks: [InteractionTask]) -> Set<String> {
        Set(tasks.compactMap { task in
            if case .place(_, let targetId) = task.expectedInteraction {
                return targetId
            }
            return nil
        })
    }

    private static func placedObjectIds(in tasks: [InteractionTask]) -> Set<String> {
        Set(tasks.compactMap { task in
            if case .place(let objectId, _) = task.expectedInteraction {
                return objectId
            }
            return nil
        })
    }

    private static func isSurface(_ object: WorldObjectSpec) -> Bool {
        switch object.kind {
        case .counter:
            return true
        case .generic(let category):
            return category == "flatSurface"
                || containsAny(object, ["counter", "surface", "table", "stand", "stall", "desk"])
        default:
            return containsAny(object, ["counter", "surface", "table", "stand", "stall", "desk"])
        }
    }

    private static func isContainer(_ object: WorldObjectSpec) -> Bool {
        switch object.kind {
        case .tray:
            return true
        case .generic(let category):
            return category == "container"
        default:
            return containsAny(object, ["basket", "bag", "box", "tray", "bowl", "bin"])
        }
    }

    private static func isPaymentObject(_ object: WorldObjectSpec) -> Bool {
        object.kind == .cardReader
            || containsAny(object, ["payment", "terminal", "reader", "register", "wallet", "card"])
    }

    private static func isPersonMarker(_ object: WorldObjectSpec) -> Bool {
        object.kind == .npcMarker
            || containsAny(object, [
                "npc",
                "cashier",
                "vendor",
                "barista",
                "clerk",
                "server",
                "attendant",
                "seller",
                "staff",
                "person"
            ])
    }

    private static func isUprightContext(_ object: WorldObjectSpec) -> Bool {
        object.kind == .menu
            || containsAny(object, ["menu", "sign", "poster", "placard", "label"])
    }

    private static func isDisplayFixture(_ object: WorldObjectSpec) -> Bool {
        object.kind == .displayCase
            || containsAny(object, ["display case", "display_case", "pastry display", "pastry_display"])
    }

    private static func isSmallManipulable(_ object: WorldObjectSpec) -> Bool {
        switch object.kind {
        case .cup:
            return true
        case .generic(let category):
            return category == "smallObject"
        default:
            return object.isInteractive && !isSurface(object)
        }
    }

    private static func containsAny(
        _ object: WorldObjectSpec,
        _ needles: [String]
    ) -> Bool {
        let haystack = "\(object.id) \(object.displayName) \(object.description)"
            .lowercased()
        return needles.contains { haystack.contains($0) }
    }

    private static func clampSize(
        _ size: SIMD3<Float>,
        min minimum: SIMD3<Float>,
        max maximum: SIMD3<Float>
    ) -> SIMD3<Float> {
        [
            Swift.max(minimum.x, Swift.min(maximum.x, size.x)),
            Swift.max(minimum.y, Swift.min(maximum.y, size.y)),
            Swift.max(minimum.z, Swift.min(maximum.z, size.z))
        ]
    }

    private static func makeFallbackSurface(existingIds: Set<String>) -> WorldObjectSpec {
        var id = "interaction_surface"
        var suffix = 2
        while existingIds.contains(id) {
            id = "interaction_surface_\(suffix)"
            suffix += 1
        }

        return WorldObjectSpec(
            id: id,
            displayName: "Interaction Surface",
            description: "Generated counter-like surface used to organize reachable practice objects.",
            kind: .generic(category: "flatSurface"),
            position: [0.0, 0.62, -0.95],
            size: [1.05, 0.08, 0.52],
            color: .brown,
            isInteractive: false
        )
    }

    private static func copy(
        _ object: WorldObjectSpec,
        position: SIMD3<Float>,
        size: SIMD3<Float>
    ) -> WorldObjectSpec {
        WorldObjectSpec(
            id: object.id,
            displayName: object.displayName,
            description: object.description,
            kind: object.kind,
            position: position,
            size: size,
            color: object.color,
            isInteractive: object.isInteractive,
            visualAsset: object.visualAsset,
            assetCard: object.assetCard
        )
    }
}

private struct ObjectGenerationResponse: Codable {
    let objects: [WorldObjectSpec]
}

private struct TaskGenerationResponse: Codable {
    let tasks: [InteractionTask]
}

private struct TaskPromptObjectSummary: Encodable {
    let id: String
    let displayName: String
    let description: String
    let kind: String
    let position: SIMD3<Float>
    let size: SIMD3<Float>
}

private struct InteractionWorldOpenAIChatRequest: Encodable {
    let model: String
    let messages: [InteractionWorldOpenAIChatMessage]
    let temperature: Double
    let responseFormat: InteractionWorldOpenAIResponseFormat

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case responseFormat = "response_format"
    }
}

private struct InteractionWorldOpenAIChatMessage: Codable {
    let role: String
    let content: String
}

private struct InteractionWorldOpenAIResponseFormat: Encodable {
    let type: String
}

private struct InteractionWorldOpenAIChatResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: InteractionWorldOpenAIChatMessage
    }
}

private func jsonString<T: Encodable>(for value: T) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    guard let data = try? encoder.encode(value),
          let string = String(data: data, encoding: .utf8) else {
        return "null"
    }

    return string
}

struct SAM3DSceneRealizationRequest: Codable, Equatable {
    let scenario: ScenarioCard
    let plan: InteractionWorldPlan
}

struct SAM3DSceneRealizationResponse: Codable, Equatable {
    let jobId: String?
    let generatedImageURL: URL?
    let objects: [SAM3DRealizedObject]
    let notes: String?

    init(
        jobId: String? = nil,
        generatedImageURL: URL? = nil,
        objects: [SAM3DRealizedObject],
        notes: String? = nil
    ) {
        self.jobId = jobId
        self.generatedImageURL = generatedImageURL
        self.objects = objects
        self.notes = notes
    }
}

private struct SAM3DSceneRealizationJobStartResponse: Codable, Equatable {
    let jobId: String
    let status: String
}

private struct SAM3DSceneRealizationJobStatusResponse: Codable, Equatable {
    let jobId: String
    let status: String
    let result: SAM3DSceneRealizationResponse?
    let error: String?
}

struct SAM3DRealizedObject: Codable, Equatable, Identifiable {
    var id: String { objectId }

    let objectId: String
    let status: SAM3DRealizedObjectStatus
    let visualFormat: WorldObjectVisualFormat
    let assetURL: URL?
    let previewImageURL: URL?
    let position: SIMD3<Float>?
    let size: SIMD3<Float>?
    let proxyShape: SAM3DProxyShapeSpec?
    let canonicalPose: WorldObjectCanonicalPose?
    let notes: String?

    init(
        objectId: String,
        status: SAM3DRealizedObjectStatus,
        visualFormat: WorldObjectVisualFormat,
        assetURL: URL?,
        previewImageURL: URL? = nil,
        position: SIMD3<Float>?,
        size: SIMD3<Float>?,
        proxyShape: SAM3DProxyShapeSpec?,
        canonicalPose: WorldObjectCanonicalPose? = nil,
        notes: String?
    ) {
        self.objectId = objectId
        self.status = status
        self.visualFormat = visualFormat
        self.assetURL = assetURL
        self.previewImageURL = previewImageURL
        self.position = position
        self.size = size
        self.proxyShape = proxyShape
        self.canonicalPose = canonicalPose
        self.notes = notes
    }
}

enum SAM3DRealizedObjectStatus: String, Codable, Equatable {
    case realized
    case missing
    case failed
    case fallbackPrimitive

    var worldStatus: WorldObjectRealizationStatus {
        switch self {
        case .realized:
            return .realized
        case .fallbackPrimitive:
            return .fallbackPrimitive
        case .missing, .failed:
            return .failed
        }
    }
}

struct SAM3DProxyShapeSpec: Codable, Equatable {
    let type: String
    let size: SIMD3<Float>?
}

struct SAM3DCachedAsset: Codable, Equatable {
    let objectId: String
    let remoteURL: URL
    let localURL: URL
    let previewRemoteURL: URL?
    let previewLocalURL: URL?

    init(
        objectId: String,
        remoteURL: URL,
        localURL: URL,
        previewRemoteURL: URL? = nil,
        previewLocalURL: URL? = nil
    ) {
        self.objectId = objectId
        self.remoteURL = remoteURL
        self.localURL = localURL
        self.previewRemoteURL = previewRemoteURL
        self.previewLocalURL = previewLocalURL
    }
}

struct SAM3DSceneRealizationResult: Codable, Equatable {
    let response: SAM3DSceneRealizationResponse
    let reconciledPlan: InteractionWorldPlan
    let cachedAssets: [SAM3DCachedAsset]

    var realizedCount: Int {
        response.objects.filter { $0.status == .realized }.count
    }

    var failedCount: Int {
        response.objects.filter { $0.status == .failed || $0.status == .missing }.count
    }
}

final class SAM3DSceneRealizationClient {
    var baseURL: URL
    var endpointPath = "realize-scene"
    var asyncEndpointPath = "realize-scene-async"
    var timeoutInterval: TimeInterval = 1_800
    var pollingInterval: TimeInterval = 5
    var jobStatusRequestTimeout: TimeInterval = 180
    var progressHandler: ((String) -> Void)?

    init(baseURL: URL = URL(string: "http://localhost:8010")!) {
        self.baseURL = baseURL
    }

    func realize(plan: InteractionWorldPlan) async throws -> SAM3DSceneRealizationResult {
        let requestBody = SAM3DSceneRealizationRequest(
            scenario: plan.scenario,
            plan: plan
        )
        let response = try await requestRealization(requestBody)
        let cachedAssets = try await cacheAssets(from: response)
        let reconciledPlan = SAM3DSceneReconciler.reconcile(
            plan: plan,
            response: response,
            cachedAssets: cachedAssets
        )

        return SAM3DSceneRealizationResult(
            response: response,
            reconciledPlan: reconciledPlan,
            cachedAssets: cachedAssets
        )
    }

    private func requestRealization(
        _ requestBody: SAM3DSceneRealizationRequest
    ) async throws -> SAM3DSceneRealizationResponse {
        do {
            return try await requestAsyncRealization(requestBody)
        } catch SAM3DSceneRealizationError.requestFailed(let statusCode, _) where statusCode == 404 {
            return try await requestSynchronousRealization(requestBody)
        }
    }

    private func requestAsyncRealization(
        _ requestBody: SAM3DSceneRealizationRequest
    ) async throws -> SAM3DSceneRealizationResponse {
        let startURL = baseURL.appendingPathComponent(asyncEndpointPath)
        var request = URLRequest(url: startURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SAM3DSceneRealizationError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SAM3DSceneRealizationError.requestFailed(
                statusCode: httpResponse.statusCode,
                body: body
            )
        }

        let job = try JSONDecoder().decode(SAM3DSceneRealizationJobStartResponse.self, from: data)
        progressHandler?("SAM 3D job \(job.jobId.prefix(8)) started. Polling for generated assets...")
        let deadline = Date().addingTimeInterval(timeoutInterval)

        while Date() < deadline {
            try await Task.sleep(nanoseconds: UInt64(pollingInterval * 1_000_000_000))
            let status: SAM3DSceneRealizationJobStatusResponse
            do {
                status = try await requestJobStatus(jobId: job.jobId)
            } catch let error as URLError where Self.isTransientPollingError(error) {
                progressHandler?("SAM 3D job \(job.jobId.prefix(8)) is still busy. Continuing to poll...")
                continue
            }

            switch status.status {
            case "queued", "running":
                progressHandler?("SAM 3D job \(job.jobId.prefix(8)) \(status.status). Waiting for generated assets...")
            case "completed":
                guard let result = status.result else {
                    throw SAM3DSceneRealizationError.invalidResponse
                }
                progressHandler?("SAM 3D job \(job.jobId.prefix(8)) completed. Downloading assets...")
                return result
            case "failed":
                throw SAM3DSceneRealizationError.requestFailed(
                    statusCode: 500,
                    body: status.error ?? "SAM 3D job failed."
                )
            default:
                throw SAM3DSceneRealizationError.requestFailed(
                    statusCode: 500,
                    body: "Unknown SAM 3D job status: \(status.status)"
                )
            }
        }

        throw SAM3DSceneRealizationError.requestFailed(
            statusCode: 408,
            body: "SAM 3D job did not finish within \(Int(timeoutInterval)) seconds."
        )
    }

    private func requestJobStatus(jobId: String) async throws -> SAM3DSceneRealizationJobStatusResponse {
        let url = baseURL
            .appendingPathComponent("jobs")
            .appendingPathComponent(jobId)
        var request = URLRequest(url: url)
        request.timeoutInterval = jobStatusRequestTimeout

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SAM3DSceneRealizationError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SAM3DSceneRealizationError.requestFailed(
                statusCode: httpResponse.statusCode,
                body: body
            )
        }

        return try JSONDecoder().decode(SAM3DSceneRealizationJobStatusResponse.self, from: data)
    }

    private static func isTransientPollingError(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }

    private func requestSynchronousRealization(
        _ requestBody: SAM3DSceneRealizationRequest
    ) async throws -> SAM3DSceneRealizationResponse {
        let url = baseURL.appendingPathComponent(endpointPath)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutInterval
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SAM3DSceneRealizationError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SAM3DSceneRealizationError.requestFailed(
                statusCode: httpResponse.statusCode,
                body: body
            )
        }

        return try JSONDecoder().decode(SAM3DSceneRealizationResponse.self, from: data)
    }

    private func cacheAssets(
        from response: SAM3DSceneRealizationResponse
    ) async throws -> [SAM3DCachedAsset] {
        let objectsWithAssets = response.objects.compactMap { object -> (String, URL)? in
            guard object.status == .realized, let assetURL = object.assetURL else {
                return nil
            }
            return (object.objectId, assetURL)
        }

        guard !objectsWithAssets.isEmpty else { return [] }

        let cacheDirectory = try Self.cacheDirectory()
        var cachedAssets: [SAM3DCachedAsset] = []

        for (objectId, remoteURL) in objectsWithAssets {
            let (data, _) = try await URLSession.shared.data(from: remoteURL)
            let fileExtension = remoteURL.pathExtension.isEmpty ? "ply" : remoteURL.pathExtension
            let fileName = "\(objectId)_\(abs(remoteURL.absoluteString.hashValue)).\(fileExtension)"
            let localURL = cacheDirectory.appendingPathComponent(fileName)
            try data.write(to: localURL, options: [.atomic])

            let previewRemoteURL = response.objects.first { $0.objectId == objectId }?.previewImageURL
            let previewLocalURL: URL?
            if let previewRemoteURL {
                let (previewData, _) = try await URLSession.shared.data(from: previewRemoteURL)
                let previewExtension = previewRemoteURL.pathExtension.isEmpty ? "png" : previewRemoteURL.pathExtension
                let previewFileName = "\(objectId)_preview_\(abs(previewRemoteURL.absoluteString.hashValue)).\(previewExtension)"
                let localPreviewURL = cacheDirectory.appendingPathComponent(previewFileName)
                try previewData.write(to: localPreviewURL, options: [.atomic])
                previewLocalURL = localPreviewURL
            } else {
                previewLocalURL = nil
            }

            cachedAssets.append(
                SAM3DCachedAsset(
                    objectId: objectId,
                    remoteURL: remoteURL,
                    localURL: localURL,
                    previewRemoteURL: previewRemoteURL,
                    previewLocalURL: previewLocalURL
                )
            )
        }

        return cachedAssets
    }

    private static func cacheDirectory() throws -> URL {
        let documentsDirectory = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]
        let directory = documentsDirectory.appendingPathComponent(
            "SAM3DCache",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }
}

enum SAM3DSceneReconciler {
    static func reconcile(
        plan: InteractionWorldPlan,
        response: SAM3DSceneRealizationResponse,
        cachedAssets: [SAM3DCachedAsset],
        useRealizedLayout: Bool = false
    ) -> InteractionWorldPlan {
        let realizedByObjectId = Dictionary(
            uniqueKeysWithValues: response.objects.map { ($0.objectId, $0) }
        )
        let cachedAssetByObjectId = Dictionary(
            uniqueKeysWithValues: cachedAssets.map { ($0.objectId, $0) }
        )

        let objects = plan.objects.map { object in
            guard let realizedObject = realizedByObjectId[object.id] else {
                return object
            }

            let cachedAsset = cachedAssetByObjectId[object.id]
            let visualAsset = WorldObjectVisualAsset(
                format: realizedObject.visualFormat,
                source: .sam3D,
                status: realizedObject.status.worldStatus,
                remoteURL: realizedObject.assetURL,
                localURL: cachedAsset?.localURL,
                previewRemoteURL: realizedObject.previewImageURL,
                previewLocalURL: cachedAsset?.previewLocalURL,
                realizedPosition: realizedObject.position,
                realizedSize: realizedObject.size ?? realizedObject.proxyShape?.size,
                canonicalPose: realizedObject.canonicalPose,
                notes: realizedObject.notes
            )

            return WorldObjectSpec(
                id: object.id,
                displayName: object.displayName,
                description: object.description,
                kind: object.kind,
                position: useRealizedLayout ? realizedObject.position ?? object.position : object.position,
                size: useRealizedLayout ? realizedObject.size ?? realizedObject.proxyShape?.size ?? object.size : object.size,
                color: object.color,
                isInteractive: object.isInteractive,
                visualAsset: visualAsset,
                assetCard: object.assetCard
            )
        }

        return InteractionWorldPlan(
            id: "\(plan.id)_sam3d_realized",
            scenario: plan.scenario,
            objects: objects,
            tasks: plan.tasks
        )
    }
}

enum SAM3DSceneRealizationError: LocalizedError, Equatable {
    case invalidResponse
    case invalidBaseURL(String)
    case requestFailed(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The SAM 3D service response was not an HTTP response."
        case .invalidBaseURL(let value):
            return "Invalid SAM 3D service URL: \(value)"
        case .requestFailed(let statusCode, let body):
            return "SAM 3D request failed with status \(statusCode): \(body)"
        }
    }
}
