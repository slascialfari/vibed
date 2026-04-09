// Vibed/VibeStore.swift

import Foundation
import Combine
import Supabase

@MainActor
final class VibeStore: ObservableObject {

    @Published var vibes: [Vibe] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    init() {
        Task { await fetchVibes() }
    }

    func fetchVibes() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            struct Row: Decodable {
                let id: UUID
                let title: String
                let description: String?
                let htmlContent: String?
                let githubRepoName: String?
                let createdAt: String

                enum CodingKeys: String, CodingKey {
                    case id, title, description
                    case htmlContent    = "html_content"
                    case githubRepoName = "github_repo_name"
                    case createdAt      = "created_at"
                }
            }

            let rows: [Row] = try await supabase
                .from("vibes")
                .select("id, title, description, html_content, github_repo_name, created_at")
                .eq("status", value: "approved")
                .order("created_at", ascending: false)
                .execute()
                .value

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            vibes = rows.map { row in
                Vibe(
                    id:              row.id,
                    title:           row.title,
                    description:     row.description ?? "",
                    htmlContent:     row.htmlContent,
                    githubRepoName:  row.githubRepoName,
                    createdAt:       formatter.date(from: row.createdAt) ?? Date()
                )
            }
        } catch {
            errorMessage = error.localizedDescription
            // Fall back to built-in samples so the feed isn't empty
            if vibes.isEmpty {
                vibes = Vibe.samples
            }
        }
    }
}
