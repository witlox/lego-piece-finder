import XCTest
import Vision
@testable import LegoPieceFinder

final class ReferenceProcessorTests: XCTestCase {

    // MARK: - Full pipeline tests (device only — feature prints need Neural Engine)

    #if !targetEnvironment(simulator)

    // -- Cutout images (close-up of the piece box only) --

    /// manual1a_cutout: Step 23 — 5 gray pieces in a 2×3 grid.
    func testManual1aCutout_FindsFivePieces() throws {
        let descriptors = try ReferenceProcessor.processAll(
            image: TestImageLoader.loadImage(named: "manual1a_cutout.jpeg"))
        XCTAssertEqual(descriptors.count, 5,
                       "Expected 5 pieces, got \(descriptors.count)")
    }

    /// manual1b_cutout: Step 43 — 3 colored pieces (blue, brown/tan, yellow).
    /// There's also a subassembly callout which should NOT be extracted.
    func testManual1bCutout_FindsThreePieces() throws {
        let descriptors = try ReferenceProcessor.processAll(
            image: TestImageLoader.loadImage(named: "manual1b_cutout.jpeg"))
        XCTAssertEqual(descriptors.count, 3,
                       "Expected 3 pieces, got \(descriptors.count)")
    }

    /// manual1c_cutout: Step 49 — 2 white pieces.
    func testManual1cCutout_FindsTwoPieces() throws {
        let descriptors = try ReferenceProcessor.processAll(
            image: TestImageLoader.loadImage(named: "manual1c_cutout.jpeg"))
        XCTAssertEqual(descriptors.count, 2,
                       "Expected 2 pieces, got \(descriptors.count)")
    }

    // -- Full-page images (manual2 series) --

    /// manual2a: 2 piece cutouts — 1 piece + 2 pieces = 3 total.
    func testManual2a_FindsThreePieces() throws {
        let descriptors = try ReferenceProcessor.processAll(
            image: TestImageLoader.loadImage(named: "manual2a.jpeg"))
        XCTAssertEqual(descriptors.count, 3,
                       "Expected 3 pieces (1+2), got \(descriptors.count)")
    }

    /// manual2b: 4 piece cutouts — 2+2+2+1 = 7 pieces total.
    func testManual2b_FindsSevenPieces() throws {
        let descriptors = try ReferenceProcessor.processAll(
            image: TestImageLoader.loadImage(named: "manual2b.jpeg"))
        XCTAssertEqual(descriptors.count, 7,
                       "Expected 7 pieces (2+2+2+1), got \(descriptors.count)")
    }

    /// manual2c: 1 piece cutout with 3 pieces.
    func testManual2c_FindsThreePieces() throws {
        let descriptors = try ReferenceProcessor.processAll(
            image: TestImageLoader.loadImage(named: "manual2c.jpeg"))
        XCTAssertEqual(descriptors.count, 3,
                       "Expected 3 pieces, got \(descriptors.count)")
    }

    /// manual2d: 1 piece cutout with 1 piece (+ 1:1 size match to ignore).
    func testManual2d_FindsOnePiece() throws {
        let descriptors = try ReferenceProcessor.processAll(
            image: TestImageLoader.loadImage(named: "manual2d.jpeg"))
        XCTAssertEqual(descriptors.count, 1,
                       "Expected 1 piece, got \(descriptors.count)")
    }

    /// manual2e: 1 piece cutout with 4 pieces.
    func testManual2e_FindsFourPieces() throws {
        let descriptors = try ReferenceProcessor.processAll(
            image: TestImageLoader.loadImage(named: "manual2e.jpeg"))
        XCTAssertEqual(descriptors.count, 4,
                       "Expected 4 pieces, got \(descriptors.count)")
    }

    /// manual2f: 1 piece cutout with 1 piece (+ minifigure subassembly to ignore).
    func testManual2f_FindsOnePiece() throws {
        let descriptors = try ReferenceProcessor.processAll(
            image: TestImageLoader.loadImage(named: "manual2f.jpeg"))
        XCTAssertEqual(descriptors.count, 1,
                       "Expected 1 piece, got \(descriptors.count)")
    }

    /// manual2g: 2 piece cutouts — 4 pieces + 2 pieces = 6 total.
    func testManual2g_FindsSixPieces() throws {
        let descriptors = try ReferenceProcessor.processAll(
            image: TestImageLoader.loadImage(named: "manual2g.jpeg"))
        XCTAssertEqual(descriptors.count, 6,
                       "Expected 6 pieces (4+2), got \(descriptors.count)")
    }

