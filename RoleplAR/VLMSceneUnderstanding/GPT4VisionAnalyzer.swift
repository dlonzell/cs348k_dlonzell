import Foundation
import SwiftUI
import CoreVideo
import CoreImage
import Alamofire

/// Analyzes scenes using OpenAI's GPT-4 Vision model
/// This is a REAL VLM that actually looks at the rendered scene
class GPT4VisionAnalyzer: SceneAnalyzer, ObservableObject {

    // MARK: - Published State

    @Published private(set) var isAnalyzing = false
    @Published private(set) var lastError: String?
    @Published var lastRawResponse: String?

    // MARK: - Configuration

    /// OpenAI API endpoint for chat completions
    private let apiURL = "https://api.openai.com/v1/chat/completions"

    /// Model to use (gpt-4-vision-preview or gpt-4o)
    var model: String = "gpt-4o"

    /// System prompt providing context about the scene
    var systemPrompt: String = """
        You are a vision system analyzing a 3D rendered scene from a VR/AR application.

        The scene may contain:
        - A brown TABLE (flat rectangular box)
        - A red MENU (thin flat rectangle)
        - A cyan TEACUP (small cylinder)
        - An orange BASEBALL BAT (elongated object)
        - A white BASEBALL (small sphere)
        - HAND SKELETONS: cyan/white spheres representing tracked hand positions

        Your task is to:
        1. Count how many hands are visible (0, 1, or 2)
        2. Identify which scene objects are visible
        3. Determine what interaction is occurring
        4. Provide a natural language SUMMARY of what you see

        The summary field is very important - describe what's happening naturally:
        - "User is tapping the teacup with the baseball bat"
        - "User is stacking the ball on top of the menu"
        - "User is holding the bat in one hand and reaching for the cup with the other"
        - "Objects are resting on the table, no interaction occurring"

        Be specific about spatial relationships and interactions between objects.
        """

    /// Maximum tokens for response
    var maxTokens: Int = 200

    /// Temperature for response randomness
    var temperature: Double = 0.1

    /// Minimum interval between API calls (to avoid rate limiting)
    /// Lower = more frequent analysis, but more API calls
    var minAnalysisInterval: TimeInterval = 0.5

    private var lastAnalysisTime: Date = .distantPast

    // MARK: - Initialization

    init() {}

    // MARK: - SceneAnalyzer Protocol

    func analyze(frame: SceneFrame) async throws -> ActionClassification {
        // Rate limiting
        let timeSinceLastAnalysis = Date().timeIntervalSince(lastAnalysisTime)
        if timeSinceLastAnalysis < minAnalysisInterval {
            // Return idle if called too frequently
            return ActionClassification(action: .idle, confidence: 0.5)
        }

        guard let pixelBuffer = frame.pixelBuffer else {
            throw GPT4VisionError.noImageData
        }

        isAnalyzing = true
        lastAnalysisTime = Date()
        defer { isAnalyzing = false }

        // Convert pixel buffer to base64 image
        let base64Image = try convertToBase64(pixelBuffer: pixelBuffer)

        // Build the prompt
        let objectsList = frame.sceneObjects.joined(separator: ", ")
        let handInfo = "Left hand tracked: \(frame.leftHandJoints.isEmpty ? "NO" : "YES"), Right hand tracked: \(frame.rightHandJoints.isEmpty ? "NO" : "YES")"
        let userPrompt = """
            Expected objects: \(objectsList)
            Hand tracking status: \(handInfo)

            Analyze this rendered scene and tell me:
            1. How many hands do you SEE in the image?
            2. Which objects are visible?
            3. What action is occurring?
            4. IMPORTANT: Write a natural summary of what's happening in 1-2 sentences. Describe any interactions between objects (e.g., "tapping X with Y", "stacking items", "using the bat to push the cup").

            Respond ONLY with a JSON object in this exact format (no other text):
            {"hands_visible": 0, "objects_visible": ["table", "menu"], "action": "idle|reaching|picking_up|holding|placing|pointing|waving", "object": "menu|teacup|baseballBat|baseball|null", "confidence": 0.0-1.0, "summary": "Natural language description of what you see happening in the scene"}
            """

        // Call GPT-4V API
        let response = try await callGPT4Vision(base64Image: base64Image, prompt: userPrompt)

        // Parse response
        let classification = try parseResponse(response, timestamp: frame.timestamp)

        return classification
    }

    // MARK: - API Call

