import CoreGraphics
import Vision

extension CGImage {

    /// Returns a new image with the area outside the contour made transparent.
    /// Used for preview images and color extraction.
    func maskedWithContour(_ contour: VNContour, bbox: CGRect) -> CGImage? {
        maskedWithContour(contour, bbox: bbox, backgroundColor: nil)
    }

    /// Returns a new image with the area outside the contour filled with a solid color.
    /// Pass white for feature print extraction (avoids alpha channel issues with Vision).
    /// Pass nil for transparent background.
    func maskedWithContour(
        _ contour: VNContour,
        bbox: CGRect,
        backgroundColor: CGColor?
    ) -> CGImage? {
        let w = self.width
        let h = self.height
        guard w >= 1, h >= 1 else { return nil }

        let hasAlpha = backgroundColor == nil
        let alphaInfo: CGImageAlphaInfo = hasAlpha ? .premultipliedLast : .noneSkipLast

        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: alphaInfo.rawValue
        ) else {
            return nil
        }

        // Fill background (transparent by default, or solid color)
        if let bg = backgroundColor {
            ctx.setFillColor(bg)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }

        // Build a path from contour points, clip, then draw the image
        guard let path = buildContourPath(contour, bbox: bbox, pixelWidth: w, pixelHeight: h) else {
            return nil
        }

        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.draw(self, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.restoreGState()

        // Trim contour edges: erase a thin strip along the boundary.
        // This removes border fragments and background artifacts that
        // the contour detection included at the piece edge.
        if hasAlpha {
            let trim = max(2, min(CGFloat(min(w, h)) * 0.015, 4))
            ctx.setBlendMode(.clear)
            ctx.setLineWidth(trim)
            ctx.addPath(path)
            ctx.strokePath()
        }

        return ctx.makeImage()
    }

    // MARK: - Private

    /// Transforms contour normalizedPoints from image-normalized space into
    /// crop-pixel space and returns a closed CGPath.
    ///
    /// Vision contour points are in 0…1 image-normalized coordinates (bottom-left origin).
    /// The bbox defines which sub-region of the full image was cropped. We map each point
    /// relative to the bbox into the pixel dimensions of the crop.
    private func buildContourPath(
        _ contour: VNContour,
        bbox: CGRect,
        pixelWidth: Int,
        pixelHeight: Int
    ) -> CGPath? {
        let points = contour.normalizedPoints
        guard points.count >= 3 else { return nil }

        let pw = CGFloat(pixelWidth)
        let ph = CGFloat(pixelHeight)

        let path = CGMutablePath()
        for (i, point) in points.enumerated() {
            // Map from full-image normalized coords to crop-local pixel coords
            let x = (CGFloat(point.x) - bbox.origin.x) / bbox.width * pw
            let y = (CGFloat(point.y) - bbox.origin.y) / bbox.height * ph
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()
        return path
    }
}
