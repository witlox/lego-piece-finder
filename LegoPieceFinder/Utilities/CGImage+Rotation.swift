import CoreGraphics

extension CGImage {
    /// Returns a new CGImage rotated by the given angle in radians.
    func rotated(by radians: CGFloat) -> CGImage? {
        let w = CGFloat(width)
        let h = CGFloat(height)

        // Compute bounding size of the rotated image
        let sin = abs(CoreGraphics.sin(radians))
        let cos = abs(CoreGraphics.cos(radians))
        let newW = Int(ceil(w * cos + h * sin))
        let newH = Int(ceil(w * sin + h * cos))

        guard let context = CGContext(
            data: nil,
            width: newW,
            height: newH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        // Move origin to center, rotate, then draw centered
        context.translateBy(x: CGFloat(newW) / 2, y: CGFloat(newH) / 2)
        context.rotate(by: radians)
        context.draw(self, in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))

        return context.makeImage()
    }
}
