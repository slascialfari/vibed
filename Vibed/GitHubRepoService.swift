// Vibed/GitHubRepoService.swift

import Foundation
import ZIPFoundation

// MARK: - GitHubRepo model (shared between AccountView and the service)

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

// MARK: - GitHubRepoService

/// Downloads GitHub repos as ZIP archives, extracts them, and serves index.html URLs.
/// Results are cached on disk (1-hour TTL) and in memory.
actor GitHubRepoService {

    static let shared = GitHubRepoService()

    private var urlCache: [String: URL] = [:]   // "owner/repo" → local index.html URL
    private let cacheTTL: TimeInterval = 3600   // 1 hour

    // MARK: - Public API

    /// Returns a local file:// URL pointing to index.html inside the extracted repo.
    /// Reads from disk/memory cache if fresh; downloads and extracts otherwise.
    func fetchRepoContents(owner: String, repo: String, token: String?) async throws -> URL {
        let key = "\(owner)/\(repo)"

        // 1. In-memory cache hit
        if let cached = urlCache[key] {
            return cached
        }

        // 2. Filesystem cache hit (fresh within TTL)
        let cacheDir = Self.cacheDir(owner: owner, repo: repo)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: cacheDir.path),
           let created = attrs[.creationDate] as? Date,
           Date().timeIntervalSince(created) < cacheTTL,
           let indexURL = Self.findIndexHTML(in: cacheDir) {
            urlCache[key] = indexURL
            return indexURL
        }

        // 3. Download + extract
        let tempZip = try await downloadZipball(owner: owner, repo: repo, token: token)

        try? FileManager.default.removeItem(at: cacheDir)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try FileManager.default.unzipItem(at: tempZip, to: cacheDir)

        guard let indexURL = Self.findIndexHTML(in: cacheDir) else {
            throw GitHubRepoError.noIndexHTML(repo)
        }

        urlCache[key] = indexURL
        return indexURL
    }

    /// Lists the authenticated user's GitHub repos (most recently updated first).
    func listRepos(token: String) async throws -> [GitHubRepo] {
        var req = URLRequest(url: URL(string: "https://api.github.com/user/repos?sort=updated&per_page=50")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode([GitHubRepo].self, from: data)
    }

    // MARK: - Private helpers

    private func downloadZipball(owner: String, repo: String, token: String?) async throws -> URL {
        for branch in ["main", "master"] {
            let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/zipball/\(branch)")!
            var req = URLRequest(url: url)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            if let token {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            if let (tempURL, response) = try? await URLSession.shared.download(for: req),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                return tempURL
            }
        }
        throw GitHubRepoError.downloadFailed(repo)
    }

    private static func cacheDir(owner: String, repo: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("vibed-cache", isDirectory: true)
            .appendingPathComponent("\(owner)-\(repo)", isDirectory: true)
    }

    /// Searches recursively for the first index.html inside dir.
    /// GitHub ZIP archives extract with a prefix folder (owner-repo-sha/),
    /// so we must search rather than assume a fixed path.
    private static func findIndexHTML(in dir: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsPackageDescendants, .skipsHiddenFiles]
        ) else { return nil }
        for case let file as URL in enumerator where file.lastPathComponent == "index.html" {
            return file
        }
        return nil
    }
}

// MARK: - Errors

enum GitHubRepoError: LocalizedError {
    case downloadFailed(String)
    case noIndexHTML(String)

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let repo):
            return "Could not download \(repo) (tried main and master branches)"
        case .noIndexHTML(let repo):
            return "No index.html found in \(repo)"
        }
    }
}
