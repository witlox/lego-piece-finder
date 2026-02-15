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

    // MARK: - Multi-reference extraction

    /// Processes a manual page photo and extracts descriptors for all pieces in the callout box.
    ///
    /// LEGO manuals have a consistent layout: each step has a bordered callout box (black border,
    /// slightly grey background) listing the needed pieces. This method:
    /// 1. Finds the callout box on the full page (largest mid-sized rectangular contour)
    /// 2. Crops to it — isolating pieces from wood grain, page edges, build illustrations
    /// 3. Detects piece contours inside the callout box on its clean, uniform background
    /// 4. Applies NMS to remove overlapping internal details (studs, face edges)
    ///
    /// Falls back to direct contour detection if no callout box is found (e.g. zoomed-in photo).
    static func processAll(image: UIImage) throws -> [ReferenceDescriptor] {
        guard let cgImage = image.cgImage else {
            throw ProcessingError.croppingFailed
        }

        // Step 1: Detect contours on the full page photo
        let pageContours = try ContourDetector.detect(
            in: cgImage,
            contrastAdjustment: 3.0,
            maxCount: 15
        )

        guard !pageContours.isEmpty else {
            throw ProcessingError.noContoursFound
        }

        // Step 2: Find the callout box — the largest contour in the 3-30% area range.
        // The callout box is always the most prominent bordered rectangle on the page,
        // larger than piece illustrations but smaller than the page itself.
        let calloutContour = pageContours
            .filter {
                let area = $0.boundingBox.width * $0.boundingBox.height
                return area > 0.03 && area < 0.30
            }
            .max {
                ($0.boundingBox.width * $0.boundingBox.height) <
                ($1.boundingBox.width * $1.boundingBox.height)
            }

        // Step 3: Crop to the callout box and re-detect contours inside it
        let pieceImage: CGImage
        if let callout = calloutContour,
           let crop = cgImage.cropping(toNormalizedRect: callout.boundingBox) {
            pieceImage = crop
        } else {
            // Fallback: no callout box found (user may have zoomed into pieces).
            // Use the full image.
            pieceImage = cgImage
        }

        let pieceContours = try ContourDetector.detect(
            in: pieceImage,
            contrastAdjustment: 3.0,
            maxCount: 10
        )

        guard !pieceContours.isEmpty else {
            throw ProcessingError.noContoursFound
        }

        // Step 4: Filter piece-sized contours within the callout box.
        // Inside the crop, pieces are a larger fraction of the area (typically 3-50%).
        // Also reject contours whose center is too light (background, not a piece).
        var candidates: [VNContour] = []
        for contour in pieceContours {
            let bbox = contour.boundingBox
            let area = bbox.width * bbox.height
            guard area > 0.02, area < 0.60 else { continue }

            // Lightness check: piece illustrations have dark content (L < 80).
            // Plain background regions and text labels are very light.
            if let crop = pieceImage.cropping(toNormalizedRect: bbox) {
                let centerRect = CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
                if let color = ColorAnalyzer.dominantColor(of: crop, inNormalizedRect: centerRect) {
                    guard color.lab.L < 80 else { continue }
                }
            }

            candidates.append(contour)
        }

        // Step 5: Non-maximum suppression — remove contours whose bbox is mostly
        // inside a larger contour's bbox (stud circles inside a brick outline).
        candidates.sort {
            let a = $0.boundingBox; let b = $1.boundingBox
            return (a.width * a.height) > (b.width * b.height)
        }

        var kept: [VNContour] = []
        for candidate in candidates {
            let cBox = candidate.boundingBox
            let cArea = cBox.width * cBox.height
            let dominated = kept.contains { larger in
                let intersection = cBox.intersection(larger.boundingBox)
                guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else {
                    return false
                }
                return (intersection.width * intersection.height) / cArea > 0.5
            }
            if !dominated {
                kept.append(candidate)
            }
        }

        // Step 6: Process surviving contours into descriptors
        var descriptors: [ReferenceDescriptor] = []
        for contour in kept {
            if let descriptor = try? processSingleContour(contour, in: pieceImage) {
                descriptors.append(descriptor)
            }
        }

        guard !descriptors.isEmpty else {
            throw ProcessingError.noContoursFound
        }

        return descriptors
    }

    /// Processes a single contour and extracts a full ReferenceDescriptor.
    private static func processSingleContour(
        _ contour: VNContour,
        in cgImage: CGImage
    ) throws -> ReferenceDescriptor {
        let bbox = contour.boundingBox

        guard let croppedCGImage = cgImage.cropping(toNormalizedRect: bbox) else {
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
        // white/light background that surrounds each piece in manual illustrations.
        // Without this, a black brick's average color becomes medium grey.
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

    // MARK: - Legacy single-piece extraction

    /// Processes a manual illustration photo and extracts a single ReferenceDescriptor
    /// for the largest piece found.
    static func process(image: UIImage) throws -> ReferenceDescriptor {
        let all = try processAll(image: image)
        guard let first = all.first else {
            throw ProcessingError.noContoursFound
        }
        return first
    }
}
