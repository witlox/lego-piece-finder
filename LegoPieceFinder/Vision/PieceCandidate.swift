import Foundation
import CoreGraphics

enum MatchType: Sendable {
    case shapeOnly
    case shapeAndColor
}

struct PieceCandidate: Sendable {
    let boundingBox: CGRect
    let matchType: MatchType
    let shapeScore: Double
    let colorDistance: Double
}
