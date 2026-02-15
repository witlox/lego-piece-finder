import SwiftUI

enum AppMode {
    case capture
    case scanning
}

@MainActor
final class AppState: ObservableObject {
    @Published var mode: AppMode = .capture
    @Published var reference: ReferenceDescriptor?
    @Published var isProcessingReference = false
    @Published var errorMessage: String?

    func setReference(from image: UIImage) {
        isProcessingReference = true
        errorMessage = nil

        Task.detached(priority: .userInitiated) {
            do {
                let descriptor = try ReferenceProcessor.process(image: image)
                await MainActor.run {
                    self.reference = descriptor
                    self.isProcessingReference = false
                    self.mode = .scanning
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isProcessingReference = false
                }
            }
        }
    }

    func resetToCapture() {
        mode = .capture
        reference = nil
        errorMessage = nil
    }
}
