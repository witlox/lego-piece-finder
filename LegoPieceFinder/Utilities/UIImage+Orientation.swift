import UIKit

extension UIImage {
    /// Returns a new UIImage with pixels rotated to match the orientation metadata.
    /// After this, `.cgImage` returns correctly oriented pixels regardless of
    /// how the device was held when the photo was taken.
    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