    // -- Descriptor validation --

    /// Every descriptor should have valid moments, prints, and a non-trivial image.
    func testAllCutouts_ProduceValidDescriptors() throws {
        let images = [
            "manual1a_cutout.jpeg",
            "manual1b_cutout.jpeg",
            "manual1c_cutout.jpeg",
        ]

        for name in images {
            let descriptors = try ReferenceProcessor.processAll(
                image: TestImageLoader.loadImage(named: name))
            XCTAssertFalse(descriptors.isEmpty, "\(name): no pieces found")

            for (i, desc) in descriptors.enumerated() {
                XCTAssertEqual(desc.huMoments.count, 7,
                               "\(name)[\(i)]: expected 7 Hu moments")
                XCTAssertTrue(desc.huMoments.contains { $0 != 0 },
                              "\(name)[\(i)]: Hu moments all zero")
                XCTAssertFalse(desc.featurePrints.isEmpty,
                               "\(name)[\(i)]: no feature prints")
                XCTAssertGreaterThanOrEqual(desc.compactness, 1.0,
                                            "\(name)[\(i)]: compactness < 1.0")
                XCTAssertGreaterThan(desc.referenceImage.size.width, 10,
                                     "\(name)[\(i)]: image too small")
                XCTAssertGreaterThan(desc.referenceImage.size.height, 10,
                                     "\(name)[\(i)]: image too small")
            }
        }
    }

    // -- Color validation --

    /// manual1b colored pieces should not have white-contaminated colors.
    func testManual1bCutout_ColorsAreNotWhite() throws {
        let descriptors = try ReferenceProcessor.processAll(
            image: TestImageLoader.loadImage(named: "manual1b_cutout.jpeg"))
        for (i, desc) in descriptors.enumerated() {
            XCTAssertLessThan(desc.dominantColor.L, 80,
                              "Piece[\(i)] L*=\(desc.dominantColor.L) — background contamination?")
        }
    }

    // -- Transparency validation --

    /// Reference images from contour masking should have alpha channels.
    func testCutout_ReferenceImagesHaveTransparency() throws {
        let descriptors = try ReferenceProcessor.processAll(
            image: TestImageLoader.loadImage(named: "manual1b_cutout.jpeg"))
        for (i, desc) in descriptors.enumerated() {
            guard let cg = desc.referenceImage.cgImage else {
                XCTFail("Piece[\(i)]: no cgImage"); continue
            }
            let a = cg.alphaInfo
            XCTAssertTrue(
                a == .premultipliedLast || a == .premultipliedFirst || a == .last || a == .first,
                "Piece[\(i)]: no alpha (alphaInfo=\(a.rawValue))")
        }
    }

    /// Different pieces should produce different feature prints.
    func testManual1bCutout_PiecesAreDifferent() throws {
        let descriptors = try ReferenceProcessor.processAll(
            image: TestImageLoader.loadImage(named: "manual1b_cutout.jpeg"))
        guard descriptors.count >= 2 else { XCTFail("Need >= 2 pieces"); return }
        for i in 0..<descriptors.count {
            for j in (i + 1)..<descriptors.count {
                let d = FeaturePrintExtractor.normalizedDistance(
                    descriptors[i].featurePrints[0], descriptors[j].featurePrints[0])
                // Similar shapes (e.g. blue 1×2 and yellow 1×2) can have
                // very close feature prints — only check they're not identical.
                XCTAssertGreaterThan(d, 0.001,
                                     "Pieces [\(i)] and [\(j)] identical feature prints (d=\(d))")
            }
        }
    }

    #endif

    // MARK: - Text recognition tests (work on simulator)

    /// manual1a_cutout: 5 quantity markers.
    func testManual1aCutout_FindsFiveQuantityMarkers() throws {
        let markers = findMarkers(inImage: "manual1a_cutout.jpeg")
        XCTAssertEqual(markers.count, 5,
                       "Expected 5 markers, got \(markers.count)")
    }

    /// manual1b_cutout: 3 quantity markers.
    func testManual1bCutout_FindsThreeQuantityMarkers() throws {
        let markers = findMarkers(inImage: "manual1b_cutout.jpeg")
        XCTAssertEqual(markers.count, 3,
                       "Expected 3 markers, got \(markers.count)")
    }

