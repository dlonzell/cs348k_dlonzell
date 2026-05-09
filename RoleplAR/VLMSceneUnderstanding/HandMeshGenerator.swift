import RealityKit
import simd
import UIKit

/// Generates visible mesh entities from hand tracking skeleton data
/// Used for creating hand representations in the offscreen render for VLM analysis
class HandMeshGenerator {

    /// Settings for hand mesh generation
    struct Settings {
        var jointRadius: Float = 0.008       // 8mm spheres (visible for VLM)
        var connectionRadius: Float = 0.004  // 4mm cylinder connections
        var leftHandColor: UIColor = .systemBlue
        var rightHandColor: UIColor = .systemGreen
    }

    private let settings: Settings

    /// Joint connections to draw cylinders between
    private let connections: [(String, String)] = [
        // Thumb
        ("thumbTip", "thumbIntermediateTip"),
        ("thumbIntermediateTip", "thumbIntermediateBase"),
        ("thumbIntermediateBase", "thumbKnuckle"),
        ("thumbKnuckle", "wrist"),

        // Index
        ("indexFingerTip", "indexFingerIntermediateTip"),
        ("indexFingerIntermediateTip", "indexFingerIntermediateBase"),
        ("indexFingerIntermediateBase", "indexFingerKnuckle"),
        ("indexFingerKnuckle", "indexFingerMetacarpal"),

        // Middle
        ("middleFingerTip", "middleFingerIntermediateTip"),
        ("middleFingerIntermediateTip", "middleFingerIntermediateBase"),
        ("middleFingerIntermediateBase", "middleFingerKnuckle"),
        ("middleFingerKnuckle", "middleFingerMetacarpal"),

        // Ring
        ("ringFingerTip", "ringFingerIntermediateTip"),
        ("ringFingerIntermediateTip", "ringFingerIntermediateBase"),
        ("ringFingerIntermediateBase", "ringFingerKnuckle"),
        ("ringFingerKnuckle", "ringFingerMetacarpal"),

        // Little
        ("littleFingerTip", "littleFingerIntermediateTip"),
        ("littleFingerIntermediateTip", "littleFingerIntermediateBase"),
        ("littleFingerIntermediateBase", "littleFingerKnuckle"),
        ("littleFingerKnuckle", "littleFingerMetacarpal"),

        // Palm/wrist connections
        ("wrist", "indexFingerMetacarpal"),
        ("wrist", "middleFingerMetacarpal"),
        ("wrist", "ringFingerMetacarpal"),
        ("wrist", "littleFingerMetacarpal"),
    ]

    init(settings: Settings = Settings()) {
        self.settings = settings
    }

    /// Generate all hand mesh entities for a single hand
    func generateHandEntities(
        joints: [String: simd_float4x4],
        isLeft: Bool
    ) -> [Entity] {
        var entities: [Entity] = []

        let color = isLeft ? settings.leftHandColor : settings.rightHandColor
        var material = SimpleMaterial()
        material.color = .init(tint: color)

        // Create spheres at each joint
        for (jointName, transform) in joints {
            let sphereMesh = MeshResource.generateSphere(radius: settings.jointRadius)
            let sphere = ModelEntity(mesh: sphereMesh, materials: [material])
            sphere.transform = Transform(matrix: transform)
            sphere.name = "\(isLeft ? "left" : "right")_joint_\(jointName)"
            entities.append(sphere)
        }

        // Create cylinders connecting joints
        for (startJoint, endJoint) in connections {
            guard let startTransform = joints[startJoint],
                  let endTransform = joints[endJoint] else {
                continue
            }

            let startPos = simd_float3(startTransform.columns.3.x,
                                        startTransform.columns.3.y,
                                        startTransform.columns.3.z)
            let endPos = simd_float3(endTransform.columns.3.x,
                                      endTransform.columns.3.y,
                                      endTransform.columns.3.z)

            if let cylinder = createCylinder(from: startPos, to: endPos, material: material) {
                cylinder.name = "\(isLeft ? "left" : "right")_conn_\(startJoint)_\(endJoint)"
                entities.append(cylinder)
            }
        }

        return entities
    }

    /// Create a cylinder between two points
    private func createCylinder(
        from start: simd_float3,
        to end: simd_float3,
        material: SimpleMaterial
    ) -> ModelEntity? {
        let distance = simd_distance(start, end)
        guard distance > 0.001 else { return nil }

        let cylinderMesh = MeshResource.generateCylinder(
            height: distance,
            radius: settings.connectionRadius
        )
        let cylinder = ModelEntity(mesh: cylinderMesh, materials: [material])

        // Position at midpoint
        let midpoint = (start + end) / 2
        cylinder.position = midpoint

        // Rotate to align with the connection direction
        let direction = normalize(end - start)
        let up = simd_float3(0, 1, 0)

        let rotationAxis = cross(up, direction)
        let rotationAngle = acos(simd_clamp(dot(up, direction), -1, 1))

        if simd_length(rotationAxis) > 0.001 {
            cylinder.orientation = simd_quatf(angle: rotationAngle, axis: normalize(rotationAxis))
        }

        return cylinder
    }
}
