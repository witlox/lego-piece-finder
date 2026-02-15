import SwiftUI

struct ReferencePreviewCard: View {
    let descriptor: ReferenceDescriptor
    let onReset: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(uiImage: descriptor.referenceImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(descriptor.dominantUIColor), lineWidth: 2)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Reference piece")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Circle()
                    .fill(Color(descriptor.dominantUIColor))
                    .frame(width: 12, height: 12)
            }

            Spacer()

            Button {
                onReset()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}
