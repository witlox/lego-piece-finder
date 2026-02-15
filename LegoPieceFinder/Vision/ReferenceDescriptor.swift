import UIKit
import Vision

struct ReferenceDescriptor: @unchecked Sendable {
    let huMoments: [Double]
    let aspectRatio: Double
    let featurePrint: VNFeaturePrintObservation
    let dominantColor: CIELABColor
    let dominantUIColor: UIColor
    let referenceImage: UIImage
}
