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

    /// Computes average color from only the opaque pixels (alpha > 0) of an RGBA image.
    /// Used for contour-masked reference images where the background is transparent.
    static func averageOpaqueColor(of cgImage: CGImage) -> (lab: CIELABColor, uiColor: UIColor)? {
        let w = cgImage.width
        let h = cgImage.height
        guard w > 0, h > 0 else { return nil }

        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        guard let data = ctx.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: w * h * 4)

        var totalR: Double = 0
        var totalG: Double = 0
        var totalB: Double = 0
        var count: Double = 0

        for i in 0 ..< (w * h) {
            let offset = i * 4
            let a = pixels[offset + 3]
            guard a > 0 else { continue }
            // Un-premultiply alpha
            let af = Double(a) / 255.0
            totalR += Double(pixels[offset]) / af
            totalG += Double(pixels[offset + 1]) / af
            totalB += Double(pixels[offset + 2]) / af
            count += 1
        }

        guard count > 0 else { return nil }

        let uiColor = UIColor(
            red: CGFloat(totalR / count / 255.0),
            green: CGFloat(totalG / count / 255.0),
            blue: CGFloat(totalB / count / 255.0),
            alpha: 1.0
        )

        return (CIELABColor.from(rgb: uiColor), uiColor)
    }
}
