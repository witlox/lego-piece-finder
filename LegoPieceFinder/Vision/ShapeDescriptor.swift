import Vision

enum ShapeDescriptor {

    /// Computes Hu moment invariants from a VNContour.
    static func huMoments(from contour: VNContour) -> [Double] {
        let points = contour.normalizedPoints
        let simdPoints = points.map { $0 }
        return HuMoments.compute(from: simdPoints)
    }

    /// Computes the aspect ratio (width / height) of the contour's bounding box.
    static func aspectRatio(of contour: VNContour) -> Double {
        let bbox = contour.boundingBox
        guard bbox.height > 0 else { return 1.0 }
        let ratio = Double(bbox.width / bbox.height)
        // Normalize so it's always >= 1 (wider dimension / narrower dimension)
        return ratio >= 1.0 ? ratio : 1.0 / ratio
    }

    /// Computes similarity between two aspect ratios (1.0 = identical, 0.0 = very different).
    static func aspectRatioSimilarity(_ a: Double, _ b: Double) -> Double {
        let maxRatio = max(a, b)
        let minRatio = min(a, b)
        guard maxRatio > 0 else { return 1.0 }
        return minRatio / maxRatio
    }

    /// Converts Hu moment distance to a 0…1 similarity (1.0 = identical).
    /// Uses an exponential decay based on typical Hu distance ranges.
    static func huMomentSimilarity(_ distance: Double) -> Double {
        // Hu moment log-scale distances: 0 = identical, ~5 = very different
        return exp(-0.5 * distance)
    }
}
