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

// MARK: - GitHubRepo

struct GitHubRepo: Identifiable, Decodable {
    let id: Int
    let name: String
    let fullName: String
    let description: String?
    let htmlUrl: String
    let owner: Owner

    struct Owner: Decodable {
        let login: String
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description, owner
        case fullName = "full_name"
        case htmlUrl  = "html_url"
    }
}

// MARK: - VibeSubmission (Supabase insert payload)

private struct VibeSubmission: Encodable {
    let title: String
    let htmlContent: String
    let githubRepoUrl: String
    let githubRepoName: String
    let category: String
    let status: String
    let creatorId: UUID

    enum CodingKeys: String, CodingKey {
        case title
        case htmlContent    = "html_content"
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
    @State private var previewVibe: Vibe?
    @State private var showSubmitted   = false

    // Repo picker state
    @State private var repos: [GitHubRepo]  = []
    @State private var isLoadingRepos       = false
    @State private var repoError: String?
    @State private var selectedRepo: GitHubRepo?

    // HTML fetch state
    @State private var fetchedHTML: String?
    @State private var isFetchingHTML = false
    @State private var htmlError: String?

    // Submit state
    @State private var isSubmitting  = false
    @State private var submitError: String?

    private var resolvedTitle: String {
        let t = vibeTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? (selectedRepo?.name ?? "Untitled") : t
    }

    private var canPreview: Bool { fetchedHTML != nil }
    private var canSubmit: Bool  { fetchedHTML != nil && selectedBranch != nil && !isSubmitting }

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

                        // HTML fetch status
                        if isFetchingHTML {
                            HStack(spacing: 8) {
                                ProgressView().tint(.white)
                                Text("Fetching index.html…")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        } else if let err = htmlError {
                            Text(err)
                                .font(.system(size: 12))
                                .foregroundStyle(.orange.opacity(0.8))
                        } else if fetchedHTML != nil, let repo = selectedRepo {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.system(size: 13))
                                Text("index.html loaded from \(repo.name)")
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
                            if let html = fetchedHTML {
                                previewVibe = Vibe(title: resolvedTitle,
                                                  description: "",
                                                  htmlContent: html)
                            }
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
            selectedRepo = repo
            fetchedHTML  = nil
            htmlError    = nil
            Task { await fetchIndexHTML(for: repo) }
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

            var request = URLRequest(url: URL(string: "https://api.github.com/user/repos?sort=updated&per_page=50")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

            let (data, _) = try await URLSession.shared.data(for: request)
            repos = try JSONDecoder().decode([GitHubRepo].self, from: data)
        } catch {
            repoError = error.localizedDescription
        }
    }

    // MARK: - Fetch index.html

    private func fetchIndexHTML(for repo: GitHubRepo) async {
        isFetchingHTML = true
        htmlError      = nil
        defer { isFetchingHTML = false }

        let owner = repo.owner.login
        let name  = repo.name

        // Try main branch first, fall back to master
        let urls = [
            "https://raw.githubusercontent.com/\(owner)/\(name)/main/index.html",
            "https://raw.githubusercontent.com/\(owner)/\(name)/master/index.html",
        ]

        for urlString in urls {
            guard let url = URL(string: urlString) else { continue }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, http.statusCode == 200,
                   let html = String(data: data, encoding: .utf8) {
                    fetchedHTML = html
                    return
                }
            } catch {
                continue
            }
        }

        htmlError = "No index.html found in \(repo.name) (tried main and master branches)"
    }

    // MARK: - Submit to Supabase

    private func submitVibe() async {
        guard let html = fetchedHTML,
              let repo = selectedRepo,
              let branch = selectedBranch else { return }

        isSubmitting = true
        submitError  = nil
        defer { isSubmitting = false }

        do {
            let session   = try await supabase.auth.session
            let creatorId = session.user.id

            let payload = VibeSubmission(
                title:           resolvedTitle,
                htmlContent:     html,
                githubRepoUrl:   repo.htmlUrl,
                githubRepoName:  repo.fullName,
                category:        branch.id,
                status:          "pending",
                creatorId:       creatorId
            )

            try await supabase
                .from("vibes")
                .insert(payload)
                .execute()

            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                showSubmitted  = true
                vibeTitle      = ""
                selectedRepo   = nil
                fetchedHTML    = nil
                selectedBranch = nil
                previewVibe    = nil
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
