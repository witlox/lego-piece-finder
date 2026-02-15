import SwiftUI
import AVFoundation

struct CaptureView: View {
    @EnvironmentObject var appState: AppState
    @State private var showImagePicker = false
    @State private var capturedImage: UIImage?

    /// The crop guide rectangle as a fraction of the image (x, y, width, height).
    /// Centered, 85% width, 35% height — fits typical callout box aspect ratios.
    static let cropFraction = CGRect(x: 0.075, y: 0.25, width: 0.85, height: 0.35)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Text("Position the piece box\ninside the guide")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text("The grey/colored box with pieces and\nquantity markers (1x, 2x, ...)")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)

                Spacer()

                if appState.isProcessingReference {
                    ProgressView("Analyzing pieces...")
                        .tint(.white)
                        .foregroundColor(.white)
                } else {
                    Button {
                        showImagePicker = true
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.white)
                                .frame(width: 72, height: 72)
                            Circle()
                                .stroke(.white, lineWidth: 3)
                                .frame(width: 82, height: 82)
                        }
                    }
                }

                if let error = appState.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }

                Spacer()
                    .frame(height: 40)
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(
                image: $capturedImage,
                cropFraction: Self.cropFraction
            )
        }
        .onChange(of: capturedImage) { _, newImage in
            if let image = newImage {
                appState.addReferences(from: image)
                capturedImage = nil
            }
        }
    }
}

// MARK: - UIImagePickerController wrapper with crop guide overlay

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    let cropFraction: CGRect
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator

        // Add the guide overlay on top of the camera preview.
        // The frame must be set explicitly — UIImagePickerController
        // does not auto-size the overlay view.
        let screenBounds = UIScreen.main.bounds
        let overlay = CropGuideOverlay(cropFraction: cropFraction)
        overlay.frame = screenBounds
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.isUserInteractionEnabled = false
        picker.cameraOverlayView = overlay

        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let uiImage = info[.originalImage] as? UIImage {
                // Crop to the guide rectangle
                parent.image = uiImage.cropped(toFraction: parent.cropFraction)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Camera overlay with crop guide rectangle

/// A transparent overlay that draws a guide rectangle on the camera preview.
/// The area outside the rectangle is dimmed; the rectangle itself is clear
/// with a white border, showing the user where to position the callout box.
final class CropGuideOverlay: UIView {
    let cropFraction: CGRect

    init(cropFraction: CGRect) {
        self.cropFraction = cropFraction
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Resize to match the camera preview area (full screen minus controls).
        // UIImagePickerController sets the overlay frame automatically.
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        let guideRect = CGRect(
            x: cropFraction.origin.x * rect.width,
            y: cropFraction.origin.y * rect.height,
            width: cropFraction.width * rect.width,
            height: cropFraction.height * rect.height
        )

        // Dim everything outside the guide
        ctx.setFillColor(UIColor.black.withAlphaComponent(0.45).cgColor)
        ctx.fill(rect)

        // Clear the guide area
        ctx.clear(guideRect)

        // Draw white border around the guide
        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.setLineWidth(2.0)
        ctx.stroke(guideRect.insetBy(dx: -1, dy: -1))

        // Corner accents (thicker, shorter lines at each corner)
        let cornerLength: CGFloat = 20
        let cornerWidth: CGFloat = 4
        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.setLineWidth(cornerWidth)
        ctx.setLineCap(.round)

        let r = guideRect
        let corners: [(CGPoint, CGPoint, CGPoint, CGPoint)] = [
            // top-left
            (CGPoint(x: r.minX, y: r.minY + cornerLength),
             CGPoint(x: r.minX, y: r.minY),
             CGPoint(x: r.minX, y: r.minY),
             CGPoint(x: r.minX + cornerLength, y: r.minY)),
            // top-right
            (CGPoint(x: r.maxX - cornerLength, y: r.minY),
             CGPoint(x: r.maxX, y: r.minY),
             CGPoint(x: r.maxX, y: r.minY),
             CGPoint(x: r.maxX, y: r.minY + cornerLength)),
            // bottom-left
            (CGPoint(x: r.minX, y: r.maxY - cornerLength),
             CGPoint(x: r.minX, y: r.maxY),
             CGPoint(x: r.minX, y: r.maxY),
             CGPoint(x: r.minX + cornerLength, y: r.maxY)),
            // bottom-right
            (CGPoint(x: r.maxX - cornerLength, y: r.maxY),
             CGPoint(x: r.maxX, y: r.maxY),
             CGPoint(x: r.maxX, y: r.maxY),
             CGPoint(x: r.maxX, y: r.maxY - cornerLength)),
        ]

        for (a, b, c, d) in corners {
            ctx.move(to: a)
            ctx.addLine(to: b)
            ctx.strokePath()
            ctx.move(to: c)
            ctx.addLine(to: d)
            ctx.strokePath()
        }

        // Label
        let label = "Position piece box here" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.white.withAlphaComponent(0.8),
            .font: UIFont.systemFont(ofSize: 15, weight: .medium),
        ]
        let labelSize = label.size(withAttributes: attrs)
        let labelPoint = CGPoint(
            x: guideRect.midX - labelSize.width / 2,
            y: guideRect.maxY + 12
        )
        label.draw(at: labelPoint, withAttributes: attrs)
    }
}

// MARK: - UIImage cropping to fractional rect

extension UIImage {
    /// Crops the image to a rectangle specified as fractions of the image size.
    /// The fraction rect uses UIKit coordinates (origin at top-left).
    func cropped(toFraction fraction: CGRect) -> UIImage {
        let normalized = normalizedOrientation()
        guard let cg = normalized.cgImage else { return self }

        let w = CGFloat(cg.width)
        let h = CGFloat(cg.height)

        let pixelRect = CGRect(
            x: (fraction.origin.x * w).rounded(.down),
            y: (fraction.origin.y * h).rounded(.down),
            width: (fraction.width * w).rounded(.down),
            height: (fraction.height * h).rounded(.down)
        )

        guard pixelRect.width >= 1, pixelRect.height >= 1,
              let cropped = cg.cropping(to: pixelRect) else {
            return self
        }

        return UIImage(cgImage: cropped)
    }
}
