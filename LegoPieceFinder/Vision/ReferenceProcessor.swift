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

    /// Minimum bbox area for a piece contour (filters text, studs, noise).
    private static let minPieceArea: CGFloat = 0.003

    /// Contours above this area are likely callout borders or page edges.
    /// Instead of processing them directly, we descend into their children.
    private static let largeContourArea: CGFloat = 0.08

    /// Processes a manual illustration photo and extracts descriptors for all visible pieces.
    /// Handles the callout-box hierarchy: if a contour is large (likely a callout border),
    /// its child contours (the actual pieces) are processed instead.
    /// Applies non-maximum suppression to remove overlapping internal details (studs, face edges).
    static func processAll(image: UIImage) throws -> [ReferenceDescriptor] {
        guard let cgImage = image.cgImage else {
            throw ProcessingError.croppingFailed
        }

        let contours = try ContourDetector.detect(
            in: cgImage,
            contrastAdjustment: 3.0,
            maxCount: 10
        )

        guard !contours.isEmpty else {
            throw ProcessingError.noContoursFound
        }

        // Collect piece-sized candidate contours from all hierarchy levels
        var candidates: [VNContour] = []

        for contour in contours {
            let bbox = contour.boundingBox
            let area = bbox.width * bbox.height

            guard area > minPieceArea else { continue }

            if area > largeContourArea {
                // Large contour — likely a callout box border or page edge.
                // Descend into children to find the actual piece illustrations.
                for i in 0..<contour.childContourCount {
                    guard let child = try? contour.childContour(at: i) else { continue }
                    let childArea = child.boundingBox.width * child.boundingBox.height
                    guard childArea > minPieceArea, childArea < largeContourArea else { continue }
                    candidates.append(child)
                }
            } else {
                candidates.append(contour)
            }
        }

        // Non-maximum suppression: remove contours whose bbox is mostly inside a
        // larger contour's bbox (e.g. stud circles inside a brick outline).
        // Sort largest-first so we keep piece outlines and drop internal details.
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
                let overlapArea = intersection.width * intersection.height
                return overlapArea / cArea > 0.5
            }
            if !dominated {
                kept.append(candidate)
            }
        }

        // Process surviving contours into descriptors
        var descriptors: [ReferenceDescriptor] = []
        for contour in kept {
            if let descriptor = try? processSingleContour(contour, in: cgImage) {
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
