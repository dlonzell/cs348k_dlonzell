import RealityKit
import Foundation

/// Loads USDZ models from the usdz_project service
class USDZLoader {
    static let shared = USDZLoader()

    /// Base URL for the usdz_project service
    /// Change this to your deployed service URL if not running locally
    var baseURL = "http://localhost:8000"

    /// Cache directory for downloaded models
    private let cacheDirectory: URL

    /// In-memory cache of loaded entities
    private var entityCache: [String: Entity] = [:]

    private init() {
        // Set up cache directory - use caches directory as fallback
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        cacheDirectory = documentsDir.appendingPathComponent("USDZCache", isDirectory: true)

        // Create cache directory if needed
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// Load a 3D model from a text prompt
    /// - Parameter prompt: Text description of the object to generate
    /// - Returns: The loaded Entity
    func loadModel(prompt: String) async throws -> Entity {
        // Check in-memory cache first
        let cacheKey = prompt.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")

        if let cached = entityCache[cacheKey] {
            // Return a clone so each instance is independent
            return cached.clone(recursive: true)
        }

        // Check file cache
        let cachedFileURL = cacheDirectory.appendingPathComponent("\(cacheKey).usdz")
        if FileManager.default.fileExists(atPath: cachedFileURL.path) {
            print("Loading USDZ from cache: \(cachedFileURL.lastPathComponent)")
            let entity = try await loadFromFile(cachedFileURL)
            entityCache[cacheKey] = entity
            return entity.clone(recursive: true)
        }

        // Fetch from service
        print("Fetching USDZ from service for: \(prompt)")
        let entity = try await fetchAndCacheModel(prompt: prompt, cacheKey: cacheKey)
        entityCache[cacheKey] = entity
        return entity.clone(recursive: true)
    }

    /// Fetch model from usdz_project service
    private func fetchAndCacheModel(prompt: String, cacheKey: String) async throws -> Entity {
        // Build URL with query parameter
        guard var components = URLComponents(string: "\(baseURL)/generate-usd-from-prompt") else {
            throw USDZLoaderError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "prompt", value: prompt)]

        guard let url = components.url else {
            throw USDZLoaderError.invalidURL
        }

        // Make POST request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180 // 3 minutes for generation

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw USDZLoaderError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            // Try to parse error message
            if let errorDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorMessage = errorDict["error"] as? String {
                throw USDZLoaderError.serverError(errorMessage)
            }
            throw USDZLoaderError.httpError(httpResponse.statusCode)
        }

        // Save to cache
        let cachedFileURL = cacheDirectory.appendingPathComponent("\(cacheKey).usdz")
        try data.write(to: cachedFileURL)

        print("Saved USDZ model to cache: \(cachedFileURL.lastPathComponent)")

        // Load entity from cached file
        return try await loadFromFile(cachedFileURL)
    }

    /// Load entity from a local USDZ file
    private func loadFromFile(_ url: URL) async throws -> Entity {
        return try await Entity(contentsOf: url)
    }

    /// Clear the cache
    func clearCache() {
        entityCache.removeAll()
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        print("USDZ cache cleared")
    }

    /// Check if the usdz_project service is available
    func checkServiceAvailability() async -> Bool {
        // Try the root endpoint since /health may not exist
        guard let url = URL(string: baseURL) else {
            return false
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 5
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                // Any response means the service is running
                return httpResponse.statusCode < 500
            }
        } catch {
            print("USDZ service not available: \(error.localizedDescription)")
        }

        return false
    }

    /// Get cache directory URL for debugging
    func getCacheDirectoryURL() -> URL {
        return cacheDirectory
    }

    /// List cached models
    func listCachedModels() -> [String] {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: cacheDirectory.path) else {
            return []
        }
        return files.filter { $0.hasSuffix(".usdz") }
    }
}

enum USDZLoaderError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case serverError(String)
    case fileNotFound

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL for USDZ service"
        case .invalidResponse:
            return "Invalid response from USDZ service"
        case .httpError(let code):
            return "HTTP error \(code) from USDZ service"
        case .serverError(let message):
            return "Server error: \(message)"
        case .fileNotFound:
            return "USDZ file not found in cache"
        }
    }
}
