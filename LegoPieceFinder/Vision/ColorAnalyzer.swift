import UIKit
import CoreImage

enum ColorAnalyzer {

    private static let ciContext = CIContext()

    /// Extracts the dominant (average) color from a CGImage region as CIELAB.
    static func dominantColor(of cgImage: CGImage) -> (lab: CIELABColor, uiColor: UIColor) {
        let ciImage = CIImage(cgImage: cgImage)
        let extent = ciImage.extent

        // Use CIAreaAverage to get the single average color
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ciImage,
            kCIInputExtentKey: CIVector(
                x: extent.origin.x,
                y: extent.origin.y,
                z: extent.size.width,
                w: extent.size.height
            )
        ]),
        let output = filter.outputImage else {
            let fallback = UIColor.gray
            return (CIELABColor.from(rgb: fallback), fallback)
        }

        // Render the 1×1 pixel
        var pixel = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        let uiColor = UIColor(
            red: CGFloat(pixel[0]) / 255.0,
            green: CGFloat(pixel[1]) / 255.0,
            blue: CGFloat(pixel[2]) / 255.0,
            alpha: 1.0
        )

        return (CIELABColor.from(rgb: uiColor), uiColor)
    }

    /// Extracts the dominant color from a specific normalized region of the image.
    static func dominantColor(
        of cgImage: CGImage,
        inNormalizedRect rect: CGRect
    ) -> (lab: CIELABColor, uiColor: UIColor)? {
        guard let cropped = cgImage.cropping(toNormalizedRect: rect) else {
            return nil
        }
        return dominantColor(of: cropped)
    }
}
