// Vibed/AuthManager.swift

import SwiftUI
import Combine
import Supabase

// MARK: - Supabase client
// Replace these with your project values from https://supabase.com/dashboard/project/_/settings/api

let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://uwmmrjgmzqlsrmywffsr.supabase.co")!,
    supabaseKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InV3bW1yamdtenFsc3JteXdmZnNyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU2NzIwNzUsImV4cCI6MjA5MTI0ODA3NX0.yl1JKwlbAalyHGel3xCHP4vAcuT2HvUoB2UbbsRm8p0"
)

// MARK: - AuthManager

@MainActor
final class AuthManager: ObservableObject {

    @Published var session: Session?
    @Published var isLoading = false
    @Published var errorMessage: String?

    var isLoggedIn: Bool { session != nil }
    var userName: String? { session?.user.userMetadata["user_name"]?.value as? String }
    var avatarURL: URL? {
        guard let str = session?.user.userMetadata["avatar_url"]?.value as? String else { return nil }
        return URL(string: str)
    }

    init() {
        Task { await startListening() }
    }

    // MARK: - Auth state listener

    private func startListening() async {
        for await (_, session) in supabase.auth.authStateChanges {
            self.session = session
        }
    }

    // MARK: - Sign in

    func signInWithGitHub() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let url = try supabase.auth.getOAuthSignInURL(
                provider: .github,
                redirectTo: URL(string: "vibed://auth/callback")!
            )
            await UIApplication.shared.open(url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Sign out

    func signOut() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await supabase.auth.signOut()
            session = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Handle deep link callback

    func handleCallback(url: URL) async {
        do {
            try await supabase.auth.session(from: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
