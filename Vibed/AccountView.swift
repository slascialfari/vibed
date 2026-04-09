// Vibed/AccountView.swift

import SwiftUI
import Supabase

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

// MARK: - VibeSubmission (Supabase insert payload)
// html_content is intentionally omitted — GitHub-backed vibes store the repo
// reference instead. The column accepts NULL for repo-backed entries.

private struct VibeSubmission: Encodable {
    let title: String
    let githubRepoUrl: String
    let githubRepoName: String
    let category: String
    let status: String
    let creatorId: UUID

    enum CodingKeys: String, CodingKey {
        case title
        case githubRepoUrl  = "github_repo_url"
        case githubRepoName = "github_repo_name"
        case category
        case status
        case creatorId      = "creator_id"
    }
}

// MARK: - AccountView

struct AccountView: View {

    @EnvironmentObject private var store: VibeStore
    @EnvironmentObject private var auth: AuthManager

    // Form state
    @State private var vibeTitle       = ""
    @State private var selectedBranch: Branch?
    @State private var showPreview     = false
    @State private var showSubmitted   = false

    // Repo picker state
    @State private var repos: [GitHubRepo]  = []
    @State private var isLoadingRepos       = false
    @State private var repoError: String?
    @State private var selectedRepo: GitHubRepo?

    // Repo download state (replaces single html fetch)
    @State private var fetchedFileURL: URL?
    @State private var isFetchingRepo  = false
    @State private var repoFetchError: String?

    // Submit state
    @State private var isSubmitting  = false
    @State private var submitError: String?

    private var resolvedTitle: String {
        let t = vibeTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? (selectedRepo?.name ?? "Untitled") : t
    }

    private var canPreview: Bool { fetchedFileURL != nil }
    private var canSubmit: Bool  { fetchedFileURL != nil && selectedBranch != nil && !isSubmitting }

    // The Vibe passed to PreviewView (no htmlContent; VibeRenderer uses fileURL)
    private var previewVibe: Vibe {
        Vibe(
            title: resolvedTitle,
            description: "",
            githubRepoName: selectedRepo?.fullName
        )
    }

