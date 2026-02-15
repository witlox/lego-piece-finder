import CoreGraphics

extension CGImage {
    /// Crops using a Vision-normalized rect (origin at bottom-left, 0…1 range).
    /// Clamps to image bounds and returns nil for degenerate rects.
    func cropping(toNormalizedRect rect: CGRect) -> CGImage? {
        let w = CGFloat(width)
        let h = CGFloat(height)

        // Clamp the normalized rect to 0…1 to handle contours at image edges
        let clampedX = max(0, min(rect.origin.x, 1))
        let clampedY = max(0, min(rect.origin.y, 1))
        let clampedW = max(0, min(rect.width, 1 - clampedX))
        let clampedH = max(0, min(rect.height, 1 - clampedY))

        let pixelRect = CGRect(
            x: (clampedX * w).rounded(.down),
            y: ((1.0 - clampedY - clampedH) * h).rounded(.down),
            width: (clampedW * w).rounded(.down),
            height: (clampedH * h).rounded(.down)
        )

        // CGImage.cropping(to:) crashes on zero-size or out-of-bounds rects
        guard pixelRect.width >= 1, pixelRect.height >= 1,
              pixelRect.maxX <= w, pixelRect.maxY <= h else {
            return nil
        }

        return self.cropping(to: pixelRect)
    }
}
