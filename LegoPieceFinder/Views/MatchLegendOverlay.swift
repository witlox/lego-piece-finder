import SwiftUI

struct MatchLegendOverlay: View {
    var body: some View {
        HStack(spacing: 16) {
            LegendItem(color: .orange, label: "Shape match")
            LegendItem(color: .green, label: "Shape + Color")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }
}

private struct LegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.white)
        }
    }
}
