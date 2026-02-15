import SwiftUI

struct MatchLegendOverlay: View {
    let references: [ReferenceDescriptor]

    var body: some View {
        VStack(spacing: 6) {
            // Per-reference color legend
            HStack(spacing: 12) {
                ForEach(Array(references.enumerated()), id: \.offset) { index, ref in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(ref.displayColor))
                            .frame(width: 10, height: 10)
                        Text("Piece \(index + 1)")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                    }
                }
            }

            // Opacity legend
            HStack(spacing: 16) {
                LegendItem(opacity: 0.55, label: "Shape + Color")
                LegendItem(opacity: 0.35, label: "Shape only")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct LegendItem: View {
    let opacity: Double
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(.white.opacity(opacity))
                .frame(width: 14, height: 10)
            Text(label)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.7))
        }
    }
}
