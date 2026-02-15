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

    // MARK: - Rotation angles for feature print extraction

    private static let rotationAngles: [CGFloat] = [
        0,
        .pi / 2,
        .pi,
        3 * .pi / 2
    ]

    // MARK: - Public API

    /// Processes a photo of a LEGO manual callout box and extracts descriptors
    /// for all piece illustrations found.
    ///
    /// The user photographs just the piece-list callout box (the bordered area
    /// showing required pieces with "1x", "2x" quantities). This method:
    /// 1. Detects contours in the image
    /// 2. Filters to piece-sized contours with non-background color
    /// 3. Applies NMS to remove overlapping internal details
    /// 4. Extracts shape, color, and feature print descriptors for each piece
    static func processAll(image: UIImage) throws -> [ReferenceDescriptor] {
        guard let rawCGImage = image.cgImage else {
            throw ProcessingError.croppingFailed
        }

        // Downsample to limit memory — 2000px is plenty for callout box analysis.
        let cgImage = ContourDetector.downsample(rawCGImage, maxDimension: 2000)

        // Detect contours in the callout box photo
        let contours = try ContourDetector.detect(
            in: cgImage,
            contrastAdjustment: 3.0,
            maxCount: 15
        )

        guard !contours.isEmpty else {
            throw ProcessingError.noContoursFound
        }

        // Filter to piece-sized contours with dark/colored content (not background)
        var candidates: [VNContour] = []
        for contour in contours {
            let bbox = contour.boundingBox
            let area = bbox.width * bbox.height
            // Pieces in a callout box photo are typically 2-60% of the image
            guard area > 0.02, area < 0.60 else { continue }

            // Reject contours whose center is too light — these are background
            // regions, text labels, or quantity markers, not piece illustrations.
            if let crop = cgImage.cropping(toNormalizedRect: bbox) {
                let centerRect = CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
                if let color = ColorAnalyzer.dominantColor(
                    of: crop,
                    inNormalizedRect: centerRect
                ) {
                    guard color.lab.L < 82 else { continue }
                }
            }

            candidates.append(contour)
        }

        // Non-maximum suppression: remove contours whose bbox is mostly inside
        // a larger contour's bbox (stud circles inside a brick outline).
        candidates.sort {
            let a = $0.boundingBox; let b = $1.boundingBox
            return (a.width * a.height) > (b.width * b.height)
        }

        var kept: [VNContour] = []
        for candidate in candidates {
            let cBox = candidate.boundingBox
            let cArea = cBox.width * cBox.height
            let dominated = kept.contains { larger in
                let lBox = larger.boundingBox
                let intersection = cBox.intersection(lBox)
                guard !intersection.isNull,
                      intersection.width > 0,
                      intersection.height > 0 else {
                    return false
                }
                return (intersection.width * intersection.height) / cArea > 0.5
            }
            if !dominated {
                kept.append(candidate)
            }
        }

        let descriptors = kept.compactMap { try? processSingleContour($0, in: cgImage) }

        guard !descriptors.isEmpty else {
            throw ProcessingError.noContoursFound
        }

        return descriptors
    }

    /// Convenience: extracts a single descriptor for the largest piece found.
    static func process(image: UIImage) throws -> ReferenceDescriptor {
        let all = try processAll(image: image)
        guard let first = all.first else {
            throw ProcessingError.noContoursFound
        }
        return first
    }

    // MARK: - Single contour processing

    /// Processes a single contour and extracts a full ReferenceDescriptor.
    private static func processSingleContour(
        _ contour: VNContour,
        in cgImage: CGImage
    ) throws -> ReferenceDescriptor {
        let bbox = contour.boundingBox

        guard let croppedCGImage = cgImage.cropping(toNormalizedRect: bbox) else {
            throw ProcessingError.croppingFailed
        }

        // Vision feature print extraction crashes on very small images
        guard croppedCGImage.width >= 20, croppedCGImage.height >= 20 else {
            throw ProcessingError.croppingFailed
        }

        // Hu moments from contour
        let huMoments = ShapeDescriptor.huMoments(from: contour)

        // Compactness (rotation-invariant, replaces aspect ratio)
        let compactness = ShapeDescriptor.compactness(of: contour)

        // Feature prints from 4 rotations of the cropped image
        var featurePrints: [VNFeaturePrintObservation] = []
        for angle in rotationAngles {
            let rotatedImage: CGImage
            if angle == 0 {
                rotatedImage = croppedCGImage
            } else {
                guard let rotated = croppedCGImage.rotated(by: angle) else { continue }
                rotatedImage = rotated
            }
            if let fp = try? FeaturePrintExtractor.extract(from: rotatedImage) {
                featurePrints.append(fp)
            }
        }

        guard !featurePrints.isEmpty else {
            throw ProcessingError.featurePrintFailed
        }

        // Dominant color — sample from center 60% of the crop to exclude the
        // background that surrounds each piece in the callout box.
        let centerRect = CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
        let (lab, uiColor): (CIELABColor, UIColor)
        if let centerColor = ColorAnalyzer.dominantColor(
            of: croppedCGImage,
            inNormalizedRect: centerRect
        ) {
            (lab, uiColor) = centerColor
        } else {
            (lab, uiColor) = ColorAnalyzer.dominantColor(of: croppedCGImage)
        }

        // Reference image for preview
        let referenceImage = UIImage(cgImage: croppedCGImage)

        return ReferenceDescriptor(
            id: UUID(),
            huMoments: huMoments,
            compactness: compactness,
            featurePrints: featurePrints,
            dominantColor: lab,
            dominantUIColor: uiColor,
            referenceImage: referenceImage,
            displayColor: .white // placeholder, assigned by AppState
        )
    }
}
