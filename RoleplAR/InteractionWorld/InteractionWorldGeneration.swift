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

            let plan = InteractionWorldPlan(
                id: "\(scenario.id)_generated_attempt_\(attemptNumber)",
                scenario: scenario,
                objects: objects,
                tasks: tasks
            )

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
                totalGenerationTimeSeconds: Date().timeIntervalSince(pipelineStart)
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

    var succeeded: Bool {
        plan != nil
    }
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

struct SAM3DRealizedObject: Codable, Equatable, Identifiable {
    var id: String { objectId }

    let objectId: String
    let status: SAM3DRealizedObjectStatus
    let visualFormat: WorldObjectVisualFormat
    let assetURL: URL?
    let position: SIMD3<Float>?
    let size: SIMD3<Float>?
    let proxyShape: SAM3DProxyShapeSpec?
    let notes: String?
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
    var timeoutInterval: TimeInterval = 300

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
            cachedAssets.append(
                SAM3DCachedAsset(
                    objectId: objectId,
                    remoteURL: remoteURL,
                    localURL: localURL
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
        cachedAssets: [SAM3DCachedAsset]
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
                notes: realizedObject.notes
            )

            return WorldObjectSpec(
                id: object.id,
                displayName: object.displayName,
                description: object.description,
                kind: object.kind,
                position: realizedObject.position ?? object.position,
                size: realizedObject.size ?? realizedObject.proxyShape?.size ?? object.size,
                color: object.color,
                isInteractive: object.isInteractive,
                visualAsset: visualAsset
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
