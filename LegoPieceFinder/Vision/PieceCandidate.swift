import Foundation
import CoreGraphics
import UIKit

enum MatchType: Sendable {
    case shapeOnly
    case shapeAndColor
}

struct PieceCandidate: @unchecked Sendable {
    let boundingBox: CGRect
    let matchType: MatchType
    let shapeScore: Double
    let colorDistance: Double
    let referenceID: UUID
    let displayColor: UIColor
}
