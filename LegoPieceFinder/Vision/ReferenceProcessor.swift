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

    /// Processes a manual page photo and extracts descriptors for all pieces shown
    /// in the piece-list callout boxes.
    ///
    /// Works with both full-page photos and zoomed-in callout box photos:
    /// 1. Finds all callout boxes on the page (uniform background, bordered)
    /// 2. Detects piece illustrations inside each callout box
    /// 3. Falls back to full-image detection if no callout boxes are found
    ///
    /// Callout box background color varies between manuals (grey, blue, white,
    /// etc.) but is consistent within a single manual. Detection uses structural
    /// properties (uniform edges, contrasting center) rather than specific colors.
    static func processAll(image: UIImage) throws -> [ReferenceDescriptor] {
        guard let cgImage = image.cgImage else {
            throw ProcessingError.croppingFailed
        }

        // Step 1: Detect contours on the full page
        let pageContours = try ContourDetector.detect(
            in: cgImage,
            contrastAdjustment: 3.0,
            maxCount: 20
        )

        guard !pageContours.isEmpty else {
            throw ProcessingError.noContoursFound
        }

        // Step 2: Find all piece-list callout boxes (color-agnostic)
        let calloutBoxes = findCalloutBoxes(from: pageContours, in: cgImage)

        // Step 3: Extract pieces from each callout box
        var descriptors: [ReferenceDescriptor] = []
        if !calloutBoxes.isEmpty {
            for box in calloutBoxes {
                if let pieces = try? extractPieces(
                    from: box.crop,
                    backgroundColor: box.backgroundColor
                ) {
                    descriptors.append(contentsOf: pieces)
                }
            }
        }

        // Step 4: Fallback — if no callout boxes found or they produced no pieces,
        // the user likely zoomed into a callout box. Process the full image.
        if descriptors.isEmpty {
            if let pieces = try? extractPieces(from: cgImage, backgroundColor: nil) {
                descriptors = pieces
            }
        }

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

    // MARK: - Callout box detection

    /// A detected callout box: its cropped image and the background color.
    private struct CalloutBox {
        let crop: CGImage
        let backgroundColor: CIELABColor
    }

    /// Finds all piece-list callout boxes on a LEGO manual page.
    ///
    /// Uses structural properties instead of hardcoded colors, because
    /// callout box backgrounds vary between manuals (grey, blue, white, etc.)
    /// but are consistent within a single manual.
    ///
    /// Detection criteria:
    /// - Area 1.5-35% of the page
    /// - Uniform edge color: 4 edge strips (top/bottom/left/right) all have
    ///   similar CIELAB color (max pairwise distance < 25)
    /// - Center contrast: the center region differs from the edge background
    ///   (CIELAB distance > 5), indicating piece illustrations inside
    /// - Not page white (average edge L < 92)
    /// - Not orange/amber sub-assembly box (a* > 10 and b* > 25 in CIELAB)
    ///
    /// Rejects build illustrations (varied colors → high edge distance),
    /// page background (L > 92), orange sub-assembly boxes (universal LEGO
    /// design: amber background with numbered steps), and small elements.
    private static func findCalloutBoxes(
        from contours: [VNContour],
        in cgImage: CGImage
    ) -> [CalloutBox] {
        var boxes: [CalloutBox] = []

        for contour in contours {
            let bbox = contour.boundingBox
            let area = bbox.width * bbox.height
            guard area > 0.015, area < 0.35 else { continue }

            guard let crop = cgImage.cropping(toNormalizedRect: bbox) else { continue }

            // Sample 4 edge strips to check for a uniform background
            let edgeRects = [
                CGRect(x: 0.05, y: 0.85, width: 0.9, height: 0.1),  // top
                CGRect(x: 0.05, y: 0.05, width: 0.9, height: 0.1),  // bottom
                CGRect(x: 0.05, y: 0.15, width: 0.1, height: 0.7),  // left
                CGRect(x: 0.85, y: 0.15, width: 0.1, height: 0.7),  // right
            ]

            var edgeColors: [CIELABColor] = []
            for rect in edgeRects {
                if let color = ColorAnalyzer.dominantColor(
                    of: crop,
                    inNormalizedRect: rect
                ) {
                    edgeColors.append(color.lab)
                }
            }

            guard edgeColors.count >= 3 else { continue }

            // Edge uniformity: all strips should have similar color.
            // Build illustrations fail here (many different colors at edges).
            var maxEdgeDist: CGFloat = 0
            for i in 0..<edgeColors.count {
                for j in (i + 1)..<edgeColors.count {
                    let dist = edgeColors[i].distance(to: edgeColors[j])
                    maxEdgeDist = max(maxEdgeDist, dist)
                }
            }
            guard maxEdgeDist < 25 else { continue }

            // Compute average edge color = background color
            let avgL = edgeColors.map(\.L).reduce(0, +) / CGFloat(edgeColors.count)
            let avgA = edgeColors.map(\.a).reduce(0, +) / CGFloat(edgeColors.count)
            let avgB = edgeColors.map(\.b).reduce(0, +) / CGFloat(edgeColors.count)
            let bgColor = CIELABColor(L: avgL, a: avgA, b: avgB)

            // Reject page white — the page itself is not a callout box
            guard avgL < 92 else { continue }

            // Reject orange/amber sub-assembly boxes. These are a universal
            // LEGO design standard (same amber color across ALL manuals) used
            // for numbered sub-assembly steps. In CIELAB, orange/amber has
            // positive a* (toward red) and positive b* (toward yellow).
            // Grey (a≈0,b≈0), blue (a≈0,b<0), and white all pass safely.
            guard !(avgA > 10 && avgB > 25) else { continue }

            // Center contrast: piece illustrations in the center should differ
            // from the uniform background at the edges.
            let centerRect = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
            if let centerColor = ColorAnalyzer.dominantColor(
                of: crop,
                inNormalizedRect: centerRect
            ) {
                let centerDist = bgColor.distance(to: centerColor.lab)
                guard centerDist > 5 else { continue }
            }

            boxes.append(CalloutBox(crop: crop, backgroundColor: bgColor))
        }

        return boxes
    }

    // MARK: - Piece extraction within a callout box

    /// Detects and extracts piece illustrations from a callout box crop.
    ///
    /// - Parameters:
    ///   - image: The cropped callout box (or full image for fallback).
    ///   - backgroundColor: The callout box's background color (from edge sampling).
    ///     When nil (fallback mode), uses an absolute lightness threshold.
    private static func extractPieces(
        from image: CGImage,
        backgroundColor: CIELABColor?
    ) throws -> [ReferenceDescriptor] {
        let contours = try ContourDetector.detect(
            in: image,
            contrastAdjustment: 3.0,
            maxCount: 10
        )

        // Filter to piece-sized contours whose color differs from the background
        var candidates: [VNContour] = []
        for contour in contours {
            let bbox = contour.boundingBox
            let area = bbox.width * bbox.height
            guard area > 0.02, area < 0.60 else { continue }

            // Color check: reject contours that look like background.
            // With a known background color, reject if too similar (CIELAB < 12).
            // Without (fallback), reject if too light (L > 82).
            if let crop = image.cropping(toNormalizedRect: bbox) {
                let centerRect = CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
                if let color = ColorAnalyzer.dominantColor(
                    of: crop,
                    inNormalizedRect: centerRect
                ) {
                    if let bg = backgroundColor {
                        guard bg.distance(to: color.lab) > 12 else { continue }
                    } else {
                        guard color.lab.L < 82 else { continue }
                    }
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

        return kept.compactMap { try? processSingleContour($0, in: image) }
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
