import ARKit
import RealityKit

@MainActor
final class HighlightOverlayManager: ObservableObject {

    private let anchor = AnchorEntity()
    private weak var arView: ARView?

    /// Default distance from camera when no plane is detected.
    private let fallbackDistance: Float = 0.5

    func attach(to arView: ARView) {
        self.arView = arView
        arView.scene.addAnchor(anchor)
    }

    /// Removes all existing highlights and places new ones for the given candidates.
    func update(candidates: [PieceCandidate]) {
        // Remove all existing highlights
        anchor.children.removeAll()

        guard let arView = arView else { return }

        let viewWidth = Float(arView.bounds.width)
        let viewHeight = Float(arView.bounds.height)

        for candidate in candidates {
            // Convert Vision normalized rect to screen coordinates
            let bbox = candidate.boundingBox
            let screenCenter = CGPoint(
                x: CGFloat(bbox.midX) * CGFloat(viewWidth),
                y: (1 - CGFloat(bbox.midY)) * CGFloat(viewHeight)
            )

            // Raycast to find surface distance, or use fallback
            let distance: Float
            if let result = arView.raycast(
                from: screenCenter,
                allowing: .estimatedPlane,
                alignment: .horizontal
            ).first {
                let camPos = arView.cameraTransform.translation
                let hitPos = result.worldTransform.columns.3
                distance = simd_distance(
                    SIMD3(camPos.x, camPos.y, camPos.z),
                    SIMD3(hitPos.x, hitPos.y, hitPos.z)
                )
            } else {
                distance = fallbackDistance
            }

            // Estimate physical size from normalized bbox and distance
            // Approximate: at distance d, the FOV covers roughly d * tan(fov/2) * 2
            let hFov: Float = 1.0 // approximate horizontal field-of-view factor
            let physicalWidth = Float(bbox.width) * distance * hFov
            let physicalHeight = Float(bbox.height) * distance * hFov

            // Create highlight entity
            let highlight = HighlightEntity.make(
                candidate: candidate,
                width: max(physicalWidth, 0.01),
                height: max(physicalHeight, 0.01)
            )

            // Position via raycast or projection
            if let result = arView.raycast(
                from: screenCenter,
                allowing: .estimatedPlane,
                alignment: .horizontal
            ).first {
                let worldPos = result.worldTransform.columns.3
                highlight.position = SIMD3(worldPos.x, worldPos.y + 0.002, worldPos.z)
            } else {
                // Fallback: place in front of camera
                let camTransform = arView.cameraTransform
                let forward = camTransform.matrix.columns.2
                let camPos = camTransform.translation
                highlight.position = SIMD3(
                    camPos.x - forward.x * fallbackDistance,
                    camPos.y - forward.y * fallbackDistance,
                    camPos.z - forward.z * fallbackDistance
                )
            }

            anchor.addChild(highlight)
        }
    }

    func removeAll() {
        anchor.children.removeAll()
    }
}
