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
    """
    You are a scene designer for a language-learning practice app running in spatial computing.

    Given the ScenarioCard below, generate the physical objects needed immediately around a standing learner. The learner stands at the origin and faces -z. Positions and sizes are in meters. Put reachable objects between hip and shoulder height. Counters and tables should usually be around y=0.6 to y=0.8. Keep objects in a compact area in front of the learner.

    ScenarioCard:
    {
      "id": "\(scenario.id)",
      "setting": "\(scenario.setting)",
      "learnerRole": "\(scenario.learnerRole)",
      "sceneGoal": "\(scenario.sceneGoal)",
      "localContext": "\(scenario.localContext)",
      "targetInteractions": \(jsonString(for: scenario.targetInteractions))
    }

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

    Return JSON only.
    """
}

func buildTaskGenerationPrompt(
    scenario: ScenarioCard,
    objects: [WorldObjectSpec]
) -> String {
    let objectSummaries = objects.map { object in
        [
            "id": object.id,
            "displayName": object.displayName,
            "description": object.description,
            "kind": object.kind.typeName
        ]
    }

    return """
    You are wiring interactions for a language-learning practice scene. Generate a task queue that covers the scenario's targetInteractions using only the available primitive vocabulary.

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

    Cover the targetInteractions in order. Reference only object IDs from Available objects. Return JSON only.
    """
}

private struct ObjectGenerationResponse: Codable {
    let objects: [WorldObjectSpec]
}

private struct TaskGenerationResponse: Codable {
    let tasks: [InteractionTask]
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
