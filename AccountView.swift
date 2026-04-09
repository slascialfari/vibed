// Vibed/AccountView.swift

import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var store: VibeStore
    @State private var editingVibe: Vibe?

    var body: some View {
        ZStack {
            Color(white: 0.05).ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your account")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white)
                        Text("Swipe right to return to the feed")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                .padding(.bottom, 14)

                Divider()
                    .background(Color.white.opacity(0.1))
                    .padding(.horizontal, 20)

                if store.createdVibes.isEmpty {
                    VStack(spacing: 14) {
                        Text("No saved Vibes yet")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Create a new Vibe or return to the main feed to begin.")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.72))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .padding(.top, 80)
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 12) {
                            ForEach(store.createdVibes) { vibe in
                                accountRow(for: vibe)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 30)
                    }
                }
            }
        }
        .sheet(item: $editingVibe) { vibe in
            EditVibeView(vibe: vibe) { updated in
                store.update(updated)
                editingVibe = nil
            }
        }
    }

    @ViewBuilder
    private func accountRow(for vibe: Vibe) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(vibe.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(vibe.description.isEmpty ? "No description" : vibe.description)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(2)
                }
                Spacer()
                Button {
                    editingVibe = vibe
                } label: {
                    Text("Edit")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }
            }

            HStack {
                Text(vibe.createdAt, style: .date)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Button(role: .destructive) {
                    store.delete(vibe)
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}

struct EditVibeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var description: String
    @State private var htmlContent: String
    let original: Vibe
    let onSave: (Vibe) -> Void

    init(vibe: Vibe, onSave: @escaping (Vibe) -> Void) {
        self.original = vibe
        self.onSave = onSave
        _title = State(initialValue: vibe.title)
        _description = State(initialValue: vibe.description)
        _htmlContent = State(initialValue: vibe.htmlContent)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Group {
                    TextField("Title", text: $title)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundColor(.white)

                    TextField("Description", text: $description)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundColor(.white)

                    TextEditor(text: $htmlContent)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                        .frame(minHeight: 200)
                }
                .padding(.horizontal, 16)

                Spacer()
            }
            .navigationTitle("Edit Vibe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let updated = Vibe(id: original.id, title: title, description: description, htmlContent: htmlContent, createdAt: original.createdAt)
                        onSave(updated)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || htmlContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .background(Color.black.ignoresSafeArea())
        }
    }
}

#Preview {
    AccountView().environmentObject(VibeStore())
}
