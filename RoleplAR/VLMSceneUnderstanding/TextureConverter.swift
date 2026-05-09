import Metal
import CoreVideo
import Accelerate
import UIKit
import CoreImage
import SwiftUI

/// Converts Metal textures to formats suitable for VLM input
enum TextureConverter {

    /// Convert MTLTexture to CVPixelBuffer
    /// - Parameters:
    ///   - texture: The source Metal texture (rgba8Unorm)
    ///   - device: The Metal device
    /// - Returns: A CVPixelBuffer containing the texture data
    static func convert(texture: MTLTexture, device: MTLDevice) throws -> CVPixelBuffer {
        let width = texture.width
        let height = texture.height

        // Create pixel buffer
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferMetalCompatibilityKey: true
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw TextureConverterError.pixelBufferCreationFailed
        }

        // Lock the pixel buffer
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            throw TextureConverterError.pixelBufferLockFailed
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)

        // Copy texture data to pixel buffer
        // Note: This requires a staging texture for GPU -> CPU transfer
        let stagingTexture = try createStagingTexture(from: texture, device: device)

        // Use a blit command to copy to staging
        guard let commandQueue = device.makeCommandQueue(),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            throw TextureConverterError.commandCreationFailed
        }

        blitEncoder.copy(from: texture, to: stagingTexture)
        blitEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        // Now read from staging texture
        let region = MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(width: width, height: height, depth: 1)
        )

        stagingTexture.getBytes(
            baseAddress,
            bytesPerRow: bytesPerRow,
            from: region,
            mipmapLevel: 0
        )

        // Convert RGBA to BGRA if needed (most VLMs expect BGRA or RGB)
        convertRGBAtoBGRA(baseAddress: baseAddress, width: width, height: height, bytesPerRow: bytesPerRow)

        return buffer
    }

    /// Create a staging texture for GPU -> CPU transfer
    private static func createStagingTexture(from source: MTLTexture, device: MTLDevice) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: source.pixelFormat,
            width: source.width,
            height: source.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared // CPU accessible

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw TextureConverterError.stagingTextureCreationFailed
        }

        return texture
    }

    /// Convert RGBA to BGRA in place
    private static func convertRGBAtoBGRA(baseAddress: UnsafeMutableRawPointer, width: Int, height: Int, bytesPerRow: Int) {
        let pixels = baseAddress.assumingMemoryBound(to: UInt8.self)

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                // Swap R and B
                let r = pixels[offset]
                let b = pixels[offset + 2]
                pixels[offset] = b
                pixels[offset + 2] = r
            }
        }
    }

    /// Convert CVPixelBuffer to UIImage for debugging/display
    static func pixelBufferToImage(_ pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()

        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    /// Save pixel buffer to app documents (no permissions needed)
    static func saveToPhotos(_ pixelBuffer: CVPixelBuffer) async throws {
        vlmLog("saveToDocuments called", category: "Save")

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        vlmLog("Pixel buffer size: \(width)x\(height)", category: "Save")

        vlmLog("Converting to UIImage...", category: "Save")
        guard let image = pixelBufferToImage(pixelBuffer) else {
            vlmError("Failed to convert pixel buffer to UIImage", category: "Save")
            throw TextureConverterError.imageConversionFailed
        }

        vlmLog("Image created: \(image.size.width)x\(image.size.height)", category: "Save")

        // Save to app documents directory instead of Photos (no permissions needed)
        guard let data = image.pngData() else {
            vlmError("Failed to create PNG data", category: "Save")
            throw TextureConverterError.imageConversionFailed
        }

        let filename = "vlm_frame_\(Int(Date().timeIntervalSince1970)).png"
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let filePath = documentsPath.appendingPathComponent(filename)

        vlmLog("Saving to: \(filePath.path)", category: "Save")

        do {
            try data.write(to: filePath)
            vlmLog("Frame saved successfully: \(filename)", category: "Save")

            // Also save the path to shared storage for easy access
            await DebugFrameStorage.shared.addFrame(path: filePath)
        } catch {
            vlmError("Failed to write file: \(error.localizedDescription)", category: "Save")
            throw error
        }
    }
}

