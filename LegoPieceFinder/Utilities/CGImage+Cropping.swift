import CoreGraphics

extension CGImage {
    /// Crops using a Vision-normalized rect (origin at bottom-left, 0…1 range).
    func cropping(toNormalizedRect rect: CGRect) -> CGImage? {
        let w = CGFloat(width)
        let h = CGFloat(height)
        let pixelRect = CGRect(
            x: rect.origin.x * w,
            y: (1.0 - rect.origin.y - rect.height) * h,
            width: rect.width * w,
            height: rect.height * h
        )
        return self.cropping(to: pixelRect)
    }
}
