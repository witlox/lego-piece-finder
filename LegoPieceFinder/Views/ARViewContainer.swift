import SwiftUI
import ARKit
import RealityKit

struct ARViewContainer: UIViewRepresentable {
    let reference: ReferenceDescriptor
    let overlayManager: HighlightOverlayManager
    let pipeline: DetectionPipeline
    let throttler: FrameThrottler

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.frameSemantics = []
        arView.session.run(config)

        overlayManager.attach(to: arView)

        arView.session.delegate = context.coordinator

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(
            reference: reference,
            overlayManager: overlayManager,
            pipeline: pipeline,
            throttler: throttler
        )
    }

    class Coordinator: NSObject, ARSessionDelegate {
        let reference: ReferenceDescriptor
        let overlayManager: HighlightOverlayManager
        let pipeline: DetectionPipeline
        let throttler: FrameThrottler

        init(
            reference: ReferenceDescriptor,
            overlayManager: HighlightOverlayManager,
            pipeline: DetectionPipeline,
            throttler: FrameThrottler
        ) {
            self.reference = reference
            self.overlayManager = overlayManager
            self.pipeline = pipeline
            self.throttler = throttler
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            guard throttler.shouldProcess() else { return }

            let pixelBuffer = frame.capturedImage
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let context = CIContext()
            guard let cgImage = context.createCGImage(
                ciImage,
                from: ciImage.extent
            ) else { return }

            let ref = reference
            let pipeline = pipeline
            let overlayManager = overlayManager

            Task {
                guard let candidates = await pipeline.processFrame(
                    cgImage: cgImage,
                    reference: ref
                ) else { return }

                await MainActor.run {
                    overlayManager.update(candidates: candidates)
                }
            }
        }
    }
}
