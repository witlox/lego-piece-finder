import SwiftUI

struct ScanView: View {
    @EnvironmentObject var appState: AppState
    let reference: ReferenceDescriptor

    @StateObject private var overlayManager = HighlightOverlayManager()
    private let pipeline = DetectionPipeline()
    private let throttler = FrameThrottler(fps: 7)

    var body: some View {
        ZStack {
            ARViewContainer(
                reference: reference,
                overlayManager: overlayManager,
                pipeline: pipeline,
                throttler: throttler
            )
            .ignoresSafeArea()

            VStack {
                ReferencePreviewCard(descriptor: reference) {
                    overlayManager.removeAll()
                    appState.resetToCapture()
                }
                .padding(.top, 8)

                Spacer()

                MatchLegendOverlay()
                    .padding(.bottom, 24)
            }
        }
    }
}
