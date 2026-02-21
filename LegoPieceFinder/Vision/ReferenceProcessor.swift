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

    /// Processes a photo of a LEGO manual callout box or full page and
    /// extracts descriptors for all piece illustrations found.
    ///
    /// Uses two strategies:
    /// 1. **Box-guided** (preferred): Finds "Nx" quantity markers via text
    ///    recognition, groups them into callout boxes by proximity, crops the
    ///    image per box, and extracts pieces from each box independently.
    ///    This excludes subassemblies, illustrations, and 1:1 references.
    /// 2. **Contour-only** (fallback): If no quantity markers are found,
    ///    detects contours directly and filters by size, color, and chroma.
    static func processAll(image: UIImage) throws -> [ReferenceDescriptor] {
        let normalized = image.normalizedOrientation()
        guard let rawCGImage = normalized.cgImage else {
            throw ProcessingError.croppingFailed
        }

        let cgImage = ContourDetector.downsample(rawCGImage, maxDimension: 2000)
        print("[RefProc] image \(cgImage.width)×\(cgImage.height)")

        let (markers, textRegions) = recognizeText(in: cgImage)
        print("[RefProc] text regions: \(textRegions.count), quantity markers: \(markers.count)")

        // Strategy 1 (preferred): box-guided extraction.
        // Groups markers into callout boxes and extracts pieces from each
        // box independently, excluding subassemblies and illustrations.
        if !markers.isEmpty {
            let descriptors = extractPiecesFromBoxes(
                markers: markers, in: cgImage, textRegions: textRegions
            )
            print("[RefProc] box-guided found \(descriptors.count) pieces from \(markers.count) markers")
            if !descriptors.isEmpty {
                return descriptors
            }
            print("[RefProc] box-guided produced no results, falling through")
        }

        // Strategy 2 (fallback): contour-only detection.
        let contourDescriptors = try extractPiecesFromContours(
            in: cgImage, textRegions: textRegions
        )
        print("[RefProc] contour-only found \(contourDescriptors.count) pieces")

        guard !contourDescriptors.isEmpty else {
            throw ProcessingError.noContoursFound
        }
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

    // MARK: - Callout box detection

    /// Groups quantity markers into separate callout boxes by spatial proximity.
    /// Markers within the same piece box are close together; markers in
    /// different boxes are separated by illustration areas.
    private static func groupMarkersIntoBoxes(_ markers: [CGRect]) -> [[CGRect]] {
        let n = markers.count
        guard n > 1 else { return [markers] }

        // Union-find
        var parent = Array(0..<n)
        func find(_ x: Int) -> Int {
            var i = x
            while parent[i] != i {
                parent[i] = parent[parent[i]]
                i = parent[i]
            }
            return i
        }
        func union(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[ra] = rb }
        }

        // Connect markers that are close enough to be in the same box.
        // Within a piece box, markers are typically within 25% of image
        // dimensions of each other.
        let xThreshold: CGFloat = 0.25
        let yThreshold: CGFloat = 0.25
        for i in 0..<n {
            for j in (i + 1)..<n {
                if abs(markers[i].midX - markers[j].midX) < xThreshold &&
                   abs(markers[i].midY - markers[j].midY) < yThreshold {
                    union(i, j)
                }
            }
        }

        var groups: [Int: [CGRect]] = [:]
        for i in 0..<n {
            groups[find(i), default: []].append(markers[i])
        }
        return Array(groups.values)
    }

    /// Computes the bounding region for a group of markers, expanded to
    /// include the piece area above the markers.
    private static func boxRegion(for markers: [CGRect]) -> CGRect {
        let minX = markers.map(\.minX).min()!
        let maxX = markers.map(\.maxX).max()!
        let minY = markers.map(\.minY).min()!
        let maxY = markers.map(\.maxY).max()!

        // Pieces are above markers (higher Y in Vision coordinates).
        // Extend generously upward and slightly outward.
        let left = max(0, minX - 0.08)
        let bottom = max(0, minY - 0.03)
        let right = min(1.0, maxX + 0.16)
        let top = min(1.0, maxY + 0.50)

        return CGRect(x: left, y: bottom, width: right - left, height: top - bottom)
    }

    /// Extracts pieces by grouping markers into callout boxes and processing
    /// each box independently. This restricts extraction to regions that
    /// contain quantity markers, excluding subassemblies and illustrations.
    private static func extractPiecesFromBoxes(
        markers: [CGRect],
        in cgImage: CGImage,
        textRegions: [CGRect]
    ) -> [ReferenceDescriptor] {
        let groups = groupMarkersIntoBoxes(markers)
        print("[RefProc] \(groups.count) callout box(es) detected")

        var allDescriptors: [ReferenceDescriptor] = []

        for (bi, group) in groups.enumerated() {
            let region = boxRegion(for: group)
            print("[RefProc] box[\(bi)] \(group.count) markers, region=\(region)")

            guard let crop = cgImage.cropping(toNormalizedRect: region) else {
                print("[RefProc] box[\(bi)] crop failed")
                continue
            }
            print("[RefProc] box[\(bi)] crop: \(crop.width)×\(crop.height)")

            // Transform marker coordinates from image space to crop space
            let transformedMarkers = group.map { marker in
                CGRect(
                    x: (marker.origin.x - region.origin.x) / region.width,
                    y: (marker.origin.y - region.origin.y) / region.height,
                    width: marker.width / region.width,
                    height: marker.height / region.height
                )
            }

            // Transform text regions that fall within the box
            let transformedText = textRegions.compactMap { text -> CGRect? in
                let t = CGRect(
                    x: (text.origin.x - region.origin.x) / region.width,
                    y: (text.origin.y - region.origin.y) / region.height,
                    width: text.width / region.width,
                    height: text.height / region.height
                )
                guard t.maxX > 0, t.maxY > 0, t.minX < 1, t.minY < 1 else {
                    return nil
                }
                return t
            }

            let descriptors = extractPiecesUsingMarkers(
                transformedMarkers, in: crop, textRegions: transformedText
            )
            print("[RefProc] box[\(bi)] found \(descriptors.count) pieces")
            allDescriptors.append(contentsOf: descriptors)
        }

        return allDescriptors
    }

    // MARK: - Marker-guided extraction

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

                // Find the best piece contour: prefer interior, moderately-sized, dark.
                // Contours are sorted largest-first; avoid selecting the box border.
                var bestContour: VNContour?
                var fallbackContour: VNContour?

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
                            print("[RefProc] piece[\(pieceIdx)] area=\(area) L=\(color.lab.L)")
                        }
                    }

                    // Save first valid contour as fallback
                    if fallbackContour == nil {
                        fallbackContour = contour
                    }

                    // Prefer contours that don't span the whole cell
                    // (box borders tend to be very large and touch cell edges)
                    let touchesEdge = bbox.minX < 0.02 || bbox.minY < 0.02 ||
                                      bbox.maxX > 0.98 || bbox.maxY > 0.98
                    if area < 0.80 && !touchesEdge {
                        bestContour = contour
                        break
                    }
                }

                var foundPiece = false
                if let contour = bestContour ?? fallbackContour {
                    print("[RefProc] piece[\(pieceIdx)] selected \(bestContour != nil ? "preferred" : "fallback") contour")
                    if let descriptor = try? processSingleContour(contour, in: regionCrop) {
                        descriptors.append(descriptor)
                        foundPiece = true
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
                    // Reject orange/yellow subassembly callouts
                    if color.lab.a > 15 && color.lab.b > 30 {
                        print("[RefProc-C] contour[\(ci)] warm chroma a*=\(color.lab.a) b*=\(color.lab.b), skip")
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

        // Create contour-masked versions of the crop:
        // - Transparent bg: for color extraction (averageOpaqueColor needs alpha)
        // - White bg: for feature print extraction (Vision dislikes alpha)
        // - Off-white bg: for preview image (clean piece on neutral background)
        let transparentMask = croppedCGImage.maskedWithContour(contour, bbox: bbox)
        let whiteBg = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        let whiteMask = croppedCGImage.maskedWithContour(contour, bbox: bbox, backgroundColor: whiteBg)
        let offWhiteBg = CGColor(red: 0.94, green: 0.94, blue: 0.93, alpha: 1)
        let previewMask = croppedCGImage.maskedWithContour(contour, bbox: bbox, backgroundColor: offWhiteBg)

        if previewMask != nil {
            print("[RefProc] contour mask created (\(croppedCGImage.width)×\(croppedCGImage.height))")
        } else {
            print("[RefProc] contour mask failed, using raw crop")
        }

        // Feature prints from 4 rotations — prefer white-bg masked image
        let fpSource = whiteMask ?? croppedCGImage
        var featurePrints: [VNFeaturePrintObservation] = []
        for angle in rotationAngles {
            let rotatedImage: CGImage
            if angle == 0 {
                rotatedImage = fpSource
            } else {
                guard let rotated = fpSource.rotated(by: angle) else { continue }
                rotatedImage = rotated
            }
            if let fp = try? FeaturePrintExtractor.extract(from: rotatedImage) {
                featurePrints.append(fp)
            }
        }

        guard !featurePrints.isEmpty else {
            throw ProcessingError.featurePrintFailed
        }

        // Dominant color — prefer averaging opaque pixels from masked image,
        // fall back to center-60% heuristic on the raw crop.
        let (lab, uiColor): (CIELABColor, UIColor)
        if let masked = transparentMask,
           let opaqueColor = ColorAnalyzer.averageOpaqueColor(of: masked) {
            (lab, uiColor) = opaqueColor
        } else {
            let centerRect = CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
            if let centerColor = ColorAnalyzer.dominantColor(
                of: croppedCGImage,
                inNormalizedRect: centerRect
            ) {
                (lab, uiColor) = centerColor
            } else {
                (lab, uiColor) = ColorAnalyzer.dominantColor(of: croppedCGImage)
            }
        }

        // Reference image for preview — piece on off-white background
        let previewSource = previewMask ?? croppedCGImage
        let referenceImage = UIImage(cgImage: previewSource)

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
