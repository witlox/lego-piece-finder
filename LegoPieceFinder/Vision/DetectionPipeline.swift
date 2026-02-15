import CoreGraphics
import UIKit
import Vision

actor DetectionPipeline {

    // MARK: - Thresholds (tunable)

    /// Minimum Hu moment similarity to pass shape filter (0…1, higher = stricter).
    /// Relaxed from 0.3 — illustration-vs-real shape matching is inherently imprecise.
    var huMomentThreshold: Double = 0.15

    /// Minimum compactness similarity to pass shape filter (0…1, higher = stricter).
    /// Relaxed from 0.5 — 3D viewing angle changes compactness vs 2D illustration.
    var compactnessThreshold: Double = 0.3

    /// Minimum composite score to qualify as a match (0…1, higher = stricter).
    var scoreThreshold: Double = 0.25

    /// Maximum CIELAB distance for "shape + color" classification.
    var colorMatchThreshold: CGFloat = 35.0

    /// Maximum CIELAB distance for color pre-filter. Generous — just eliminates
    /// obviously wrong colors (e.g. red contour vs grey reference) cheaply.
    var colorPreFilterThreshold: CGFloat = 50.0

    // MARK: - Weights for composite scoring

    /// Color is the strongest signal when matching illustration references to
    /// real-world pieces, because shape features (Hu moments, compactness,
    /// feature prints) all suffer from the viewpoint change between a 2D
    /// isometric illustration and a 3D piece seen from above in a pile.
    private let huWeight: Double = 0.35
    private let compactnessWeight: Double = 0.10
    private let featurePrintWeight: Double = 0.10
    private let colorWeight: Double = 0.45

    // MARK: - State

    private var isProcessing = false

    // MARK: - Detection

    /// Processes a single frame against multiple references and returns matching piece candidates.
    /// Returns nil if already processing (frame skip).
    ///
    /// Pipeline order is optimised for a dense pile: color pre-filter first (cheap,
    /// eliminates ~80 % of contours), then shape analysis only on survivors.
    func processFrame(
        cgImage: CGImage,
        references: [ReferenceDescriptor]
    ) -> [PieceCandidate]? {
        guard !isProcessing, !references.isEmpty else { return nil }
        isProcessing = true
        defer { isProcessing = false }

        // 1. Downsample for contour detection and color analysis.
        //    768 px keeps individual pieces at ~20-50 px in a dense pile.
        //    Using the same downsampled image for color avoids cropping the
        //    full 12 MP camera frame for every contour (major memory savings).
        let downsampled = ContourDetector.downsample(cgImage, maxDimension: 768)

        // 2. Detect contours
        guard let contours = try? ContourDetector.detect(
            in: downsampled,
            contrastAdjustment: 2.0,
            maxCount: 30
        ), !contours.isEmpty else {
            return []
        }

        var candidates: [PieceCandidate] = []

        for contour in contours {
            let bbox = contour.boundingBox
            let bboxArea = bbox.width * bbox.height

            // Skip noise (tiny) and merged blobs (huge)
            guard bboxArea > 0.0005, bboxArea < 0.10 else { continue }

            // ── Color pre-filter (cheap, eliminates most non-matching pieces) ──
            // autoreleasepool bounds CIImage/CIFilter temporaries from color extraction
            let contourColor: (lab: CIELABColor, uiColor: UIColor)? = autoreleasepool {
                ColorAnalyzer.dominantColor(of: downsampled, inNormalizedRect: bbox)
            }
            guard let contourColor else { continue }

            // Compute color distance to every reference; keep only close ones
            var refColorPairs: [(ref: ReferenceDescriptor, colorDist: CGFloat)] = []
            for ref in references {
                let dist = ref.dominantColor.distance(to: contourColor.lab)
                if dist < colorPreFilterThreshold {
                    refColorPairs.append((ref, dist))
                }
            }
            guard !refColorPairs.isEmpty else { continue }

            // ── Shape features (computed once per contour) ──
            let huMoments = ShapeDescriptor.huMoments(from: contour)
            let contourCompactness = ShapeDescriptor.compactness(of: contour)

            // Feature print (expensive — only for contours that passed color filter).
            // Uses downsampled image to avoid large allocations.
            // autoreleasepool bounds Vision request temporaries.
            let contourFP: VNFeaturePrintObservation? = autoreleasepool {
                guard let cropped = downsampled.cropping(toNormalizedRect: bbox) else {
                    return nil
                }
                return try? FeaturePrintExtractor.extract(from: cropped)
            }

            // ── Score against each color-compatible reference ──
            var bestScore: Double = 0
            var bestRef: ReferenceDescriptor?
            var bestColorDist: CGFloat = .greatestFiniteMagnitude

            for (ref, colorDist) in refColorPairs {
                // Hu similarity
                let huDist = HuMoments.distance(ref.huMoments, huMoments)
                let huSim = ShapeDescriptor.huMomentSimilarity(huDist)
                guard huSim >= huMomentThreshold else { continue }

                // Compactness similarity
                let compactSim = ShapeDescriptor.compactnessSimilarity(
                    ref.compactness, contourCompactness
                )
                guard compactSim >= compactnessThreshold else { continue }

                // Feature print: best (min distance) across reference's rotated prints
                var featurePrintSim: Double = 0.5
                if let fp = contourFP {
                    var minDist: Float = 1.0
                    for refFP in ref.featurePrints {
                        let dist = FeaturePrintExtractor.normalizedDistance(refFP, fp)
                        minDist = min(minDist, dist)
                    }
                    featurePrintSim = Double(1.0 - minDist)
                }

                // Color similarity: 1.0 at distance 0, 0.0 at pre-filter threshold
                let colorSim = max(0, 1.0 - Double(colorDist) / Double(colorPreFilterThreshold))

                // Composite score
                let score = huWeight * huSim
                    + compactnessWeight * compactSim
                    + featurePrintWeight * featurePrintSim
                    + colorWeight * colorSim

                if score > bestScore {
                    bestScore = score
                    bestRef = ref
                    bestColorDist = colorDist
                }
            }

            guard bestScore >= scoreThreshold, let matchedRef = bestRef else { continue }

            // ── Classify match type ──
            let matchType: MatchType = bestColorDist <= colorMatchThreshold
                ? .shapeAndColor
                : .shapeOnly

            candidates.append(PieceCandidate(
                boundingBox: bbox,
                matchType: matchType,
                shapeScore: bestScore,
                colorDistance: Double(bestColorDist),
                referenceID: matchedRef.id,
                displayColor: matchedRef.displayColor
            ))
        }

        return candidates
    }
}
