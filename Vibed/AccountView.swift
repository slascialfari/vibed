// Vibed/AccountView.swift

import SwiftUI

// MARK: - Branch

struct Branch: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
}

let availableBranches: [Branch] = [
    Branch(id: "games",       name: "Games",       icon: "gamecontroller"),
    Branch(id: "music",       name: "Music",       icon: "music.note"),
    Branch(id: "art",         name: "Art",         icon: "paintpalette"),
    Branch(id: "interactive", name: "Interactive", icon: "hand.tap"),
    Branch(id: "experiments", name: "Experiments", icon: "flask"),
]

// MARK: - AccountView

struct AccountView: View {

    @EnvironmentObject private var store: VibeStore
    @EnvironmentObject private var auth: AuthManager

    @State private var vibeTitle      = ""
    @State private var vibeCode       = ""
    @State private var selectedBranch: Branch?
    @State private var previewVibe: Vibe?
    @State private var showSubmitted  = false

    private var codeIsEmpty: Bool {
        vibeCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSubmit: Bool {
        !codeIsEmpty && selectedBranch != nil && previewVibe != nil
    }

    private var resolvedTitle: String {
        let t = vibeTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Untitled" : t
    }

    var body: some View {
        ZStack {
            Color(white: 0.06).ignoresSafeArea()

            if auth.isLoggedIn {
                loggedInView
            } else {
                signInView
            }

            if let vibe = previewVibe {
                PreviewView(
                    vibe: vibe,
                    onBack: { previewVibe = nil },
                    onPublish: { previewVibe = nil }
                )
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: previewVibe != nil)
        .animation(.easeInOut(duration: 0.2), value: auth.isLoggedIn)
    }

    // MARK: - Sign-in view

    private var signInView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 14) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.white.opacity(0.3))

                Text("Creator Account")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Connect GitHub to submit\nvibes for the feed")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: 12) {
                if let err = auth.errorMessage {
                    Text(err)
                        .font(.system(size: 13))
                        .foregroundStyle(.red.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }

                Button {
                    Task { await auth.signInWithGitHub() }
                } label: {
                    HStack(spacing: 10) {
                        if auth.isLoading {
                            ProgressView().tint(.black)
                        } else {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Connect GitHub")
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
                }
                .disabled(auth.isLoading)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 60)
        }
    }

    // MARK: - Logged-in view

    private var loggedInView: some View {
        VStack(spacing: 0) {

            // ── Header ─────────────────────────────────────────────────────
            HStack(alignment: .center, spacing: 12) {
                // Avatar
                AsyncImage(url: auth.avatarURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.white.opacity(0.1)
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(auth.userName ?? "GitHub User")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Connected via GitHub")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                }

                Spacer()

                Button {
                    Task { await auth.signOut() }
                } label: {
                    Text("Disconnect")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 64)
            .padding(.bottom, 18)

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            // ── Submission form ────────────────────────────────────────────
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {

                    // Title
                    VStack(alignment: .leading, spacing: 6) {
                        sectionLabel("Vibe title")
                        TextField("Name your vibe...", text: $vibeTitle)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white)
                            .tint(.white)
                    }

                    rowDivider

                    // Code
                    VStack(alignment: .leading, spacing: 6) {
                        sectionLabel("HTML / JS source")
                        TextEditor(text: $vibeCode)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white)
                            .tint(.white)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 130, maxHeight: 200)
                            .padding(10)
                            .background(Color.white.opacity(0.05),
                                        in: RoundedRectangle(cornerRadius: 10))
                    }

                    rowDivider

                    // Branch selector
                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel("Select branch")
                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible())],
                            spacing: 10
                        ) {
                            ForEach(availableBranches) { branch in
                                branchButton(branch)
                            }
                        }
                    }

                    rowDivider

                    // Actions
                    HStack(spacing: 10) {
                        Button {
                            previewVibe = Vibe(title: resolvedTitle,
                                              description: "",
                                              htmlContent: vibeCode)
                        } label: {
                            Text("Preview")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(codeIsEmpty ? .white.opacity(0.25) : .white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(
                                    Color.white.opacity(codeIsEmpty ? 0.04 : 0.1),
                                    in: RoundedRectangle(cornerRadius: 12)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(codeIsEmpty ? 0.06 : 0.16),
                                                lineWidth: 1)
                                )
                        }
                        .disabled(codeIsEmpty)

                        Button { submitVibe() } label: {
                            Text("Submit for Approval")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(canSubmit ? .black : .black.opacity(0.3))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(
                                    Color.white.opacity(canSubmit ? 1 : 0.2),
                                    in: RoundedRectangle(cornerRadius: 12)
                                )
                        }
                        .disabled(!canSubmit)
                    }

                    if showSubmitted {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Submitted for review! We'll notify you when it's live.")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        .padding(14)
                        .background(Color.green.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 12))
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 50)
            }
        }
    }

    // MARK: - Branch button

    private func branchButton(_ branch: Branch) -> some View {
        let selected = selectedBranch?.id == branch.id
        return Button { selectedBranch = branch } label: {
            HStack(spacing: 8) {
                Image(systemName: branch.icon)
                    .font(.system(size: 14))
                Text(branch.name)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(selected ? .black : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                selected ? Color.white : Color.white.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 10)
            )
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.4))
            .textCase(.uppercase)
            .kerning(0.5)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
    }

    // MARK: - Submit

    private func submitVibe() {
        // POST vibe + branch to your backend moderation API.
        // Vibe is NOT added to local feed — pending approval.
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            showSubmitted  = true
            vibeTitle      = ""
            vibeCode       = ""
            selectedBranch = nil
            previewVibe    = nil
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            withAnimation { showSubmitted = false }
        }
    }
}
