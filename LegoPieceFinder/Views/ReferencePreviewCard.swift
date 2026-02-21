import SwiftUI

// MARK: - Single reference card

struct ReferencePreviewCard: View {
    let descriptor: ReferenceDescriptor
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 4) {
                Image(uiImage: descriptor.referenceImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                    .padding(4)
                    .background(Color(white: 0.94))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(descriptor.displayColor), lineWidth: 2.5)
                    )

                Circle()
                    .fill(Color(descriptor.displayColor))
                    .frame(width: 8, height: 8)
            }

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.8))
            }
            .offset(x: 8, y: -8)
        }
    }
}

// MARK: - Horizontal strip of reference cards

struct ReferencePreviewStrip: View {
    let references: [ReferenceDescriptor]
    let onRemove: (UUID) -> Void
    let onAddMore: () -> Void
    let onResetAll: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(references, id: \.id) { ref in
                    ReferencePreviewCard(descriptor: ref) {
                        onRemove(ref.id)
                    }
                }

                // Add more button
                Button {
                    onAddMore()
                } label: {
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                            .foregroundColor(.white.opacity(0.5))
                            .frame(width: 120, height: 120)
                            .overlay(
                                Image(systemName: "plus")
                                    .foregroundColor(.white.opacity(0.7))
                            )

                        Text("Add")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                // Reset all button
                if references.count > 1 {
                    Button {
                        onResetAll()
                    } label: {
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.red.opacity(0.2))
                                .frame(width: 120, height: 120)
                                .overlay(
                                    Image(systemName: "trash")
                                        .foregroundColor(.red.opacity(0.7))
                                )

                            Text("Clear")
                                .font(.caption2)
                                .foregroundColor(.red.opacity(0.7))
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}
