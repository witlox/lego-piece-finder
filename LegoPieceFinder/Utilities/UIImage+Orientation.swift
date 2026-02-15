import UIKit

extension UIImage {
    /// Returns a new UIImage with pixels rotated to match the orientation metadata.
    /// After this, `.cgImage` returns correctly oriented pixels regardless of
    /// how the device was held when the photo was taken.
    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0  // match source pixels, not screen scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
