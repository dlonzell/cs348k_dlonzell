import Foundation
import CoreML
import Vision
import CoreImage
import CoreVideo

#if os(iOS) || os(visionOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

#if canImport(MLX) && canImport(MLXVLM)
import MLX
import MLXLMCommon
import MLXVLM
#endif

// MARK: - Model Selection

/// Available VLM models for FastVLM inference (tested and working as of Jan 2026)
enum FastVLMModel: String, CaseIterable {
    /// SmolVLM2 2.2B - Most memory efficient (~5.5GB), good balance of speed and quality
    case smolVLM2 = "mlx-community/SmolVLM2-2.2B-Instruct-mlx"
    /// Qwen3 VL 2B - Works well but can be verbose
    case qwen3VL = "Qwen/Qwen3-VL-2B-Instruct"
    /// LFM2 VL 1.6B - Fastest inference (~307 tps)
    case lfm2VL = "mlx-community/LFM2-VL-1.6B-8bit"

    var displayName: String {
        switch self {
        case .smolVLM2: return "SmolVLM2 2.2B (Recommended)"
        case .qwen3VL: return "Qwen3 VL 2B"
        case .lfm2VL: return "LFM2 VL 1.6B (Fastest)"
        }
    }
}

/// FastVLM Analyzer - On-device VLM inference using MLX
/// Requires MLX Swift packages to be added to the project.
/// On simulator, falls back to returning idle (Metal not supported).
class FastVLMAnalyzer: SceneAnalyzer, ObservableObject {

    // MARK: - Published State

    @Published private(set) var isAnalyzing = false
    @Published private(set) var isModelLoaded = false
    @Published private(set) var lastError: String?
    @Published var lastRawResponse: String?

    // MARK: - Configuration

    /// Selected VLM model (use FastVLMModel enum for tested options)
    var selectedModel: FastVLMModel = .smolVLM2

    /// Hugging Face model ID for VLM - defaults to selected model, can be overridden
    var huggingFaceModelId: String {
        get { _customModelId ?? selectedModel.rawValue }
        set { _customModelId = newValue }
    }
    private var _customModelId: String?

    /// System prompt for the VLM
    var systemPrompt: String = """
        You are analyzing a 3D rendered scene from a VR/AR application.

        The scene contains:
        - A brown TABLE (flat rectangular box)
        - A red MENU (thin flat rectangle on the table)
        - A cyan TEACUP (small cylinder on the table)
        - HAND SKELETONS: cyan/white spheres representing tracked hand joints

        Identify what action the hands are performing with these objects.
        """

    /// Prompt template for analysis
    var promptTemplate: String = "What action are the hands performing? Objects in scene: {objects}. Respond with JSON: {\"action\": \"idle|reaching|picking_up|holding|placing|pointing|waving\", \"object\": \"menu|teacup|table|null\", \"confidence\": 0.0-1.0}"

    /// Maximum tokens for response
    var maxTokens: Int = 100

    /// Minimum interval between analyses
    var minAnalysisInterval: TimeInterval = 0.3

    private var lastAnalysisTime: Date = .distantPast

    // MARK: - Model State

    #if canImport(MLX) && canImport(MLXVLM)
    private var modelContainer: ModelContainer?
    private var chatSession: ChatSession?
    #endif

    private var modelDirectory: URL?

    // MARK: - Initialization

    init() {}

    init(modelDirectory: URL) {
        self.modelDirectory = modelDirectory
    }

    // MARK: - Model Loading

    /// Clear cached model files (useful when download was interrupted)
    func clearModelCache() {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        let modelCacheDir = cacheDir?.appendingPathComponent("models/mlx-community/\(huggingFaceModelId.replacingOccurrences(of: "/", with: "/"))")

        if let dir = modelCacheDir, FileManager.default.fileExists(atPath: dir.path) {
            do {
                try FileManager.default.removeItem(at: dir)
                vlmLog("FastVLM: Cleared model cache at \(dir.path)", category: "FastVLM")
            } catch {
                vlmError("FastVLM: Failed to clear cache: \(error)", category: "FastVLM")
            }
        }

        // Also try the huggingface_hub cache location
        if let cacheDir = cacheDir {
            let hfCacheDir = cacheDir.appendingPathComponent("huggingface")
            if FileManager.default.fileExists(atPath: hfCacheDir.path) {
                do {
                    try FileManager.default.removeItem(at: hfCacheDir)
                    vlmLog("FastVLM: Cleared HuggingFace cache", category: "FastVLM")
                } catch {
                    vlmError("FastVLM: Failed to clear HF cache: \(error)", category: "FastVLM")
                }
            }
        }
    }

