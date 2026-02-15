import SwiftUI
import ARKit
import RealityKit

struct ARViewContainer: UIViewRepresentable {
    let references: [ReferenceDescriptor]
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

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.references = references
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        coordinator.invalidate()
        uiView.session.pause()
        uiView.session.delegate = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            references: references,
            overlayManager: overlayManager,
            pipeline: pipeline,
            throttler: throttler
        )
    }

    class Coordinator: NSObject, ARSessionDelegate {
        var references: [ReferenceDescriptor]
        let overlayManager: HighlightOverlayManager
        let pipeline: DetectionPipeline
        let throttler: FrameThrottler

        /// Single shared CIContext — these are heavyweight and thread-safe.
        private let ciContext = CIContext()

        /// Prevents spawning new tasks while one is already in-flight.
        /// Uses UnsafeSendableBox so it can be captured safely across isolation.
        private let taskInFlight = UnsafeSendableBox(false)

        /// Set to true when the view is being torn down; prevents new Tasks.
        private let invalidated = UnsafeSendableBox(false)

        init(
            references: [ReferenceDescriptor],
            overlayManager: HighlightOverlayManager,
            pipeline: DetectionPipeline,
            throttler: FrameThrottler
        ) {
            self.references = references
            self.overlayManager = overlayManager
            self.pipeline = pipeline
            self.throttler = throttler
        }

        func invalidate() {
            invalidated.value = true
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            guard !invalidated.value,
                  throttler.shouldProcess(),
                  !taskInFlight.value else { return }

            let pixelBuffer = frame.capturedImage
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            guard let cgImage = ciContext.createCGImage(
                ciImage,
                from: ciImage.extent
            ) else { return }

            let refs = references
            let pipeline = pipeline
            let overlayManager = overlayManager
            let inFlightFlag = taskInFlight
            let invalidFlag = invalidated

            inFlightFlag.value = true

            Task {
                let candidates = await pipeline.processFrame(
                    cgImage: cgImage,
                    references: refs
                )

                await MainActor.run {
                    inFlightFlag.value = false
                    guard !invalidFlag.value else { return }
                    if let candidates {
                        overlayManager.update(candidates: candidates)
                    }
                }
            }
        }
    }
}
