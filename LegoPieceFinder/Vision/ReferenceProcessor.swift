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
    /// Uses two strategies:
    /// 1. **Text-guided** (preferred): Finds "1x", "2x" quantity markers via
    ///    text recognition, divides the image into columns around each marker,
    ///    and extracts the piece from each column. This reliably splits pieces
    ///    that contour detection alone might merge.
    /// 2. **Contour-only** (fallback): If no quantity markers are found,
    ///    detects contours directly and filters by size and color.
    static func processAll(image: UIImage) throws -> [ReferenceDescriptor] {
        // Normalize orientation first — UIImage.cgImage returns raw pixels
        // without applying imageOrientation, so a rotated iPad would produce
        // a sideways image breaking text recognition and column splitting.
        let normalized = image.normalizedOrientation()
        guard let rawCGImage = normalized.cgImage else {
            throw ProcessingError.croppingFailed
        }

        // Downsample to limit memory — 2000px is plenty for callout box analysis.
        let cgImage = ContourDetector.downsample(rawCGImage, maxDimension: 2000)
        print("[RefProc] image \(cgImage.width)×\(cgImage.height)")

        // Detect all text regions so we can exclude contours that are just
        // text (step numbers, labels, etc.) rather than piece illustrations.
        let textRegions = findAllTextRegions(in: cgImage)
        print("[RefProc] text regions: \(textRegions.count)")

        // Run contour-only detection — this is the reliable base that finds
        // all pieces. It may merge adjacent pieces into one contour though.
        let contourDescriptors: [ReferenceDescriptor]
        do {
            contourDescriptors = try extractPiecesFromContours(
                in: cgImage, textRegions: textRegions
            )
        } catch {
            contourDescriptors = []
        }
        print("[RefProc] contour-only found \(contourDescriptors.count) pieces")

        // Try text-guided splitting for additional pieces that contour
        // detection may have merged. Markers let us split merged blobs.
        let markers = findQuantityMarkers(in: cgImage)
        print("[RefProc] quantity markers: \(markers.count)")

        if markers.count > contourDescriptors.count {
            // Markers suggest more pieces than contours found — use
            // text-guided extraction which can split merged contours.
            let markerDescriptors = extractPiecesUsingMarkers(
                markers, in: cgImage, textRegions: textRegions
            )
            print("[RefProc] text-guided found \(markerDescriptors.count) pieces")

            if markerDescriptors.count > contourDescriptors.count {
                print("[RefProc] using text-guided (\(markerDescriptors.count) > \(contourDescriptors.count))")
                return markerDescriptors
            }
        }

        guard !contourDescriptors.isEmpty else {
            throw ProcessingError.noContoursFound
        }

        print("[RefProc] using contour-only (\(contourDescriptors.count) pieces)")
        return contourDescriptors
    }

    /// Convenience: extracts a single descriptor for the largest piece found.
    static func process(image: UIImage) throws -> ReferenceDescriptor {
        let all = try processAll(image: image)
        guard let first = all.first else {
            throw ProcessingError.noContoursFound
        }
        return first
    }

    // MARK: - Text detection

    /// Detects all text bounding boxes in the image.
    /// Used to filter out contours that are text (step numbers, labels)
    /// rather than piece illustrations.
    private static func findAllTextRegions(in cgImage: CGImage) -> [CGRect] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        guard (try? handler.perform([request])) != nil,
              let results = request.results else {
            return []
        }

        return results.map(\.boundingBox)
    }

    /// Returns true if the contour bbox overlaps significantly with any
    /// detected text region — meaning it's likely a number or label.
    private static func isTextContour(
        _ bbox: CGRect,
        textRegions: [CGRect]
    ) -> Bool {
        let contourArea = bbox.width * bbox.height
        guard contourArea > 0 else { return false }
        for textBox in textRegions {
            let intersection = bbox.intersection(textBox)
            guard !intersection.isNull,
                  intersection.width > 0,
                  intersection.height > 0 else { continue }
            let overlapRatio = (intersection.width * intersection.height) / contourArea
            if overlapRatio > 0.5 { return true }
        }
        return false
    }

    // MARK: - Text-guided piece extraction

    /// Detects quantity marker text ("1x", "2x", etc.) in the image.
    /// Returns their bounding boxes sorted left-to-right.
    private static func findQuantityMarkers(in cgImage: CGImage) -> [CGRect] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
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
            print("[RefProc] detected text: \"\(text)\" at \(observation.boundingBox)")
            // Match "1x", "2x", "10x", also "1×", "2×" (multiplication sign)
            if text.range(of: #"\d+[x×X]"#, options: .regularExpression) != nil {
                print("[RefProc]   → matched as quantity marker")
                markers.append(observation.boundingBox)
            }
        }

        return markers.sorted { $0.midX < $1.midX }
    }

    /// Extracts one piece per quantity marker by dividing the image into
    /// columns based on marker positions.
    ///
    /// LEGO callout boxes arrange pieces in a row with "1x"/"2x" markers
    /// below each piece. This method:
    /// 1. Sorts markers left-to-right
    /// 2. Computes column boundaries (midpoints between adjacent markers)
    /// 3. For each column, crops the region above the marker
    /// 4. Finds the largest dark contour in that region — the piece
    private static func extractPiecesUsingMarkers(
        _ markers: [CGRect],
        in cgImage: CGImage,
        textRegions: [CGRect]
    ) -> [ReferenceDescriptor] {
        var descriptors: [ReferenceDescriptor] = []

        for (i, marker) in markers.enumerated() {
            // Column left edge: midpoint to previous marker, or image edge
            let leftEdge: CGFloat
            if i == 0 {
                leftEdge = 0
            } else {
                leftEdge = (markers[i - 1].midX + marker.midX) / 2
            }

            // Column right edge: midpoint to next marker, or image edge
            let rightEdge: CGFloat
            if i == markers.count - 1 {
                rightEdge = 1.0
            } else {
                rightEdge = (marker.midX + markers[i + 1].midX) / 2
            }

            // Search region: the column area above the marker text.
            // In Vision coordinates (bottom-left origin), "above" = higher y.
            let columnRect = CGRect(
                x: leftEdge,
                y: marker.maxY,
                width: rightEdge - leftEdge,
                height: 1.0 - marker.maxY
            )

            print("[RefProc] marker[\(i)] column: \(columnRect)")

            guard columnRect.width > 0.01, columnRect.height > 0.01,
                  let regionCrop = cgImage.cropping(toNormalizedRect: columnRect) else {
                print("[RefProc] marker[\(i)] column crop failed")
                continue
            }

            print("[RefProc] marker[\(i)] regionCrop: \(regionCrop.width)×\(regionCrop.height)")

            // Find piece contour in this column
            guard let contours = try? ContourDetector.detect(
                in: regionCrop,
                contrastAdjustment: 3.0,
                maxCount: 5
            ), !contours.isEmpty else {
                print("[RefProc] marker[\(i)] no contours in column")
                continue
            }

            print("[RefProc] marker[\(i)] \(contours.count) contours in column")

            // Take the largest contour that's dark enough (not background)
            var foundPiece = false
            for contour in contours {
                let bbox = contour.boundingBox
                let area = bbox.width * bbox.height
                guard area > 0.03 else {
                    print("[RefProc]   contour area \(area) < 0.03, skip")
                    continue
                }

                // Check it's not background
                if let crop = regionCrop.cropping(toNormalizedRect: bbox) {
                    let centerRect = CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
                    if let color = ColorAnalyzer.dominantColor(
                        of: crop,
                        inNormalizedRect: centerRect
                    ) {
                        if color.lab.L >= 85 {
                            print("[RefProc]   contour L=\(color.lab.L) >= 85, skip (too light)")
                            continue
                        }
                        print("[RefProc]   contour area=\(area) L=\(color.lab.L) — accepted")
                    }
                }

                if let descriptor = try? processSingleContour(contour, in: regionCrop) {
                    descriptors.append(descriptor)
                    foundPiece = true
                    break // one piece per marker
                } else {
                    print("[RefProc]   processSingleContour failed for contour")
                }
            }
            if !foundPiece {
                print("[RefProc] marker[\(i)] no valid piece found")
            }
        }

        return descriptors
    }

    // MARK: - Contour-only fallback

    /// Extracts pieces using contour detection only (no text guidance).
    /// Used when no quantity markers are found in the image.
    private static func extractPiecesFromContours(
        in cgImage: CGImage,
        textRegions: [CGRect]
    ) throws -> [ReferenceDescriptor] {
        let contours = try ContourDetector.detect(
            in: cgImage,
            contrastAdjustment: 3.0,
            maxCount: 15
        )

        guard !contours.isEmpty else {
            throw ProcessingError.noContoursFound
        }

        var candidates: [VNContour] = []
        for (ci, contour) in contours.enumerated() {
            let bbox = contour.boundingBox
            let area = bbox.width * bbox.height
            guard area > 0.02, area < 0.60 else {
                print("[RefProc-C] contour[\(ci)] area=\(area) out of range, skip")
                continue
            }

            // Skip contours that overlap significantly with detected text
            // (step numbers, labels, quantity markers).
            if isTextContour(bbox, textRegions: textRegions) {
                print("[RefProc-C] contour[\(ci)] overlaps text, skip")
                continue
            }

            if let crop = cgImage.cropping(toNormalizedRect: bbox) {
                let centerRect = CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
                if let color = ColorAnalyzer.dominantColor(
                    of: crop,
                    inNormalizedRect: centerRect
                ) {
                    if color.lab.L >= 82 {
                        print("[RefProc-C] contour[\(ci)] L=\(color.lab.L) >= 82, skip")
                        continue
                    }
                    print("[RefProc-C] contour[\(ci)] area=\(area) L=\(color.lab.L) — kept")
                }
            }

            candidates.append(contour)
        }
        print("[RefProc-C] \(candidates.count) candidates after filtering")

        // Non-maximum suppression
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

        return kept.compactMap { try? processSingleContour($0, in: cgImage) }
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
