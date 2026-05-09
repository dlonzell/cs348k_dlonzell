import RealityKit
import Metal
import ARKit
import UIKit

/// Renders the scene offscreen for VLM analysis
/// Uses RealityRenderer to capture scene + hand meshes without passthrough
@MainActor
class OffscreenRenderer {

    // MARK: - Properties

    /// The RealityKit renderer for offscreen rendering
    private var renderer: RealityRenderer?

    /// Root entity containing all scene content
    private let rootEntity = Entity()

    /// Camera entity for the render
    private var camera: PerspectiveCamera?

    /// Metal device for texture creation
    private let device: MTLDevice

    /// Output texture dimensions
    let textureWidth: Int
    let textureHeight: Int

    /// The color texture we render to
    private var colorTexture: MTLTexture?

    /// Depth texture for proper occlusion
    private var depthTexture: MTLTexture?

    /// Hand mesh generator for creating visible hand entities
    private let handMeshGenerator = HandMeshGenerator()

    /// Current hand mesh entities (cleared and recreated each frame)
    private var handEntities: [Entity] = []

    /// Scene object entities (table, menu, etc.)
    private var sceneObjects: [Entity] = []

    /// Lighting entities
    private var lightEntities: [Entity] = []

    // MARK: - Initialization

    init(width: Int = 512, height: Int = 512) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw OffscreenRendererError.noMetalDevice
        }

        self.device = device
        self.textureWidth = width
        self.textureHeight = height

        try setupRenderer()
        setupTextures()
        setupCamera()
        setupLighting()
    }

    // MARK: - Setup

    private func setupRenderer() throws {
        renderer = try RealityRenderer()
        renderer?.entities.append(rootEntity)
    }

    private func setupTextures() {
        // Color texture
        let colorDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, // Use bgra8Unorm for better compatibility
            width: textureWidth,
            height: textureHeight,
            mipmapped: false
        )
        colorDesc.usage = [.renderTarget, .shaderRead]
        #if targetEnvironment(simulator)
        colorDesc.storageMode = .shared // Simulator requires shared storage
        #else
        colorDesc.storageMode = .private
        #endif
        colorTexture = device.makeTexture(descriptor: colorDesc)

        // Depth texture
        let depthDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: textureWidth,
            height: textureHeight,
            mipmapped: false
        )
        depthDesc.usage = [.renderTarget, .shaderRead]
        #if targetEnvironment(simulator)
        depthDesc.storageMode = .shared // Simulator requires shared storage
        #else
        depthDesc.storageMode = .private
        #endif
        depthTexture = device.makeTexture(descriptor: depthDesc)
    }

    private func setupCamera() {
        let perspectiveCamera = PerspectiveCamera()
        perspectiveCamera.camera.fieldOfViewInDegrees = 60
        perspectiveCamera.camera.near = 0.01
        perspectiveCamera.camera.far = 100

        // Default position - look at table area (tableY=0.55, tableZ=-0.85)
        perspectiveCamera.position = [0, 1.5, 0] // Eye level, slightly lower
        perspectiveCamera.look(at: [0, 0.55, -0.85], from: perspectiveCamera.position, relativeTo: nil)

        rootEntity.addChild(perspectiveCamera)
        camera = perspectiveCamera
        renderer?.activeCamera = perspectiveCamera
    }

    private func setupLighting() {
        // Add lighting if available (visionOS 2.0+)
        if #available(visionOS 2.0, *) {
            setupAdvancedLighting()
        }

        // Ground plane for spatial reference (works on all versions)
        // Use UnlitMaterial so it's visible without lighting (required for visionOS 1.x)
        let groundMesh = MeshResource.generatePlane(width: 4, depth: 4)
        var groundMaterial = UnlitMaterial()
        groundMaterial.color = .init(tint: UIColor.gray.withAlphaComponent(0.5))
        let ground = ModelEntity(mesh: groundMesh, materials: [groundMaterial])
        ground.position = [0, 0, -0.85] // Match tableZ position
        rootEntity.addChild(ground)
    }

    @available(visionOS 2.0, *)
    private func setupAdvancedLighting() {
        // Main directional light - point at table area (tableY=0.55, tableZ=-0.85)
        let directionalLight = DirectionalLight()
        directionalLight.light.color = .white
        directionalLight.light.intensity = 2000
        directionalLight.look(at: [0, 0.55, -0.85], from: [1, 3, 0], relativeTo: nil)
        directionalLight.shadow = DirectionalLightComponent.Shadow(
            maximumDistance: 5,
            depthBias: 0.001
        )
        rootEntity.addChild(directionalLight)
        lightEntities.append(directionalLight)

        // Fill light - closer to scene
        let fillLight = PointLight()
        fillLight.light.color = .white
        fillLight.light.intensity = 1500
        fillLight.light.attenuationRadius = 8
        fillLight.position = [-0.5, 1.5, -0.5]
        rootEntity.addChild(fillLight)
        lightEntities.append(fillLight)
    }

    // MARK: - Scene Management

    /// Add a scene object entity
    func addSceneObject(_ entity: Entity) {
        rootEntity.addChild(entity)
        sceneObjects.append(entity)
    }

    /// Remove all scene objects
    func clearSceneObjects() {
        for entity in sceneObjects {
            entity.removeFromParent()
        }
        sceneObjects.removeAll()
    }

    /// Update the position of a scene object by name
    func updateSceneObjectPosition(name: String, position: SIMD3<Float>) {
        if let entity = sceneObjects.first(where: { $0.name == name }) {
            entity.position = position
        }
        // Note: if entity not found, it silently fails - check sceneObjects array if issues
    }

    /// Update camera position based on head tracking
    func updateCamera(transform: simd_float4x4) {
        camera?.transform = Transform(matrix: transform)
    }

    /// Update camera to look at a specific point
    func updateCamera(position: SIMD3<Float>, lookAt: SIMD3<Float>) {
        camera?.position = position
        camera?.look(at: lookAt, from: position, relativeTo: nil)
    }

    // MARK: - Hand Mesh Management

    /// Update hand meshes for rendering
    func updateHandMeshes(leftJoints: [String: simd_float4x4], rightJoints: [String: simd_float4x4]) {
        // Remove old hand entities
        for entity in handEntities {
            entity.removeFromParent()
        }
        handEntities.removeAll()

        // Generate new hand entities
        if !leftJoints.isEmpty {
            let leftEntities = handMeshGenerator.generateHandEntities(joints: leftJoints, isLeft: true)
            for entity in leftEntities {
                rootEntity.addChild(entity)
                handEntities.append(entity)
            }
        }

        if !rightJoints.isEmpty {
            let rightEntities = handMeshGenerator.generateHandEntities(joints: rightJoints, isLeft: false)
            for entity in rightEntities {
                rootEntity.addChild(entity)
                handEntities.append(entity)
            }
        }
    }

    // MARK: - Rendering

    /// Render the current scene to texture
    /// - Returns: The rendered color texture
    func render() async throws -> MTLTexture? {
        #if targetEnvironment(simulator)
        // RealityRenderer.updateAndRender causes SIGABRT on visionOS simulator
        // Return nil to signal that rendering is not available
        print("OffscreenRenderer: Skipping render on simulator (not supported)")
        return nil
        #else
        guard let renderer = renderer,
              let colorTexture = colorTexture else {
            throw OffscreenRendererError.notInitialized
        }

        // Create camera output descriptor
        let descriptor = RealityRenderer.CameraOutput.Descriptor.singleProjection(
            colorTexture: colorTexture
        )

        let cameraOutput: RealityRenderer.CameraOutput
        do {
            cameraOutput = try RealityRenderer.CameraOutput(descriptor)
        } catch {
            print("OffscreenRenderer: Failed to create CameraOutput: \(error)")
            throw OffscreenRendererError.renderFailed
        }

        // Render the scene
        do {
            try renderer.updateAndRender(
                deltaTime: 1.0 / 30.0, // 30 fps
                cameraOutput: cameraOutput,
                whenScheduled: { _ in },
                onComplete: { _ in }
            )
        } catch {
            print("OffscreenRenderer: updateAndRender failed: \(error)")
            throw OffscreenRendererError.renderFailed
        }

        return colorTexture
        #endif
    }

    /// Render and convert to CVPixelBuffer for VLM input
    func renderToPixelBuffer() async throws -> CVPixelBuffer? {
        guard let texture = try await render() else {
            return nil
        }

        return try TextureConverter.convert(texture: texture, device: device)
    }

    // MARK: - Cleanup

    func cleanup() {
        clearSceneObjects()
        for entity in handEntities {
            entity.removeFromParent()
        }
        handEntities.removeAll()

        for entity in lightEntities {
            entity.removeFromParent()
        }
        lightEntities.removeAll()

        camera?.removeFromParent()
        renderer = nil
    }
}

// MARK: - Errors

enum OffscreenRendererError: LocalizedError {
    case noMetalDevice
    case notInitialized
    case renderFailed
    case textureCreationFailed

    var errorDescription: String? {
        switch self {
        case .noMetalDevice:
            return "No Metal device available"
        case .notInitialized:
            return "Renderer not initialized"
        case .renderFailed:
            return "Failed to render scene"
        case .textureCreationFailed:
            return "Failed to create texture"
        }
    }
}
