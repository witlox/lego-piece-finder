import UIKit
import XCTest

/// Loads test images from the test bundle's Resources folder.
enum TestImageLoader {

    /// Loads a UIImage from the test bundle.
    static func loadImage(named name: String) -> UIImage {
        let bundle = Bundle(for: ReferenceProcessorTests.self)
        let baseName = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension

        // Resources are copied flat into the bundle
        if let url = bundle.url(forResource: baseName, withExtension: ext) {
            guard let image = UIImage(contentsOfFile: url.path) else {
                XCTFail("Could not create UIImage from \(url.path)")
                return UIImage()
            }
            return image
        }

        // Try subdirectory "Resources"
        if let url = bundle.url(forResource: baseName, withExtension: ext,
                                subdirectory: "Resources") {
            guard let image = UIImage(contentsOfFile: url.path) else {
                XCTFail("Could not create UIImage from \(url.path)")
                return UIImage()
            }
            return image
        }

        XCTFail("Test image '\(name)' not found in bundle at \(bundle.bundlePath)")
        return UIImage()
    }

    /// Loads a CGImage from the test bundle.
    static func loadCGImage(named name: String) -> CGImage {
        let uiImage = loadImage(named: name)
        guard let cgImage = uiImage.cgImage else {
            XCTFail("Could not get cgImage from '\(name)'")
            return CGContext(
                data: nil, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!.makeImage()!
        }
        return cgImage
    }
}
