import UIKit
import Vision

struct ReferenceDescriptor: @unchecked Sendable {
    let id: UUID
    let huMoments: [Double]
    let compactness: Double
    let featurePrints: [VNFeaturePrintObservation]
    let dominantColor: CIELABColor
    let dominantUIColor: UIColor
    let referenceImage: UIImage
    let displayColor: UIColor

    func withDisplayColor(_ color: UIColor) -> ReferenceDescriptor {
        ReferenceDescriptor(
            id: id,
            huMoments: huMoments,
            compactness: compactness,
            featurePrints: featurePrints,
            dominantColor: dominantColor,
            dominantUIColor: dominantUIColor,
            referenceImage: referenceImage,
            displayColor: color
        )
    }
}