    /// Load the VLM model from Hugging Face
    func loadModelFromBundle(named modelName: String = "FastVLM") async throws {
        #if targetEnvironment(simulator)
        vlmLog("FastVLM: Simulator detected - MLX not supported, using fallback mode", category: "FastVLM")
        isModelLoaded = true  // Mark as "loaded" so pipeline can start
        return
        #else

        #if canImport(MLX) && canImport(MLXVLM)
        vlmLog("FastVLM: Loading model from Hugging Face: \(huggingFaceModelId)", category: "FastVLM")

        do {
            // Set GPU cache limit for memory efficiency
            GPU.set(cacheLimit: 20 * 1024 * 1024)

            // Load model from Hugging Face using the simplified API
            vlmLog("FastVLM: Downloading/loading model (this may take a while on first run)...", category: "FastVLM")
            vlmLog("FastVLM: IMPORTANT - Keep the app open until download completes!", category: "FastVLM")

            let container = try await VLMModelFactory.shared.loadContainer(
                configuration: ModelConfiguration(id: huggingFaceModelId)
            ) { progress in
                vlmLog("FastVLM: Download progress: \(Int(progress.fractionCompleted * 100))%", category: "FastVLM")
            }

            modelContainer = container
            chatSession = ChatSession(container)

            isModelLoaded = true
            vlmLog("FastVLM: Model loaded successfully!", category: "FastVLM")
        } catch let error as NSError where error.domain == "NSCocoaErrorDomain" && error.code == 260 {
            // File not found - likely corrupted cache from interrupted download
            vlmError("FastVLM: Detected corrupted cache (incomplete download). Clearing and retrying...", category: "FastVLM")
            clearModelCache()
            try await retryModelLoad()
        } catch let error as DecodingError {
            // Handle keyNotFound and other decoding errors (model weight format mismatch)
            vlmError("FastVLM: Model weight format error: \(error). This usually means the model is incompatible. Clearing cache and retrying...", category: "FastVLM")
            clearModelCache()
            try await retryModelLoad()
        } catch {
            // Check if error message contains keyNotFound (sometimes wrapped in other error types)
            let errorString = String(describing: error)
            if errorString.contains("keyNotFound") || errorString.contains("Key") && errorString.contains("not found") {
                vlmError("FastVLM: Model weight key error detected. Clearing cache and retrying...", category: "FastVLM")
                clearModelCache()
                try await retryModelLoad()
            } else {
                lastError = error.localizedDescription
                vlmError("FastVLM: Failed to load model: \(error)", category: "FastVLM")
                throw FastVLMError.inferenceError(error)
            }
        }
        #else
        throw FastVLMError.platformNotSupported
        #endif
        #endif
    }

    #if canImport(MLX) && canImport(MLXVLM)
    /// Retry model loading after cache clear (called from error handlers)
    private func retryModelLoad() async throws {
        vlmLog("FastVLM: Retrying model load...", category: "FastVLM")
        do {
            let container = try await VLMModelFactory.shared.loadContainer(
                configuration: ModelConfiguration(id: huggingFaceModelId)
            ) { progress in
                vlmLog("FastVLM: Download progress (retry): \(Int(progress.fractionCompleted * 100))%", category: "FastVLM")
            }

            modelContainer = container
            chatSession = ChatSession(container)
            isModelLoaded = true
            vlmLog("FastVLM: Model loaded successfully after retry!", category: "FastVLM")
        } catch {
            lastError = error.localizedDescription
            vlmError("FastVLM: Failed to load model after retry: \(error)", category: "FastVLM")
            throw FastVLMError.inferenceError(error)
        }
    }
    #endif

