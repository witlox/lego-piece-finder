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
        guard let rawCGImage = image.cgImage else {
            throw ProcessingError.croppingFailed
        }

        // Downsample to limit memory — 2000px is plenty for manual page analysis.
        // Full iPad photos can be 12MP+ which causes OOM during feature extraction.
        let cgImage = ContourDetector.downsample(rawCGImage, maxDimension: 2000)

        // Step 1: Find quantity markers ("1x", "2x", etc.) via text recognition.
        // These are the definitive identifier for piece-list callout boxes.
        let quantityMarkers = findQuantityMarkers(in: cgImage)

        // Step 2: Detect contours on the full page
        let pageContours = try ContourDetector.detect(
            in: cgImage,
            contrastAdjustment: 3.0,
            maxCount: 30
        )

        guard !pageContours.isEmpty else {
            throw ProcessingError.noContoursFound
        }

        // Step 3: Sample the page background color (from corners)
        let pageBackground = samplePageBackground(in: cgImage)

        // Step 4: Find callout boxes that contain quantity markers
        let calloutBoxes = findCalloutBoxes(
            from: pageContours,
            in: cgImage,
            quantityMarkers: quantityMarkers,
            pageBackground: pageBackground
        )

        // Step 5: Extract pieces from each callout box
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

        // Step 6: Fallback — if no callout boxes found or they produced no pieces,
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

    // MARK: - Text recognition for quantity markers

    /// Detects quantity marker text ("1x", "2x", "3x", etc.) on the page.
    /// Returns their bounding boxes in Vision normalized coordinates.
    /// These markers are the definitive identifier for piece-list callout boxes.
    private static func findQuantityMarkers(in cgImage: CGImage) -> [CGRect] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        guard (try? handler.perform([request])) != nil,
              let results = request.results else {
            return []
        }

        var markers: [CGRect] = []
        for observation in results {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string
            // Match "1x", "2x", "10x", also "1×", "2×" (multiplication sign)
            if text.range(of: #"\d+[x×X]"#, options: .regularExpression) != nil {
                markers.append(observation.boundingBox)
            }
        }

        return markers
    }

    // MARK: - Page background sampling

    /// Samples the page background color from corner regions.
    private static func samplePageBackground(in cgImage: CGImage) -> CIELABColor {
        let cornerRects = [
            CGRect(x: 0.0, y: 0.9, width: 0.1, height: 0.1),   // top-left
            CGRect(x: 0.9, y: 0.9, width: 0.1, height: 0.1),   // top-right
            CGRect(x: 0.0, y: 0.0, width: 0.1, height: 0.1),   // bottom-left
            CGRect(x: 0.9, y: 0.0, width: 0.1, height: 0.1),   // bottom-right
        ]

        var colors: [CIELABColor] = []
        for rect in cornerRects {
            if let color = ColorAnalyzer.dominantColor(
                of: cgImage,
                inNormalizedRect: rect
            ) {
                colors.append(color.lab)
            }
        }

        guard !colors.isEmpty else {
            return CIELABColor(L: 95, a: 0, b: 0) // assume white
        }

        let avgL = colors.map(\.L).reduce(0, +) / CGFloat(colors.count)
        let avgA = colors.map(\.a).reduce(0, +) / CGFloat(colors.count)
        let avgB = colors.map(\.b).reduce(0, +) / CGFloat(colors.count)
        return CIELABColor(L: avgL, a: avgA, b: avgB)
    }

    // MARK: - Callout box detection

    /// A detected callout box: its cropped image and the background color.
    private struct CalloutBox {
        let crop: CGImage
        let backgroundColor: CIELABColor
    }

    /// Finds piece-list callout boxes on a LEGO manual page.
    ///
    /// Uses two primary signals:
    /// 1. **Quantity markers**: Boxes must contain "1x", "2x", etc. text —
    ///    the definitive identifier for piece-list boxes in all LEGO manuals.
    /// 2. **Least contrasting background**: Among boxes containing markers,
    ///    piece-list boxes have the background closest to the page color
    ///    (grey on white page, light blue on white page, etc.), unlike
    ///    orange sub-assembly boxes which are intentionally high-contrast.
    private static func findCalloutBoxes(
        from contours: [VNContour],
        in cgImage: CGImage,
        quantityMarkers: [CGRect],
        pageBackground: CIELABColor
    ) -> [CalloutBox] {
        // Collect all candidate boxes that contain quantity marker text
        var candidates: [(box: CalloutBox, pageDistance: CGFloat)] = []

        for contour in contours {
            let bbox = contour.boundingBox
            let area = bbox.width * bbox.height
            guard area > 0.005, area < 0.35 else { continue }

            // Must contain at least one quantity marker center point.
            // Use a slightly enlarged bbox to account for contour imprecision.
            let enlarged = bbox.insetBy(dx: -0.02, dy: -0.02)
            let markerCount = quantityMarkers.filter { marker in
                let center = CGPoint(x: marker.midX, y: marker.midY)
                return enlarged.contains(center)
            }.count
            guard markerCount > 0 else { continue }

            guard let crop = cgImage.cropping(toNormalizedRect: bbox) else { continue }

            // Compute background color from edges
            let bgColor = boxBackgroundColor(of: crop)

            // Distance from page background — piece-list boxes are the
            // least contrasting (closest to page color)
            let pageDist = pageBackground.distance(to: bgColor)

            candidates.append((
                box: CalloutBox(crop: crop, backgroundColor: bgColor),
                pageDistance: pageDist
            ))
        }

        guard !candidates.isEmpty else { return [] }

        // Find the minimum page distance among candidates — this represents
        // the piece-list box background color for this manual.
        let minDist = candidates.map(\.pageDistance).min() ?? 0

        // Keep all boxes within a reasonable range of the closest background.
        // This handles pages with multiple piece-list boxes (all same color).
        // Reject boxes that are much more contrasting (e.g., orange sub-assembly
        // boxes that happen to have "2x" text nearby).
        return candidates
            .filter { $0.pageDistance <= minDist + 20 }
            .map(\.box)
    }

    /// Computes the average background color of a box from its edge strips.
    private static func boxBackgroundColor(of crop: CGImage) -> CIELABColor {
        let edgeRects = [
            CGRect(x: 0.05, y: 0.85, width: 0.9, height: 0.1),
            CGRect(x: 0.05, y: 0.05, width: 0.9, height: 0.1),
            CGRect(x: 0.05, y: 0.15, width: 0.1, height: 0.7),
            CGRect(x: 0.85, y: 0.15, width: 0.1, height: 0.7),
        ]

        var colors: [CIELABColor] = []
        for rect in edgeRects {
            if let color = ColorAnalyzer.dominantColor(
                of: crop,
                inNormalizedRect: rect
            ) {
                colors.append(color.lab)
            }
        }

        guard !colors.isEmpty else {
            return ColorAnalyzer.dominantColor(of: crop).lab
        }

        let avgL = colors.map(\.L).reduce(0, +) / CGFloat(colors.count)
        let avgA = colors.map(\.a).reduce(0, +) / CGFloat(colors.count)
        let avgB = colors.map(\.b).reduce(0, +) / CGFloat(colors.count)
        return CIELABColor(L: avgL, a: avgA, b: avgB)
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
