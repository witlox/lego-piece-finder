import SwiftUI
import AVFoundation

struct CaptureView: View {
    @EnvironmentObject var appState: AppState
    @State private var showImagePicker = false
    @State private var capturedImage: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Text("Photograph a LEGO piece\nfrom the instruction manual")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text("Position the piece clearly in frame.\nThe illustration should be on a light background.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)

                Spacer()

                if appState.isProcessingReference {
                    ProgressView("Analyzing piece...")
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
            ImagePicker(image: $capturedImage)
        }
        .onChange(of: capturedImage) { _, newImage in
            if let image = newImage {
                appState.setReference(from: image)
                capturedImage = nil
            }
        }
    }
}

// MARK: - UIImagePickerController wrapper

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
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
                parent.image = uiImage
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
