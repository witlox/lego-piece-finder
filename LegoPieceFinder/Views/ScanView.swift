import SwiftUI

struct ScanView: View {
    @EnvironmentObject var appState: AppState

    @StateObject private var overlayManager = HighlightOverlayManager()
    private let pipeline = DetectionPipeline()
    private let throttler = FrameThrottler(fps: 7)

    var body: some View {
        ZStack {
            ARViewContainer(
                references: appState.references,
                overlayManager: overlayManager,
                pipeline: pipeline,
                throttler: throttler
            )
            .ignoresSafeArea()

            VStack {
                ReferencePreviewStrip(
                    references: appState.references,
                    onRemove: { id in
                        overlayManager.removeAll()
                        appState.removeReference(id: id)
                    },
                    onAddMore: {
                        appState.mode = .capture
                    },
                    onResetAll: {
                        overlayManager.removeAll()
                        appState.resetToCapture()
                    }
                )
                .padding(.top, 8)

                Spacer()

                MatchLegendOverlay(references: appState.references)
                    .padding(.bottom, 24)
            }
        }
    }
}
