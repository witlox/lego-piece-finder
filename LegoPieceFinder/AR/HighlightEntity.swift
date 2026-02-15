import RealityKit
import UIKit

enum HighlightEntity {

    /// Orange color for shape-only matches
    static let shapeOnlyColor = UIColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 0.45)

    /// Green color for shape+color matches
    static let shapeAndColorColor = UIColor(red: 0.0, green: 0.85, blue: 0.2, alpha: 0.55)

    /// Creates a semi-transparent highlight plane for a matched piece.
    static func make(
        matchType: MatchType,
        width: Float,
        height: Float
    ) -> ModelEntity {
        let mesh = MeshResource.generatePlane(width: width, depth: height)
        let color: UIColor = matchType == .shapeAndColor ? shapeAndColorColor : shapeOnlyColor
        var material = UnlitMaterial()
        material.color = .init(tint: color)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        return entity
    }
}
