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

    // MARK: - Compactness (rotation-invariant)

    /// Computes perimeter of a contour by summing edge lengths between consecutive points.
    static func perimeter(of contour: VNContour) -> Double {
        let points = contour.normalizedPoints
        guard points.count >= 2 else { return 0 }
        var sum = 0.0
        for i in 0..<points.count {
            let a = points[i]
            let b = points[(i + 1) % points.count]
            let dx = Double(b.x - a.x)
            let dy = Double(b.y - a.y)
            sum += (dx * dx + dy * dy).squareRoot()
        }
        return sum
    }

    /// Computes area of a contour using the shoelace formula.
    static func area(of contour: VNContour) -> Double {
        let points = contour.normalizedPoints
        guard points.count >= 3 else { return 0 }
        var sum = 0.0
        for i in 0..<points.count {
            let a = points[i]
            let b = points[(i + 1) % points.count]
            sum += Double(a.x) * Double(b.y) - Double(b.x) * Double(a.y)
        }
        return abs(sum) / 2.0
    }

    /// Computes compactness (isoperimetric ratio): perimeter² / (4π · area).
    /// Always ≥ 1.0 (circle = 1.0). Fully rotation-invariant.
    static func compactness(of contour: VNContour) -> Double {
        let p = perimeter(of: contour)
        let a = area(of: contour)
        guard a > 0 else { return 1.0 }
        return (p * p) / (4.0 * .pi * a)
    }

    /// Similarity between two compactness values (1.0 = identical, 0.0 = very different).
    static func compactnessSimilarity(_ a: Double, _ b: Double) -> Double {
        let maxVal = max(a, b)
        let minVal = min(a, b)
        guard maxVal > 0 else { return 1.0 }
        return minVal / maxVal
    }
}