    private func callGPT4Vision(base64Image: String, prompt: String) async throws -> String {
        let headers: HTTPHeaders = [
            "Authorization": "Bearer \(Constants.openAIAPIKey)",
            "Content-Type": "application/json"
        ]

        // Build the request body with image
        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "system",
                    "content": systemPrompt
                ],
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": prompt
                        ],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/jpeg;base64,\(base64Image)",
                                "detail": "low"  // Use low detail for faster processing
                            ]
                        ]
                    ]
                ]
            ],
            "max_tokens": maxTokens,
            "temperature": temperature
        ]

        return try await withCheckedThrowingContinuation { continuation in
            AF.request(
                apiURL,
                method: .post,
                parameters: requestBody,
                encoding: JSONEncoding.default,
                headers: headers
            )
            .validate()
            .responseDecodable(of: GPT4VisionResponse.self) { response in
                switch response.result {
                case .success(let gptResponse):
                    if let content = gptResponse.choices.first?.message.content {
                        self.lastRawResponse = content
                        continuation.resume(returning: content)
                    } else {
                        continuation.resume(throwing: GPT4VisionError.noOutput)
                    }
                case .failure(let error):
                    self.lastError = error.localizedDescription
                    print("GPT-4V API Error: \(error)")
                    if let data = response.data, let errorStr = String(data: data, encoding: .utf8) {
                        print("Error response: \(errorStr)")
                    }
                    continuation.resume(throwing: GPT4VisionError.apiError(error.localizedDescription))
                }
            }
        }
    }

    // MARK: - Image Conversion

    private func convertToBase64(pixelBuffer: CVPixelBuffer) throws -> String {
        // Convert CVPixelBuffer to CGImage via CIImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()

        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            throw GPT4VisionError.imageConversionFailed
        }

        // Convert CGImage to JPEG data
        guard let jpegData = cgImageToJPEG(cgImage, quality: 0.7) else {
            throw GPT4VisionError.imageConversionFailed
        }

        return jpegData.base64EncodedString()
    }

    private func cgImageToJPEG(_ cgImage: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]

        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return data as Data
    }

    // MARK: - Response Parsing

    private func parseResponse(_ response: String, timestamp: Date) throws -> ActionClassification {
        // Extract JSON from response
        let jsonString = extractJSON(from: response)

        guard let data = jsonString.data(using: .utf8) else {
            throw GPT4VisionError.invalidResponse(response)
        }

        do {
            let parsed = try JSONDecoder().decode(VLMResponseFormat.self, from: data)

            let actionType = ActionType(rawValue: parsed.action) ?? .unknown

            // Use summary if available, fall back to description
            let sceneSummary = parsed.summary ?? parsed.description

            // Log detailed info about what GPT-4V sees
            let handsStr = parsed.hands_visible.map { "\($0)" } ?? "?"
            let objectsStr = parsed.objects_visible?.joined(separator: ", ") ?? "?"
            vlmLog("GPT-4V sees: \(handsStr) hands, objects: [\(objectsStr)], action: \(actionType.displayName)", category: "GPT4V")
            if let summary = sceneSummary, !summary.isEmpty {
                vlmLog("GPT-4V summary: \(summary)", category: "GPT4V")
            }

            return ActionClassification(
                action: actionType,
                object: parsed.object,
                target: parsed.target,
                confidence: parsed.confidence,
                timestamp: timestamp,
                sceneSummary: sceneSummary
            )
        } catch {
            // Try plain text parsing as fallback
            print("JSON parsing failed, trying plain text: \(response)")
            return parseFromPlainText(response, timestamp: timestamp)
        }
    }

    private func extractJSON(from text: String) -> String {
        if let startIndex = text.firstIndex(of: "{"),
           let endIndex = text.lastIndex(of: "}") {
            return String(text[startIndex...endIndex])
        }
        return text
    }

    private func parseFromPlainText(_ text: String, timestamp: Date) -> ActionClassification {
        let lowercased = text.lowercased()

        var action: ActionType = .idle
        var object: String? = nil
        var confidence: Float = 0.5

        if lowercased.contains("picking") || lowercased.contains("pick up") || lowercased.contains("lifting") {
            action = .pickingUp
            confidence = 0.7
        } else if lowercased.contains("placing") || lowercased.contains("putting down") || lowercased.contains("setting") {
            action = .placing
            confidence = 0.7
        } else if lowercased.contains("holding") || lowercased.contains("carrying") || lowercased.contains("elevated") {
            action = .holding
            confidence = 0.7
        } else if lowercased.contains("reaching") {
            action = .reaching
            confidence = 0.6
        } else if lowercased.contains("pointing") {
            action = .pointing
            confidence = 0.6
        } else if lowercased.contains("waving") {
            action = .waving
            confidence = 0.6
        }

        if lowercased.contains("menu") {
            object = "menu"
        } else if lowercased.contains("cup") || lowercased.contains("teacup") {
            object = "teacup"
        }

        return ActionClassification(
            action: action,
            object: object,
            target: nil,
            confidence: confidence,
            timestamp: timestamp
        )
    }
}

// MARK: - Response Types

private struct GPT4VisionResponse: Decodable {
    let choices: [GPT4VisionChoice]
}

private struct GPT4VisionChoice: Decodable {
    let message: GPT4VisionMessage
}

private struct GPT4VisionMessage: Decodable {
    let content: String
}

private struct VLMResponseFormat: Decodable {
    let action: String
    let object: String?
    let target: String?
    let confidence: Float
    let hands_visible: Int?
    let objects_visible: [String]?
    let description: String?  // Legacy field
    let summary: String?      // New flexible summary field
}

// MARK: - Errors

enum GPT4VisionError: LocalizedError {
    case noImageData
    case imageConversionFailed
    case apiError(String)
    case noOutput
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .noImageData:
            return "No image data in frame"
        case .imageConversionFailed:
            return "Failed to convert image for API"
        case .apiError(let message):
            return "GPT-4V API error: \(message)"
        case .noOutput:
            return "No response from GPT-4V"
        case .invalidResponse(let response):
            return "Could not parse response: \(response)"
        }
    }
}
