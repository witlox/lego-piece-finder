import Vision
import CoreGraphics

enum FeaturePrintExtractor {

    /// Generates a VNFeaturePrintObservation for the given image.
    static func extract(from cgImage: CGImage) throws -> VNFeaturePrintObservation {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        guard let result = request.results?.first else {
            throw FeaturePrintError.noResult
        }
        return result
    }

    /// Computes normalized distance between two feature prints.
    /// Returns a value in 0…1 range (lower = more similar).
    static func normalizedDistance(
        _ a: VNFeaturePrintObservation,
        _ b: VNFeaturePrintObservation
    ) -> Float {
        var distance: Float = 0
        try? a.computeDistance(&distance, to: b)
        // Feature print distances typically range 0–70+. Normalize to 0–1.
        return min(distance / 70.0, 1.0)
    }

    enum FeaturePrintError: Error {
        case noResult
    }
}
