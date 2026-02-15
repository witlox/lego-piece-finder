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

        // Single text recognition pass — extract both quantity markers
        // and all text regions (for filtering out step numbers etc.).
        let (markers, textRegions) = recognizeText(in: cgImage)
        print("[RefProc] text regions: \(textRegions.count), quantity markers: \(markers.count)")

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

    // MARK: - Text detection (single pass)

    /// Runs text recognition once and returns both quantity markers and
    /// all text bounding boxes. Using a single pass avoids running the
    /// expensive `.accurate` neural network twice.
    private static func recognizeText(
        in cgImage: CGImage
    ) -> (markers: [CGRect], allText: [CGRect]) {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        guard (try? handler.perform([request])) != nil,
              let results = request.results else {
            return ([], [])
        }

        var markers: [CGRect] = []
        var allText: [CGRect] = []

        for observation in results {
            allText.append(observation.boundingBox)
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string
            print("[RefProc] text: \"\(text)\" at \(observation.boundingBox)")
            if text.range(of: #"^\d+[x×X]$"#, options: .regularExpression) != nil {
                print("[RefProc]   → quantity marker")
                markers.append(observation.boundingBox)
            }
        }

        return (markers.sorted { $0.midX < $1.midX }, allText)
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

    /// Extracts one piece per quantity marker using grid-based splitting.
    ///
    /// LEGO callout boxes arrange pieces in a grid. Each marker ("1x", "2x")
    /// sits underneath and to the left of its piece. This method:
    /// 1. Clusters markers by x-position into columns
    /// 2. Within each column, sorts by y-position into rows
    /// 3. For each marker, computes a cell region (above the marker, bounded
    ///    by the next row/column or image edge)
    /// 4. Finds the largest dark contour in each cell — the piece
    private static func extractPiecesUsingMarkers(
        _ markers: [CGRect],
        in cgImage: CGImage,
        textRegions: [CGRect]
    ) -> [ReferenceDescriptor] {

        // ── Step 1: Cluster markers into grid columns by x-position ──
        // Sort by midX, then group markers within 15% of image width.
        let sorted = markers.sorted { $0.midX < $1.midX }
        let clusterThreshold: CGFloat = 0.15
        var columns: [[CGRect]] = []
        for marker in sorted {
            if let lastIdx = columns.indices.last,
               abs(columns[lastIdx].last!.midX - marker.midX) < clusterThreshold {
                columns[lastIdx].append(marker)
            } else {
                columns.append([marker])
            }
        }

        // Sort each column by y (bottom to top in Vision coords)
        for i in columns.indices {
            columns[i].sort { $0.midY < $1.midY }
        }

        // ── Step 2: Compute column x-boundaries (midpoints between columns) ──
        let columnMidXs = columns.map { col in
            col.map(\.midX).reduce(0, +) / CGFloat(col.count)
        }
        var colLeftEdges: [CGFloat] = []
        var colRightEdges: [CGFloat] = []
        for ci in columns.indices {
            let left: CGFloat = ci == 0 ? 0 : (columnMidXs[ci - 1] + columnMidXs[ci]) / 2
            let right: CGFloat = ci == columns.count - 1 ? 1.0 : (columnMidXs[ci] + columnMidXs[ci + 1]) / 2
            colLeftEdges.append(left)
            colRightEdges.append(right)
        }

        print("[RefProc] grid: \(columns.count) cols × \(columns.map(\.count).max() ?? 0) rows")

        // ── Step 3: For each marker, compute cell and extract piece ──
        var descriptors: [ReferenceDescriptor] = []
        var pieceIdx = 0

        for (ci, column) in columns.enumerated() {
            for (ri, marker) in column.enumerated() {
                // Cell bottom: just above the marker text
                let cellBottom = marker.maxY
                // Cell top: bottom of the next row's marker, or image top
                let cellTop: CGFloat
                if ri < column.count - 1 {
                    cellTop = column[ri + 1].minY
                } else {
                    cellTop = 1.0
                }

                let cellRect = CGRect(
                    x: colLeftEdges[ci],
                    y: cellBottom,
                    width: colRightEdges[ci] - colLeftEdges[ci],
                    height: cellTop - cellBottom
                )

                print("[RefProc] piece[\(pieceIdx)] col=\(ci) row=\(ri) cell=\(cellRect)")

                guard cellRect.width > 0.01, cellRect.height > 0.01,
                      let regionCrop = cgImage.cropping(toNormalizedRect: cellRect) else {
                    print("[RefProc] piece[\(pieceIdx)] cell crop failed")
                    pieceIdx += 1
                    continue
                }

                print("[RefProc] piece[\(pieceIdx)] crop: \(regionCrop.width)×\(regionCrop.height)")

                guard let contours = try? ContourDetector.detect(
                    in: regionCrop,
                    contrastAdjustment: 3.0,
                    maxCount: 5
                ), !contours.isEmpty else {
                    print("[RefProc] piece[\(pieceIdx)] no contours")
                    pieceIdx += 1
                    continue
                }

                var foundPiece = false
                for contour in contours {
                    let bbox = contour.boundingBox
                    let area = bbox.width * bbox.height
                    guard area > 0.01 else { continue }

                    if let crop = regionCrop.cropping(toNormalizedRect: bbox) {
                        let centerRect = CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
                        if let color = ColorAnalyzer.dominantColor(
                            of: crop,
                            inNormalizedRect: centerRect
                        ) {
                            if color.lab.L >= 85 { continue }
                            print("[RefProc] piece[\(pieceIdx)] area=\(area) L=\(color.lab.L) — ok")
                        }
                    }

                    if let descriptor = try? processSingleContour(contour, in: regionCrop) {
                        descriptors.append(descriptor)
                        foundPiece = true
                        break
                    }
                }
                if !foundPiece {
                    print("[RefProc] piece[\(pieceIdx)] no valid contour")
                }
                pieceIdx += 1
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
            // Min 1% to skip studs/details; max 40% to skip the box border
            guard area > 0.01, area < 0.40 else {
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