    /// manual1c_cutout: 2 quantity markers.
    func testManual1cCutout_FindsTwoQuantityMarkers() throws {
        let markers = findMarkers(inImage: "manual1c_cutout.jpeg")
        XCTAssertEqual(markers.count, 2,
                       "Expected 2 markers, got \(markers.count)")
    }

    /// Full-page images should at least produce detectable contours.
    /// Text recognition on full pages is unreliable due to small text,
    /// so we only verify contour detection works. The full pipeline (with
    /// marker-guided extraction) is tested on-device above.
    func testManual2FullPages_HaveDetectableContours() throws {
        let pages = ["manual2a.jpeg", "manual2b.jpeg", "manual2c.jpeg",
                     "manual2d.jpeg", "manual2e.jpeg", "manual2f.jpeg", "manual2g.jpeg"]

        for name in pages {
            let cgImage = loadAndDownsample(name)
            let contours = try ContourDetector.detect(
                in: cgImage, contrastAdjustment: 3.0, maxCount: 15)
            XCTAssertFalse(contours.isEmpty, "\(name): no contours detected")
        }
    }

    // MARK: - Contour detection in marker cells (simulator)

    /// Each quantity marker cell in manual1b should contain a dark piece contour.
    func testManual1bCutout_ContoursFoundInMarkerCells() throws {
        let cgImage = loadAndDownsample("manual1b_cutout.jpeg")
        let markers = findQuantityMarkers(in: cgImage)
        XCTAssertGreaterThanOrEqual(markers.count, 3)

        var cellsWithPieces = 0
        for marker in markers {
            let cellRect = CGRect(
                x: max(0, marker.minX - 0.08),
                y: marker.maxY,
                width: min(1.0, marker.width + 0.16),
                height: min(1.0 - marker.maxY, 0.5)
            )
            guard let cellCrop = cgImage.cropping(toNormalizedRect: cellRect) else { continue }

            if let contours = try? ContourDetector.detect(
                in: cellCrop, contrastAdjustment: 3.0, maxCount: 5
            ), contours.contains(where: { contour in
                let area = contour.boundingBox.width * contour.boundingBox.height
                guard area > 0.01, let crop = cellCrop.cropping(toNormalizedRect: contour.boundingBox) else {
                    return false
                }
                return ColorAnalyzer.dominantColor(of: crop).lab.L < 85
            }) {
                cellsWithPieces += 1
            }
        }

        XCTAssertEqual(cellsWithPieces, markers.count,
                       "Each marker cell should contain a dark contour")
    }

    // MARK: - Shape descriptor validation (simulator)

    /// Contours should produce valid Hu moments and compactness.
    func testContourShapeDescriptors_AreValid() throws {
        let cgImage = loadAndDownsample("manual1b_cutout.jpeg")
        let contours = try ContourDetector.detect(
            in: cgImage, contrastAdjustment: 3.0, maxCount: 15)

        for contour in contours {
            let area = contour.boundingBox.width * contour.boundingBox.height
            guard area > 0.001, area < 0.5 else { continue }

            let hu = ShapeDescriptor.huMoments(from: contour)
            XCTAssertEqual(hu.count, 7)
            XCTAssertTrue(hu.contains { $0 != 0 })

            let c = ShapeDescriptor.compactness(of: contour)
            XCTAssertGreaterThanOrEqual(c, 1.0)
        }
    }

    // MARK: - Helpers

    private func loadAndDownsample(_ name: String) -> CGImage {
        let uiImage = TestImageLoader.loadImage(named: name)
        let normalized = uiImage.normalizedOrientation()
        let rawCG = normalized.cgImage!
        return ContourDetector.downsample(rawCG, maxDimension: 2000)
    }

    private func findMarkers(inImage name: String) -> [CGRect] {
        findQuantityMarkers(in: loadAndDownsample(name))
    }

    private func findQuantityMarkers(in cgImage: CGImage) -> [CGRect] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        guard (try? handler.perform([request])) != nil else { return [] }

        var markers: [CGRect] = []
        for obs in request.results ?? [] {
            guard let text = obs.topCandidates(1).first?.string else { continue }
            if text.range(of: #"^\d+[x×X]$"#, options: .regularExpression) != nil {
                markers.append(obs.boundingBox)
            }
        }
        return markers
    }
}