    var body: some View {
        ZStack {
            Color(white: 0.06).ignoresSafeArea()

            if auth.isLoggedIn {
                loggedInView
            } else {
                signInView
            }

            if showPreview, let url = fetchedFileURL {
                PreviewView(
                    vibe: previewVibe,
                    fileURL: url,
                    onBack: { showPreview = false },
                    onPublish: {
                        showPreview = false
                        Task { await submitVibe() }
                    }
                )
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showPreview)
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

                Text("Connect GitHub to publish\nyour repos to the feed")
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

            // ── Header ────────────────────────────────────────────────────
            HStack(alignment: .center, spacing: 12) {
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

            // ── Form ──────────────────────────────────────────────────────
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

                    // Repo picker
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            sectionLabel("Pick a GitHub Repo")
                            Spacer()
                            Button {
                                Task { await fetchRepos() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                        }

                        if isLoadingRepos {
                            HStack {
                                ProgressView().tint(.white)
                                Text("Fetching repos…")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)

                        } else if let err = repoError {
                            Text(err)
                                .font(.system(size: 13))
                                .foregroundStyle(.red.opacity(0.8))

                        } else if repos.isEmpty {
                            Button {
                                Task { await fetchRepos() }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.down.circle")
                                        .font(.system(size: 14))
                                    Text("Load my repos")
                                        .font(.system(size: 14, weight: .medium))
                                }
                                .foregroundStyle(.white.opacity(0.6))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.white.opacity(0.06),
                                            in: RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                            }

                        } else {
                            VStack(spacing: 8) {
                                ForEach(repos) { repo in
                                    repoRow(repo)
                                }
                            }
                        }

                        // Download status
                        if isFetchingRepo {
                            HStack(spacing: 8) {
                                ProgressView().tint(.white)
                                Text("Downloading repo…")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        } else if let err = repoFetchError {
                            Text(err)
                                .font(.system(size: 12))
                                .foregroundStyle(.orange.opacity(0.8))
                        } else if fetchedFileURL != nil, let repo = selectedRepo {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.system(size: 13))
                                Text("Ready to preview: \(repo.name)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                    }

                    rowDivider

                    // Branch selector
                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel("Select category")
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
                            showPreview = true
                        } label: {
                            Text("Preview")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(canPreview ? .white : .white.opacity(0.25))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(
                                    Color.white.opacity(canPreview ? 0.1 : 0.04),
                                    in: RoundedRectangle(cornerRadius: 12)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(canPreview ? 0.16 : 0.06),
                                                lineWidth: 1)
                                )
                        }
                        .disabled(!canPreview)

                        Button {
                            Task { await submitVibe() }
                        } label: {
                            Group {
                                if isSubmitting {
                                    ProgressView().tint(.black)
                                } else {
                                    Text("Submit for Approval")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(canSubmit ? .black : .black.opacity(0.3))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(
                                Color.white.opacity(canSubmit ? 1 : 0.2),
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                        }
                        .disabled(!canSubmit)
                    }

                    if let err = submitError {
                        Text(err)
                            .font(.system(size: 13))
                            .foregroundStyle(.red.opacity(0.8))
                            .multilineTextAlignment(.center)
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

    // MARK: - Repo row

    private func repoRow(_ repo: GitHubRepo) -> some View {
        let isSelected = selectedRepo?.id == repo.id
        return Button {
            selectedRepo   = repo
            fetchedFileURL = nil
            repoFetchError = nil
            Task { await downloadRepo(repo) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.3))

                VStack(alignment: .leading, spacing: 3) {
                    Text(repo.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                    if let desc = repo.description, !desc.isEmpty {
                        Text(desc)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                Color.white.opacity(isSelected ? 0.1 : 0.04),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(isSelected ? 0.2 : 0.08), lineWidth: 1)
            )
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

    // MARK: - Fetch repos

    private func fetchRepos() async {
        isLoadingRepos = true
        repoError      = nil
        defer { isLoadingRepos = false }

        do {
            let session = try await supabase.auth.session
            guard let token = session.providerToken else {
                repoError = "GitHub token unavailable — please reconnect."
                return
            }
            repos = try await GitHubRepoService.shared.listRepos(token: token)
        } catch {
            repoError = error.localizedDescription
        }
    }

    // MARK: - Download repo as ZIP

    private func downloadRepo(_ repo: GitHubRepo) async {
        isFetchingRepo = true
        repoFetchError = nil
        defer { isFetchingRepo = false }

        do {
            let token = (try? await supabase.auth.session)?.providerToken
            let url = try await GitHubRepoService.shared.fetchRepoContents(
                owner: repo.owner.login,
                repo: repo.name,
                token: token
            )
            fetchedFileURL = url
        } catch {
            repoFetchError = error.localizedDescription
        }
    }

    // MARK: - Submit to Supabase

    private func submitVibe() async {
        guard fetchedFileURL != nil,
              let repo = selectedRepo,
              let branch = selectedBranch else { return }

        isSubmitting = true
        submitError  = nil
        defer { isSubmitting = false }

        do {
            let session   = try await supabase.auth.session
            let creatorId = session.user.id

            let payload = VibeSubmission(
                title:          resolvedTitle,
                githubRepoUrl:  repo.htmlUrl,
                githubRepoName: repo.fullName,
                category:       branch.id,
                status:         "pending",
                creatorId:      creatorId
            )

            try await supabase
                .from("vibes")
                .insert(payload)
                .execute()

            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                showSubmitted  = true
                vibeTitle      = ""
                selectedRepo   = nil
                fetchedFileURL = nil
                selectedBranch = nil
                showPreview    = false
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(6))
                withAnimation { showSubmitted = false }
            }
        } catch {
            submitError = error.localizedDescription
        }
    }
}
