import Vision
import CoreImage

enum ContourDetector {

    /// Detects contours in the given image.
    /// Returns top-level contours sorted by area (largest first), up to `maxCount`.
    static func detect(
        in cgImage: CGImage,
        contrastAdjustment: Float = 2.0,
        maxCount: Int = 20
    ) throws -> [VNContour] {
        let request = VNDetectContoursRequest()
        request.contrastAdjustment = contrastAdjustment
        request.detectsDarkOnLight = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        guard let observation = request.results?.first else {
            return []
        }

        let topLevel = (0..<observation.contourCount).compactMap { index in
            try? observation.contour(at: index)
        }

        // Sort by bounding box area (largest first) and take top maxCount
        let sorted = topLevel.sorted { a, b in
            let areaA = a.boundingBox.width * a.boundingBox.height
            let areaB = b.boundingBox.width * b.boundingBox.height
            return areaA > areaB
        }

        return Array(sorted.prefix(maxCount))
    }

    /// Downscales the image to fit within the given max dimension, preserving aspect ratio.
    static func downsample(_ cgImage: CGImage, maxDimension: Int = 512) -> CGImage {
        let w = cgImage.width
        let h = cgImage.height
        guard max(w, h) > maxDimension else { return cgImage }

        let scale: CGFloat
        if w > h {
            scale = CGFloat(maxDimension) / CGFloat(w)
        } else {
            scale = CGFloat(maxDimension) / CGFloat(h)
        }

        let newW = Int(CGFloat(w) * scale)
        let newH = Int(CGFloat(h) * scale)

        guard let context = CGContext(
            data: nil,
            width: newW,
            height: newH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return cgImage
        }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        return context.makeImage() ?? cgImage
    }
}
