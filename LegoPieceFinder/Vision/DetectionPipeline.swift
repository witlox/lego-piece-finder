import CoreGraphics
import Vision

actor DetectionPipeline {

    // MARK: - Thresholds (tunable)

    /// Minimum Hu moment similarity to pass first filter (0…1, higher = stricter)
    var huMomentThreshold: Double = 0.3

    /// Minimum aspect ratio similarity to pass filter (0…1, higher = stricter)
    var aspectRatioThreshold: Double = 0.5

    /// Minimum weighted shape score to qualify as a match (0…1, higher = stricter)
    var shapeScoreThreshold: Double = 0.35

    /// Maximum CIELAB distance for color match
    var colorDistanceThreshold: CGFloat = 25.0

    // MARK: - Weights for hybrid scoring

    private let huWeight: Double = 0.60
    private let aspectWeight: Double = 0.25
    private let featurePrintWeight: Double = 0.15

    // MARK: - State

    private var isProcessing = false

    // MARK: - Detection

    /// Processes a single frame and returns matching piece candidates.
    /// Returns nil if already processing (frame skip).
    func processFrame(
        cgImage: CGImage,
        reference: ReferenceDescriptor
    ) -> [PieceCandidate]? {
        guard !isProcessing else { return nil }
        isProcessing = true
        defer { isProcessing = false }

        // 1. Downsample for contour detection
        let downsampled = ContourDetector.downsample(cgImage, maxDimension: 512)

        // 2. Detect contours
        guard let contours = try? ContourDetector.detect(
            in: downsampled,
            contrastAdjustment: 2.0,
            maxCount: 20
        ), !contours.isEmpty else {
            return []
        }

        var candidates: [PieceCandidate] = []

        for contour in contours {
            // Skip very small contours (noise)
            let bbox = contour.boundingBox
            let area = bbox.width * bbox.height
            guard area > 0.001 else { continue }

            // 3. Compute Hu moments and quick filter
            let huMoments = ShapeDescriptor.huMoments(from: contour)
            let huDist = HuMoments.distance(reference.huMoments, huMoments)
            let huSim = ShapeDescriptor.huMomentSimilarity(huDist)

            guard huSim >= huMomentThreshold else { continue }

            // 4. Aspect ratio filter
            let aspectRatio = ShapeDescriptor.aspectRatio(of: contour)
            let aspectSim = ShapeDescriptor.aspectRatioSimilarity(
                reference.aspectRatio, aspectRatio
            )

            guard aspectSim >= aspectRatioThreshold else { continue }

            // 5. Feature print comparison (expensive, only for survivors)
            var featurePrintSim: Double = 0.5 // default if extraction fails
            if let cropped = cgImage.cropping(toNormalizedRect: bbox),
               let fp = try? FeaturePrintExtractor.extract(from: cropped) {
                let dist = FeaturePrintExtractor.normalizedDistance(reference.featurePrint, fp)
                featurePrintSim = Double(1.0 - dist)
            }

            // 6. Weighted shape score
            let shapeScore = huWeight * huSim
                + aspectWeight * aspectSim
                + featurePrintWeight * featurePrintSim

            guard shapeScore >= shapeScoreThreshold else { continue }

            // 7. Color analysis
            let colorDistance: CGFloat
            if let colorResult = ColorAnalyzer.dominantColor(
                of: cgImage,
                inNormalizedRect: bbox
            ) {
                colorDistance = reference.dominantColor.distance(to: colorResult.lab)
            } else {
                colorDistance = .greatestFiniteMagnitude
            }

            let matchType: MatchType = colorDistance <= colorDistanceThreshold
                ? .shapeAndColor
                : .shapeOnly

            candidates.append(PieceCandidate(
                boundingBox: bbox,
                matchType: matchType,
                shapeScore: shapeScore,
                colorDistance: Double(colorDistance)
            ))
        }

        return candidates
    }
}
