import XCTest
import Vision
@testable import LegoPieceFinder

final class ContourMaskTests: XCTestCase {

    // MARK: - Contour masking basics

    /// Masking a cropped piece image with its contour should produce an image
    /// with both transparent and opaque pixels.
    func testMaskedWithContour_ProducesTransparentBackground() throws {
        let cgImage = TestImageLoader.loadCGImage(named: "manual1b_cutout.jpeg")
        let downsampled = ContourDetector.downsample(cgImage, maxDimension: 2000)

        let contours = try ContourDetector.detect(
            in: downsampled, contrastAdjustment: 3.0, maxCount: 15
        )
        XCTAssertFalse(contours.isEmpty, "Should detect contours")

        // Find a piece-sized contour (not the box border)
        guard let contour = contours.first(where: {
            let area = $0.boundingBox.width * $0.boundingBox.height
            return area > 0.01 && area < 0.40
        }) else {
            XCTFail("No piece-sized contour found")
            return
        }

        let bbox = contour.boundingBox
        guard let crop = downsampled.cropping(toNormalizedRect: bbox) else {
            XCTFail("Could not crop bounding box")
            return
        }

        // Test transparent background masking
        guard let masked = crop.maskedWithContour(contour, bbox: bbox) else {
            XCTFail("maskedWithContour returned nil")
            return
        }

        XCTAssertEqual(masked.width, crop.width, "Masked image width should match crop")
        XCTAssertEqual(masked.height, crop.height, "Masked image height should match crop")

        // Check alpha info — should have alpha
        let alphaInfo = masked.alphaInfo
        XCTAssertTrue(
            alphaInfo == .premultipliedLast || alphaInfo == .premultipliedFirst ||
            alphaInfo == .last || alphaInfo == .first,
            "Masked image should have alpha channel (got \(alphaInfo.rawValue))"
        )

        // Verify mix of transparent and opaque pixels
        let (transparent, opaque) = countTransparency(in: masked)
        XCTAssertGreaterThan(transparent, 0,
                             "Should have transparent pixels (background)")
        XCTAssertGreaterThan(opaque, 0,
                             "Should have opaque pixels (piece)")
    }

    /// Masking with a white background should produce no transparent pixels.
    func testMaskedWithContour_WhiteBackground_NoTransparency() throws {
        let cgImage = TestImageLoader.loadCGImage(named: "manual1b_cutout.jpeg")
        let downsampled = ContourDetector.downsample(cgImage, maxDimension: 2000)

        let contours = try ContourDetector.detect(
            in: downsampled, contrastAdjustment: 3.0, maxCount: 15
        )

        guard let contour = contours.first(where: {
            let area = $0.boundingBox.width * $0.boundingBox.height
            return area > 0.01 && area < 0.40
        }) else {
            XCTFail("No piece-sized contour found")
            return
        }

        let bbox = contour.boundingBox
        guard let crop = downsampled.cropping(toNormalizedRect: bbox) else {
            XCTFail("Could not crop bounding box")
            return
        }

        let whiteBg = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        guard let masked = crop.maskedWithContour(contour, bbox: bbox, backgroundColor: whiteBg) else {
            XCTFail("maskedWithContour (white bg) returned nil")
            return
        }

        // With a solid background, alphaInfo should be noneSkipLast
        XCTAssertEqual(masked.alphaInfo, .noneSkipLast,
                       "White-bg masked image should not have alpha")
    }

    /// Masking should not crash or return nil for very small contours.
    func testMaskedWithContour_SmallContour_DoesNotCrash() throws {
        let cgImage = TestImageLoader.loadCGImage(named: "manual1a_cutout.jpeg")
        let downsampled = ContourDetector.downsample(cgImage, maxDimension: 2000)

        let contours = try ContourDetector.detect(
            in: downsampled, contrastAdjustment: 3.0, maxCount: 15
        )

        // Try masking every contour — none should crash
        for contour in contours {
            let bbox = contour.boundingBox
            guard let crop = downsampled.cropping(toNormalizedRect: bbox) else { continue }
            // This should not crash even for tiny contours
            _ = crop.maskedWithContour(contour, bbox: bbox)
        }
    }

