import SwiftUI
import PhotosUI

struct AICreatorView: View {

    @Binding var previewVibe: Vibe?
    let onPublish: (Vibe) -> Void

    @State private var descriptionText = ""
    @State private var refinePrompt = ""
    @State private var currentHTML = ""
    @State private var isGenerating = false
    @State private var errorMessage: String?

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?

    private var canGenerate: Bool {
        !descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasGenerated: Bool {
        !currentHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var currentVibe: Vibe? {
        guard hasGenerated else { return nil }
        return Vibe(
            id: UUID(),
            title: descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "AI Vibe" : descriptionText,
            description: descriptionText,
            htmlContent: currentHTML
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header

                promptSection

                actionButtons

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                if hasGenerated {
                    generatedPreview
                }

                Spacer(minLength: 20)
            }
            .padding(20)
        }
        .background(Color(white: 0.06).ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Create with AI")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)

            Text("Describe the vibe you want and let AI generate the HTML for you.")
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.72))
                .lineLimit(nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var promptSection: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Vibe description")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)

                TextEditor(text: $descriptionText)
                    .frame(minHeight: 120)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(14)
                    .overlay(
                        Group {
                            if descriptionText.isEmpty {
                                Text("E.g. a dramatic debate stage with neon lighting and bold headlines...")
                                    .foregroundColor(.white.opacity(0.35))
                                    .padding(EdgeInsets(top: 16, leading: 14, bottom: 0, trailing: 14))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Refine prompt")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)

                TextEditor(text: $refinePrompt)
                    .frame(minHeight: 90)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(14)
                    .overlay(
                        Group {
                            if refinePrompt.isEmpty {
                                Text("Optional refinement: more dramatic, simpler layout, brighter colors...")
                                    .foregroundColor(.white.opacity(0.35))
                                    .padding(EdgeInsets(top: 14, leading: 14, bottom: 0, trailing: 14))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    )
            }

            // ── Image reference ────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 8) {
                Text("Reference image")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)

                HStack(spacing: 12) {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label(selectedImage == nil ? "Add Image" : "Change Image",
                              systemImage: "photo.on.rectangle")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.08), in: Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
                    }

                    if let selectedImage {
                        Image(uiImage: selectedImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1))

                        Button {
                            self.selectedImage = nil
                            self.selectedPhotoItem = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }

                    Spacer()
                }
            }
            .onChange(of: selectedPhotoItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        selectedImage = image
                    }
                }
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 14) {
            Button {
                generateVibe()
            } label: {
                Label(isGenerating ? "Generating…" : "Generate Vibe", systemImage: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .cornerRadius(16)
            }
            .disabled(!canGenerate || isGenerating)

            Button {
                refineVibe()
            } label: {
                Text("Refine")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(canGenerate && hasGenerated ? .black : .white.opacity(0.45))
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(canGenerate && hasGenerated ? 1 : 0.15))
                    .cornerRadius(16)
            }
            .disabled(!canGenerate || !hasGenerated || isGenerating)
        }
    }

    private var generatedPreview: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("AI Preview")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                if let vibe = currentVibe {
                    Button {
                        previewVibe = vibe
                    } label: {
                        Text("Open Preview")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.blue)
                    }
                }
            }

            if currentHTML.isEmpty {
                Text("Your generated vibe will appear here after AI completes.")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.75))
            } else {
                VibeRenderer(vibe: currentVibe!)
                    .frame(height: 330)
                    .cornerRadius(18)
                    .shadow(color: .black.opacity(0.20), radius: 20, x: 0, y: 12)
            }

            if let vibe = currentVibe {
                Button {
                    onPublish(vibe)
                } label: {
                    Text("Publish Vibe")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white)
                        .cornerRadius(18)
                }
            }
        }
        .padding(.top, 6)
    }

    private func generateVibe() {
        guard canGenerate else { return }
        isGenerating = true
        errorMessage = nil

        let imageData = selectedImage?.jpegData(compressionQuality: 0.8)
        AnthropicService.shared.generateHTML(description: descriptionText, imageData: imageData) { result in
            DispatchQueue.main.async {
                isGenerating = false
                switch result {
                case .success(let html):
                    currentHTML = html
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func refineVibe() {
        guard canGenerate, hasGenerated else { return }
        isGenerating = true
        errorMessage = nil

        let fullDescription = descriptionText + " " + refinePrompt
        let imageData = selectedImage?.jpegData(compressionQuality: 0.8)
        AnthropicService.shared.generateHTML(description: fullDescription, imageData: imageData) { result in
            DispatchQueue.main.async {
                isGenerating = false
                switch result {
                case .success(let html):
                    currentHTML = html
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
