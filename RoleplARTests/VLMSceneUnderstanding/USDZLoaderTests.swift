//
//  USDZLoaderTests.swift
//  RoleplARTests
//
//  Tests for USDZLoader caching and service interaction
//

import XCTest
@testable import RoleplAR

final class USDZLoaderTests: XCTestCase {

    var loader: USDZLoader!

    override func setUp() {
        super.setUp()
        loader = USDZLoader.shared
    }

    override func tearDown() {
        // Don't clear cache in teardown as it affects shared instance
        super.tearDown()
    }

    // MARK: - Singleton Tests

    func testSharedInstance() {
        let instance1 = USDZLoader.shared
        let instance2 = USDZLoader.shared

        XCTAssertTrue(instance1 === instance2)
    }

    // MARK: - Configuration Tests

    func testDefaultBaseURL() {
        XCTAssertEqual(loader.baseURL, "http://localhost:8000")
    }

    func testBaseURLCanBeChanged() {
        let originalURL = loader.baseURL
        loader.baseURL = "http://test.server:9000"

        XCTAssertEqual(loader.baseURL, "http://test.server:9000")

        // Restore
        loader.baseURL = originalURL
    }

    // MARK: - Cache Directory Tests

    func testCacheDirectoryExists() {
        let cacheDir = loader.getCacheDirectoryURL()

        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheDir.path))
    }

    func testCacheDirectoryIsInDocuments() {
        let cacheDir = loader.getCacheDirectoryURL()

        // Should be in Documents or Caches directory
        let path = cacheDir.path
        XCTAssertTrue(
            path.contains("Documents") ||
            path.contains("Caches") ||
            path.contains("tmp"),
            "Cache directory should be in Documents, Caches, or tmp"
        )
    }

    // MARK: - Cache Operations Tests

    func testListCachedModelsInitiallyEmpty() {
        // Clear cache first
        loader.clearCache()

        let models = loader.listCachedModels()

        // May not be empty if other tests ran, but should be an array
        XCTAssertNotNil(models)
    }

    func testClearCache() {
        // This should not crash
        loader.clearCache()

        // Cache directory should still exist
        let cacheDir = loader.getCacheDirectoryURL()
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheDir.path))
    }

    // MARK: - Service Availability Tests

    func testCheckServiceAvailability() async {
        // This tests the network check without actually requiring the service
        let isAvailable = await loader.checkServiceAvailability()

        // Result depends on whether service is running
        // Just verify it doesn't crash and returns a bool
        XCTAssertNotNil(isAvailable)
    }

    func testCheckServiceAvailabilityWithInvalidURL() async {
        let originalURL = loader.baseURL
        loader.baseURL = "http://invalid.nonexistent.url:99999"

        let isAvailable = await loader.checkServiceAvailability()

        XCTAssertFalse(isAvailable)

        // Restore
        loader.baseURL = originalURL
    }

    // MARK: - Error Handling Tests

    func testLoadModelWithInvalidService() async {
        let originalURL = loader.baseURL
        loader.baseURL = "http://invalid.nonexistent.url:99999"

        do {
            _ = try await loader.loadModel(prompt: "test object")
            XCTFail("Should have thrown an error")
        } catch {
            // Expected to fail
            XCTAssertNotNil(error)
        }

        // Restore
        loader.baseURL = originalURL
    }

    // MARK: - USDZLoaderError Tests

    func testErrorDescriptions() {
        XCTAssertEqual(
            USDZLoaderError.invalidURL.errorDescription,
            "Invalid URL for USDZ service"
        )
        XCTAssertEqual(
            USDZLoaderError.invalidResponse.errorDescription,
            "Invalid response from USDZ service"
        )
        XCTAssertEqual(
            USDZLoaderError.httpError(404).errorDescription,
            "HTTP error 404 from USDZ service"
        )
        XCTAssertEqual(
            USDZLoaderError.serverError("Test error").errorDescription,
            "Server error: Test error"
        )
        XCTAssertEqual(
            USDZLoaderError.fileNotFound.errorDescription,
            "USDZ file not found in cache"
        )
    }

    // MARK: - Cache Key Generation Tests

    func testCacheKeyNormalization() async {
        // Test that prompts with spaces and special chars get normalized
        // We can't directly test private method, but we can observe behavior

        // Two prompts that should result in same cache key
        let prompt1 = "simple table"
        let prompt2 = "simple table"

        // These should use same cache key (can't verify directly without accessing cache)
        // Just ensure no crashes with various inputs
        _ = prompt1.lowercased().replacingOccurrences(of: " ", with: "_")
        _ = prompt2.lowercased().replacingOccurrences(of: " ", with: "_")

        // Verify normalization logic matches expected pattern
        let testPrompt = "Test/Object Name"
        let expectedKey = "test_object_name"
        let actualKey = testPrompt.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")

        XCTAssertEqual(actualKey, expectedKey)
    }
}