    // MARK: - averageOpaqueColor tests

    /// averageOpaqueColor on a contour-masked image should return a non-white color
    /// for a colored piece (blue piece from manual1b).
    func testAverageOpaqueColor_ReturnsNonWhiteForColoredPiece() throws {
        let cgImage = TestImageLoader.loadCGImage(named: "manual1b_cutout.jpeg")
        let downsampled = ContourDetector.downsample(cgImage, maxDimension: 2000)

        let contours = try ContourDetector.detect(
            in: downsampled, contrastAdjustment: 3.0, maxCount: 15
        )

        // Find a dark (piece) contour
        var foundColoredPiece = false
        for contour in contours {
            let bbox = contour.boundingBox
            let area = bbox.width * bbox.height
            guard area > 0.01, area < 0.40 else { continue }

            guard let crop = downsampled.cropping(toNormalizedRect: bbox) else { continue }
            guard let masked = crop.maskedWithContour(contour, bbox: bbox) else { continue }

            if let result = ColorAnalyzer.averageOpaqueColor(of: masked) {
                // For a colored piece, L should not be near-white
                if result.lab.L < 80 {
                    foundColoredPiece = true
                    // Should have reasonable color values
                    XCTAssertGreaterThan(result.lab.L, 0,
                                         "L* should be positive")
                    break
                }
            }
        }
        XCTAssertTrue(foundColoredPiece,
                      "Should find at least one colored piece with L < 80")
    }

    /// averageOpaqueColor on a fully transparent image should return nil.
    func testAverageOpaqueColor_ReturnsNilForFullyTransparent() {
        guard let ctx = CGContext(
            data: nil, width: 10, height: 10,
            bitsPerComponent: 8, bytesPerRow: 40,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            XCTFail("Could not create context")
            return
        }
        // Context is initialized to all zeros (fully transparent)
        guard let transparent = ctx.makeImage() else {
            XCTFail("Could not make image")
            return
        }

        let result = ColorAnalyzer.averageOpaqueColor(of: transparent)
        XCTAssertNil(result, "Should return nil for fully transparent image")
    }

    /// averageOpaqueColor vs dominantColor on a masked image — averageOpaqueColor
    /// should be less contaminated by white background.
    func testAverageOpaqueColor_LessWhiteThanDominantColor() throws {
        let cgImage = TestImageLoader.loadCGImage(named: "manual1b_cutout.jpeg")
        let downsampled = ContourDetector.downsample(cgImage, maxDimension: 2000)

        let contours = try ContourDetector.detect(
            in: downsampled, contrastAdjustment: 3.0, maxCount: 15
        )

        for contour in contours {
            let bbox = contour.boundingBox
            let area = bbox.width * bbox.height
            guard area > 0.01, area < 0.40 else { continue }

            guard let crop = downsampled.cropping(toNormalizedRect: bbox) else { continue }
            guard let masked = crop.maskedWithContour(contour, bbox: bbox) else { continue }
            guard let opaqueColor = ColorAnalyzer.averageOpaqueColor(of: masked) else { continue }

            let fullColor = ColorAnalyzer.dominantColor(of: crop)

            // averageOpaqueColor should give a darker (less white) result
            // than dominantColor on the raw crop which includes white background
            XCTAssertLessThanOrEqual(
                opaqueColor.lab.L, fullColor.lab.L + 5, // small tolerance
                "averageOpaqueColor L*=\(opaqueColor.lab.L) should not be " +
                "lighter than dominantColor L*=\(fullColor.lab.L)"
            )
            return // Just test the first valid contour
        }
    }

    // MARK: - Helpers

    private func countTransparency(in cgImage: CGImage) -> (transparent: Int, opaque: Int) {
        let w = cgImage.width
        let h = cgImage.height
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return (0, 0)
        }
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        guard let data = ctx.data else { return (0, 0) }
        let pixels = data.bindMemory(to: UInt8.self, capacity: w * h * 4)

        var transparent = 0
        var opaque = 0
        for p in 0..<(w * h) {
            if pixels[p * 4 + 3] == 0 {
                transparent += 1
            } else {
                opaque += 1
            }
        }
        return (transparent, opaque)
    }
}
