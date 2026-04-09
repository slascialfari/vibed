// Vibed/PreviewView.swift

import SwiftUI

struct PreviewView: View {
    let vibe: Vibe

    /// Local file URL for multi-file GitHub repo vibes.
    /// When set, VibeRenderer loads from disk instead of vibe.htmlContent.
    var fileURL: URL? = nil

    var onBack: () -> Void
    var onPublish: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VibeRenderer(vibe: vibe, fileURL: fileURL, isInteractive: true)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Back button — top left
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.55), in: Circle())
                    }
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 60)

                Spacer()

                // Publish button — bottom center
                Button(action: onPublish) {
                    Text("Submit for Approval")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 48)
                        .padding(.vertical, 14)
                        .background(.white, in: Capsule())
                }
                .padding(.bottom, 52)
            }
        }
    }
}
