import Vision

extension VNContour {
    /// Returns the bounding box of the contour in Vision-normalized coordinates (0…1).
    var boundingBox: CGRect {
        let points = normalizedPoints
        guard !points.isEmpty else { return .zero }

        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude

        for point in points {
            let x = CGFloat(point.x)
            let y = CGFloat(point.y)
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
