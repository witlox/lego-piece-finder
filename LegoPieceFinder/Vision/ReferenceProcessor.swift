import UIKit
import Vision

enum ReferenceProcessor {

    enum ProcessingError: Error, LocalizedError {
        case noContoursFound
        case featurePrintFailed
        case croppingFailed

        var errorDescription: String? {
            switch self {
            case .noContoursFound: return "No piece contour found in the image."
            case .featurePrintFailed: return "Could not extract feature print."
            case .croppingFailed: return "Could not crop piece from image."
            }
        }
    }

    /// Processes a manual illustration photo and extracts a full ReferenceDescriptor.
    /// The illustration should contain a single LEGO piece on a light/white background.
    static func process(image: UIImage) throws -> ReferenceDescriptor {
        guard let cgImage = image.cgImage else {
            throw ProcessingError.croppingFailed
        }

        // 1. Detect contours — manual illustrations are high contrast
        let contours = try ContourDetector.detect(
            in: cgImage,
            contrastAdjustment: 3.0,
            maxCount: 5
        )

        guard let largestContour = contours.first else {
            throw ProcessingError.noContoursFound
        }

        // 2. Get bounding box and crop the piece region
        let bbox = largestContour.boundingBox
        guard let croppedCGImage = cgImage.cropping(toNormalizedRect: bbox) else {
            throw ProcessingError.croppingFailed
        }

        // 3. Compute Hu moments from the contour (primary shape signal)
        let huMoments = ShapeDescriptor.huMoments(from: largestContour)

        // 4. Compute aspect ratio
        let aspectRatio = ShapeDescriptor.aspectRatio(of: largestContour)

        // 5. Extract feature print from the cropped piece (secondary signal)
        let featurePrint: VNFeaturePrintObservation
        do {
            featurePrint = try FeaturePrintExtractor.extract(from: croppedCGImage)
        } catch {
            throw ProcessingError.featurePrintFailed
        }

        // 6. Extract dominant color from the piece region
        let (lab, uiColor) = ColorAnalyzer.dominantColor(of: croppedCGImage)

        // 7. Create reference image for preview
        let referenceImage = UIImage(cgImage: croppedCGImage)

        return ReferenceDescriptor(
            huMoments: huMoments,
            aspectRatio: aspectRatio,
            featurePrint: featurePrint,
            dominantColor: lab,
            dominantUIColor: uiColor,
            referenceImage: referenceImage
        )
    }
}