// MARK: - Debug Frame Storage

/// Stores paths to saved debug frames for viewing
@MainActor
class DebugFrameStorage: ObservableObject {
    static let shared = DebugFrameStorage()

    @Published var savedFrames: [URL] = []

    private init() {
        loadExistingFrames()
    }

    func addFrame(path: URL) {
        savedFrames.insert(path, at: 0)
        // Keep only last 10 frames
        if savedFrames.count > 10 {
            // Delete old file
            let old = savedFrames.removeLast()
            try? FileManager.default.removeItem(at: old)
        }
        vlmLog("Saved frames count: \(savedFrames.count)", category: "Save")
    }

    func loadExistingFrames() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        do {
            let files = try FileManager.default.contentsOfDirectory(at: documentsPath, includingPropertiesForKeys: nil)
            savedFrames = files.filter { $0.lastPathComponent.hasPrefix("vlm_frame_") }.sorted { $0.lastPathComponent > $1.lastPathComponent }
            vlmLog("Loaded \(savedFrames.count) existing frames", category: "Save")
        } catch {
            vlmLog("No existing frames found", category: "Save")
        }
    }

    func clearAll() {
        for path in savedFrames {
            try? FileManager.default.removeItem(at: path)
        }
        savedFrames.removeAll()
        vlmLog("Cleared all saved frames", category: "Save")
    }

    /// Get pixel buffer dimensions
    static func dimensions(of pixelBuffer: CVPixelBuffer) -> (width: Int, height: Int) {
        return (
            CVPixelBufferGetWidth(pixelBuffer),
            CVPixelBufferGetHeight(pixelBuffer)
        )
    }
}

enum TextureConverterError: LocalizedError {
    case pixelBufferCreationFailed
    case pixelBufferLockFailed
    case commandCreationFailed
    case stagingTextureCreationFailed
    case imageConversionFailed

    var errorDescription: String? {
        switch self {
        case .pixelBufferCreationFailed:
            return "Failed to create CVPixelBuffer"
        case .pixelBufferLockFailed:
            return "Failed to lock CVPixelBuffer"
        case .commandCreationFailed:
            return "Failed to create Metal command buffer"
        case .stagingTextureCreationFailed:
            return "Failed to create staging texture"
        case .imageConversionFailed:
            return "Failed to convert to UIImage"
        }
    }
}

// MARK: - Debug Frame Viewer

/// View for displaying saved debug frames
struct DebugFrameViewer: View {
    @ObservedObject var storage = DebugFrameStorage.shared
    @State private var selectedFrame: URL?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Saved Frames (\(storage.savedFrames.count))")
                    .font(.headline)
                Spacer()
                Button("Refresh") {
                    storage.loadExistingFrames()
                }
                .buttonStyle(.bordered)
                Button("Clear All") {
                    storage.clearAll()
                    selectedFrame = nil
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            if storage.savedFrames.isEmpty {
                VStack {
                    Spacer()
                    Text("No frames saved yet")
                        .foregroundStyle(.secondary)
                    Text("Tap 'Save Frame to Photos' to capture")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            } else {
                VStack(spacing: 0) {
                    // Selected frame preview (large, at top)
                    if let selected = selectedFrame {
                        FramePreview(url: selected)
                            .frame(maxHeight: .infinity)
                        Divider()
                    }

                    // Thumbnails list (bottom)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(storage.savedFrames, id: \.self) { url in
                                FrameThumbnail(url: url, isSelected: selectedFrame == url) {
                                    selectedFrame = url
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(height: 80)
                }
            }
        }
        .background(.ultraThinMaterial)
    }
}

/// Thumbnail view for a saved frame
struct FrameThumbnail: View {
    let url: URL
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                if let image = loadImage() {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.gray.opacity(0.3))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        )
                }

                Text(timestamp)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func loadImage() -> UIImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    private var timestamp: String {
        // Extract timestamp from filename "vlm_frame_1234567890.png"
        let filename = url.deletingPathExtension().lastPathComponent
        if let timestampStr = filename.split(separator: "_").last,
           let timestamp = Double(timestampStr) {
            let date = Date(timeIntervalSince1970: timestamp)
            return date.formatted(date: .omitted, time: .shortened)
        }
        return url.lastPathComponent
    }
}