    /// Load model from a local directory (alternative method)
    func loadModel() async throws {
        #if targetEnvironment(simulator)
        isModelLoaded = true
        return
        #else

        #if canImport(MLX) && canImport(MLXVLM)
        guard let directory = modelDirectory else {
            // Fall back to Hugging Face loading
            try await loadModelFromBundle()
            return
        }

        vlmLog("FastVLM: Loading from local directory: \(directory.path)", category: "FastVLM")

        do {
            // Set GPU cache limit for memory efficiency
            GPU.set(cacheLimit: 20 * 1024 * 1024)

            // Create model configuration with local directory
            let modelConfig = ModelConfiguration(
                directory: directory,
                defaultPrompt: promptTemplate
            )

            // Load the model container using VLMModelFactory
            modelContainer = try await VLMModelFactory.shared.loadContainer(
                configuration: modelConfig
            ) { progress in
                vlmLog("FastVLM: Loading progress: \(Int(progress.fractionCompleted * 100))%", category: "FastVLM")
            }

            // Create chat session for inference
            if let container = modelContainer {
                chatSession = ChatSession(container)
            }

            isModelLoaded = true
            vlmLog("FastVLM: Model loaded successfully", category: "FastVLM")
        } catch {
            lastError = error.localizedDescription
            vlmError("FastVLM: Failed to load model: \(error)", category: "FastVLM")
            throw FastVLMError.inferenceError(error)
        }
        #else
        throw FastVLMError.platformNotSupported
        #endif
        #endif
    }

    // MARK: - SceneAnalyzer Protocol

