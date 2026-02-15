import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            switch appState.mode {
            case .capture:
                CaptureView()
            case .scanning:
                if !appState.references.isEmpty {
                    ScanView()
                } else {
                    CaptureView()
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appState.mode)
    }
}