/// Full preview of a selected frame
struct FramePreview: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 8) {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Text("\(Int(img.size.width))x\(Int(img.size.height))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .padding(8)
        .onAppear {
            loadImage()
        }
        .onChange(of: url) {
            loadImage()
        }
    }

    private func loadImage() {
        DispatchQueue.global(qos: .userInitiated).async {
            if let data = try? Data(contentsOf: url),
               let loadedImage = UIImage(data: data) {
                DispatchQueue.main.async {
                    self.image = loadedImage
                }
            }
        }
    }
}

// MARK: - Frame Viewer Window (Separate Window)

/// Standalone window for viewing captured frames at full size
struct FrameViewerWindow: View {
    @ObservedObject var storage = DebugFrameStorage.shared
    @State private var selectedFrame: URL?
    @State private var zoomScale: CGFloat = 1.0

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                // Frame list (left)
                List(storage.savedFrames, id: \.self, selection: $selectedFrame) { url in
                    HStack {
                        if let img = loadThumbnail(url) {
                            Image(uiImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 50, height: 50)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        VStack(alignment: .leading) {
                            Text(formatTimestamp(url))
                                .font(.caption)
                            Text(url.lastPathComponent)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: 220)

                Divider()

                // Large preview (right) - expanded width
                VStack {
                    if let selected = selectedFrame {
                        LargeFramePreview(url: selected, zoomScale: $zoomScale)
                    } else {
                        ContentUnavailableView(
                            "No Frame Selected",
                            systemImage: "photo",
                            description: Text("Select a frame from the list or save a new one")
                        )
                    }
                }
                .frame(minWidth: 500, maxWidth: .infinity)
            }
            .navigationTitle("VLM Frame Viewer")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh") {
                        storage.loadExistingFrames()
                    }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Clear All", role: .destructive) {
                        storage.clearAll()
                        selectedFrame = nil
                    }
                }
            }
        }
        .onAppear {
            storage.loadExistingFrames()
            // Auto-select first frame
            if selectedFrame == nil, let first = storage.savedFrames.first {
                selectedFrame = first
            }
        }
    }

    private func loadThumbnail(_ url: URL) -> UIImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    private func formatTimestamp(_ url: URL) -> String {
        let filename = url.deletingPathExtension().lastPathComponent
        if let timestampStr = filename.split(separator: "_").last,
           let timestamp = Double(timestampStr) {
            let date = Date(timeIntervalSince1970: timestamp)
            return date.formatted(date: .abbreviated, time: .standard)
        }
        return "Unknown"
    }
}

/// Large zoomable frame preview
struct LargeFramePreview: View {
    let url: URL
    @Binding var zoomScale: CGFloat
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 12) {
            if let img = image {
                ScrollView([.horizontal, .vertical]) {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(zoomScale)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Info bar
                HStack {
                    Text("\(Int(img.size.width)) x \(Int(img.size.height))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    // Zoom controls
                    Button(action: { zoomScale = max(0.5, zoomScale - 0.25) }) {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    Text("\(Int(zoomScale * 100))%")
                        .font(.caption)
                        .frame(width: 50)
                    Button(action: { zoomScale = min(3.0, zoomScale + 0.25) }) {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    Button(action: { zoomScale = 1.0 }) {
                        Text("Reset")
                            .font(.caption)
                    }
                }
                .padding(.horizontal)
            } else {
                ProgressView("Loading...")
            }
        }
        .padding()
        .onAppear { loadImage() }
        .onChange(of: url) { loadImage() }
    }

    private func loadImage() {
        image = nil
        DispatchQueue.global(qos: .userInitiated).async {
            if let data = try? Data(contentsOf: url),
               let loadedImage = UIImage(data: data) {
                DispatchQueue.main.async {
                    self.image = loadedImage
                }
            }
        }
    }
}
