import SwiftUI

enum AppMode {
    case capture
    case scanning
}

@MainActor
final class AppState: ObservableObject {
    @Published var mode: AppMode = .capture
    @Published var references: [ReferenceDescriptor] = []
    @Published var isProcessingReference = false
    @Published var errorMessage: String?

    // MARK: - Color palette for distinguishing references

    private static let palette: [UIColor] = [
        UIColor(red: 0.00, green: 0.85, blue: 0.20, alpha: 1),  // green
        UIColor(red: 0.20, green: 0.60, blue: 1.00, alpha: 1),  // blue
        UIColor(red: 1.00, green: 0.60, blue: 0.00, alpha: 1),  // orange
        UIColor(red: 0.85, green: 0.20, blue: 0.85, alpha: 1),  // magenta
        UIColor(red: 1.00, green: 0.85, blue: 0.00, alpha: 1),  // yellow
        UIColor(red: 0.00, green: 0.85, blue: 0.85, alpha: 1),  // cyan
        UIColor(red: 1.00, green: 0.30, blue: 0.30, alpha: 1),  // red
        UIColor(red: 0.60, green: 0.40, blue: 1.00, alpha: 1),  // purple
    ]

    private var nextColorIndex = 0

    private func nextPaletteColor() -> UIColor {
        let color = Self.palette[nextColorIndex % Self.palette.count]
        nextColorIndex += 1
        return color
    }

    // MARK: - Multi-reference management

    func addReferences(from image: UIImage) {
        isProcessingReference = true
        errorMessage = nil

        Task.detached(priority: .userInitiated) {
            do {
                let descriptors = try ReferenceProcessor.processAll(image: image)
                await MainActor.run {
                    let colored = descriptors.map { $0.withDisplayColor(self.nextPaletteColor()) }
                    self.references.append(contentsOf: colored)
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

    func removeReference(id: UUID) {
        references.removeAll { $0.id == id }
        if references.isEmpty {
            resetToCapture()
        }
    }

    func resetToCapture() {
        mode = .capture
        references = []
        nextColorIndex = 0
        errorMessage = nil
    }
}