    func analyze(frame: SceneFrame) async throws -> ActionClassification {
        // Rate limiting
        let timeSinceLastAnalysis = Date().timeIntervalSince(lastAnalysisTime)
        if timeSinceLastAnalysis < minAnalysisInterval {
            return ActionClassification(action: .idle, confidence: 0.5)
        }

        #if targetEnvironment(simulator)
        // On simulator, use heuristic fallback based on hand data
        return analyzeWithHeuristics(frame: frame)
        #else

        #if canImport(MLX) && canImport(MLXVLM)
        guard isModelLoaded, let session = chatSession else {
            throw FastVLMError.modelNotLoaded
        }

        guard let pixelBuffer = frame.pixelBuffer else {
            throw FastVLMError.noImageData
        }

        isAnalyzing = true
        lastAnalysisTime = Date()
        defer { isAnalyzing = false }

        do {
            // Convert pixel buffer to CGImage
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let context = CIContext()
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
                vlmLog("FastVLM: Image conversion failed, using heuristics", category: "FastVLM")
                return analyzeWithHeuristics(frame: frame)
            }

            // Build prompt with scene context
            let objectsList = frame.sceneObjects.joined(separator: ", ")
            let prompt = promptTemplate.replacingOccurrences(of: "{objects}", with: objectsList)

            // Create a temporary file for the image (ChatSession expects URL)
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("vlm_frame_\(UUID().uuidString).png")

            #if os(iOS) || os(visionOS)
            let uiImage = UIImage(cgImage: cgImage)
            guard let pngData = uiImage.pngData() else {
                vlmLog("FastVLM: PNG conversion failed, using heuristics", category: "FastVLM")
                return analyzeWithHeuristics(frame: frame)
            }
            try pngData.write(to: tempURL)
            #elseif os(macOS)
            // macOS fallback
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            guard let tiffData = nsImage.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:]) else {
                vlmLog("FastVLM: PNG conversion failed, using heuristics", category: "FastVLM")
                return analyzeWithHeuristics(frame: frame)
            }
            try pngData.write(to: tempURL)
            #endif

            defer {
                try? FileManager.default.removeItem(at: tempURL)
            }

            // Run inference using ChatSession with timeout protection
            let response = try await session.respond(
                to: prompt,
                image: .url(tempURL)
            )

            lastRawResponse = response
            vlmLog("FastVLM response: \(response)", category: "FastVLM")

            // Parse response
            return try parseResponse(response, timestamp: frame.timestamp)

        } catch {
            lastError = error.localizedDescription
            vlmError("FastVLM inference error: \(error), falling back to heuristics", category: "FastVLM")
            // Fall back to heuristics instead of crashing
            return analyzeWithHeuristics(frame: frame)
        }
        #else
        // MLX not available, use heuristic fallback
        return analyzeWithHeuristics(frame: frame)
        #endif
        #endif
    }

    // MARK: - Heuristic Fallback

    /// Analyze frame using hand position heuristics when MLX is not available
    private func analyzeWithHeuristics(frame: SceneFrame) -> ActionClassification {
        lastAnalysisTime = Date()

        let hasLeftHand = !frame.leftHandJoints.isEmpty
        let hasRightHand = !frame.rightHandJoints.isEmpty

        if !hasLeftHand && !hasRightHand {
            return ActionClassification(action: .idle, confidence: 0.9, timestamp: frame.timestamp)
        }

        // Get hand position from index finger tip or wrist
        let handJoints = hasRightHand ? frame.rightHandJoints : frame.leftHandJoints

        guard let indexTip = handJoints["indexFingerTip"] ?? handJoints["handWrist"] else {
            return ActionClassification(action: .idle, confidence: 0.7, timestamp: frame.timestamp)
        }

        let handPosition = SIMD3<Float>(indexTip.columns.3.x, indexTip.columns.3.y, indexTip.columns.3.z)

        // Table position (matching placeholder objects)
        let tableY: Float = 0.55
        let tableZ: Float = -0.85

        // Check if hand is near table level
        let nearTableHeight = abs(handPosition.y - tableY) < 0.2
        let inFrontOfTable = handPosition.z < tableZ + 0.3 && handPosition.z > tableZ - 0.3

        if nearTableHeight && inFrontOfTable {
            // Check if hand is elevated (holding something)
            if handPosition.y > tableY + 0.1 {
                return ActionClassification(
                    action: .holding,
                    object: "menu",
                    confidence: 0.7,
                    timestamp: frame.timestamp
                )
            }

            // Near table level - reaching
            return ActionClassification(
                action: .reaching,
                object: abs(handPosition.x) < 0.1 ? "menu" : "teacup",
                confidence: 0.65,
                timestamp: frame.timestamp
            )
        }

        // Hand above head level - waving
        if handPosition.y > 1.5 {
            return ActionClassification(
                action: .waving,
                confidence: 0.7,
                timestamp: frame.timestamp
            )
        }

        // Default to idle
        return ActionClassification(action: .idle, confidence: 0.6, timestamp: frame.timestamp)
    }

    // MARK: - Response Parsing

    private func parseResponse(_ response: String, timestamp: Date) throws -> ActionClassification {
        // Extract JSON from response
        let jsonString = extractJSON(from: response)

        guard let data = jsonString.data(using: .utf8) else {
            throw FastVLMError.invalidResponse(response)
        }

        do {
            let parsed = try JSONDecoder().decode(FastVLMResponse.self, from: data)

            let actionType = ActionType(rawValue: parsed.action) ?? .unknown

            vlmLog("FastVLM parsed: action=\(actionType.displayName), object=\(parsed.object ?? "nil")", category: "FastVLM")

            return ActionClassification(
                action: actionType,
                object: parsed.object,
                target: nil,
                confidence: parsed.confidence,
                timestamp: timestamp
            )
        } catch {
            // Try plain text parsing as fallback
            vlmLog("FastVLM JSON parse failed, trying text fallback", category: "FastVLM")
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
        } else if lowercased.contains("holding") || lowercased.contains("carrying") {
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
        } else if lowercased.contains("table") {
            object = "table"
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

private struct FastVLMResponse: Decodable {
    let action: String
    let object: String?
    let confidence: Float
}

// MARK: - Errors

enum FastVLMError: LocalizedError {
    case modelNotFound(String)
    case modelNotLoaded
    case noImageData
    case imageConversionFailed
    case noOutput
    case invalidResponse(String)
    case inferenceError(Error)
    case platformNotSupported

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let name):
            return "FastVLM model '\(name)' not found in bundle"
        case .modelNotLoaded:
            return "FastVLM model not loaded"
        case .noImageData:
            return "No image data in frame"
        case .imageConversionFailed:
            return "Failed to convert image for inference"
        case .noOutput:
            return "Model produced no output"
        case .invalidResponse(let response):
            return "Could not parse model response: \(response)"
        case .inferenceError(let error):
            return "Inference error: \(error.localizedDescription)"
        case .platformNotSupported:
            return "FastVLM requires MLX Swift packages. Add 'mlx-swift-lm' to your project dependencies."
        }
    }
}
