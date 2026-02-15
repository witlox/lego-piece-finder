import RealityKit
import UIKit

enum HighlightEntity {

    /// Creates a semi-transparent highlight plane for a matched piece.
    /// Uses the candidate's display color with alpha based on match type.
    static func make(
        candidate: PieceCandidate,
        width: Float,
        height: Float
    ) -> ModelEntity {
        let mesh = MeshResource.generatePlane(width: width, depth: height)
        let alpha: CGFloat = candidate.matchType == .shapeAndColor ? 0.55 : 0.35
        let color = candidate.displayColor.withAlphaComponent(alpha)
        var material = UnlitMaterial()
        material.color = .init(tint: color)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        return entity
    }
}
