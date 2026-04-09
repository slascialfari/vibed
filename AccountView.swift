// Vibed/AccountView.swift

import SwiftUI
import AuthenticationServices
import CryptoKit
import Combine

// MARK: - Auth0 Configuration
// 1. Create an application at https://manage.auth0.com
// 2. Set Application Type to "Native"
// 3. Add "com.stefano.vibed://callback" to Allowed Callback URLs
// 4. Fill in your values below

private let auth0Domain    = "YOUR_DOMAIN.auth0.com"   // e.g. "myapp.us.auth0.com"
private let auth0ClientId  = "YOUR_CLIENT_ID"
private let redirectURI    = "com.stefano.vibed://callback"
private let callbackScheme = "com.stefano.vibed"

// MARK: - Branch

struct Branch: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
}

private let availableBranches: [Branch] = [
    Branch(id: "games",       name: "Games",       icon: "gamecontroller"),
    Branch(id: "music",       name: "Music",       icon: "music.note"),
    Branch(id: "art",         name: "Art",         icon: "paintpalette"),
    Branch(id: "interactive", name: "Interactive", icon: "hand.tap"),
    Branch(id: "experiments", name: "Experiments", icon: "flask"),
]

// MARK: - AuthManager

@MainActor
final class AuthManager: ObservableObject {
    @Published var isLoggedIn = false
    @Published var userName: String?
    @Published var userEmail: String?
    @Published var isLoading = false
    @Published var loginError: String?

    private var accessToken: String?
    private var authSession: ASWebAuthenticationSession?
    private var contextProvider: ContextProvider?

    func login() async {
        isLoading  = true
        loginError = nil
        defer { isLoading = false }

        // PKCE: generate code verifier + challenge
        var rawBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, rawBytes.count, &rawBytes)
        let codeVerifier  = Data(rawBytes).base64URLEncoded()
        let codeChallenge = Data(SHA256.hash(data: Data(codeVerifier.utf8))).base64URLEncoded()
        let state         = UUID().uuidString

        var comps = URLComponents()
        comps.scheme = "https"
        comps.host   = auth0Domain
        comps.path   = "/authorize"
        comps.queryItems = [
            URLQueryItem(name: "response_type",         value: "code"),
            URLQueryItem(name: "client_id",             value: auth0ClientId),
            URLQueryItem(name: "redirect_uri",          value: redirectURI),
            URLQueryItem(name: "scope",                 value: "openid profile email"),
            URLQueryItem(name: "state",                 value: state),
            URLQueryItem(name: "code_challenge",        value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]

        guard let authURL = comps.url else { return }

        do {
            let callbackURL: URL = try await withCheckedThrowingContinuation { cont in
                let provider = ContextProvider(window: keyWindow())
                self.contextProvider = provider

                let session = ASWebAuthenticationSession(
                    url: authURL,
                    callbackURLScheme: callbackScheme
                ) { url, error in
                    if let error { cont.resume(throwing: error) }
                    else if let url { cont.resume(returning: url) }
                }
                session.presentationContextProvider = provider
                session.prefersEphemeralWebBrowserSession = false
                self.authSession = session
                session.start()
            }

            let cbComps = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
            guard
                let code          = cbComps?.queryItems?.first(where: { $0.name == "code" })?.value,
                let returnedState = cbComps?.queryItems?.first(where: { $0.name == "state" })?.value,
                returnedState == state
            else {
                loginError = "Invalid authorization response."
                return
            }

            try await exchangeCode(code: code, codeVerifier: codeVerifier)

        } catch ASWebAuthenticationSessionError.canceledLogin {
            // User cancelled — no error displayed
        } catch {
            loginError = "Login failed. Please try again."
        }
    }

    private func exchangeCode(code: String, codeVerifier: String) async throws {
        guard let url = URL(string: "https://\(auth0Domain)/oauth/token") else {
            throw URLError(.badURL)
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = [
            "grant_type=authorization_code",
            "client_id=\(auth0ClientId)",
            "code=\(code)",
            "redirect_uri=\(redirectURI)",
            "code_verifier=\(codeVerifier)",
        ].joined(separator: "&").data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: req)

        guard
            let json  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let token = json["access_token"] as? String
        else { throw URLError(.badServerResponse) }

        accessToken = token
        try await fetchUserInfo(token: token)
    }

    private func fetchUserInfo(token: String) async throws {
        guard let url = URL(string: "https://\(auth0Domain)/userinfo") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: req)

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            userName   = json["name"]  as? String
            userEmail  = json["email"] as? String
            isLoggedIn = true
        }
    }

    func logout() {
        isLoggedIn   = false
        userName     = nil
        userEmail    = nil
        accessToken  = nil
        loginError   = nil
    }

    private func keyWindow() -> UIWindow {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first
            ?? UIWindow(windowScene: UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }.first!)
    }

    private final class ContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
        let window: UIWindow
        init(window: UIWindow) { self.window = window }
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { window }
    }
}

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - AccountView

struct AccountView: View {

    @EnvironmentObject private var store: VibeStore
    @StateObject private var auth = AuthManager()

    // Submission form state
    @State private var vibeTitle     = ""
    @State private var vibeCode      = ""
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
                loginView
            }

            // Preview overlay
            if let vibe = previewVibe {
                PreviewView(
                    vibe: vibe,
                    onBack: { previewVibe = nil },
                    onPublish: { previewVibe = nil }  // submit flow handles publishing
                )
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: previewVibe != nil)
    }

    // MARK: - Login view

    private var loginView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 14) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.white.opacity(0.35))

                Text("Creator Account")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Sign in to submit vibes\nfor the feed")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: 10) {
                if let err = auth.loginError {
                    Text(err)
                        .font(.system(size: 13))
                        .foregroundStyle(.red.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }

                Button {
                    Task { await auth.login() }
                } label: {
                    HStack(spacing: 10) {
                        if auth.isLoading {
                            ProgressView().tint(.black)
                        } else {
                            Image(systemName: "person.badge.key.fill")
                            Text("Sign in with Auth0")
                        }
                    }
                    .font(.system(size: 16, weight: .semibold))
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
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(auth.userName ?? "Creator")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                    if let email = auth.userEmail {
                        Text(email)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                Spacer()
                Button("Sign out") { auth.logout() }
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, 20)
            .padding(.top, 64)
            .padding(.bottom, 18)

            Divider().background(Color.white.opacity(0.1))

            // ── Submission form ────────────────────────────────────────────
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {

                    // Title
                    VStack(alignment: .leading, spacing: 6) {
                        label("Vibe title")
                        TextField("Name your vibe...", text: $vibeTitle)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white)
                            .tint(.white)
                    }

                    divider

                    // Code
                    VStack(alignment: .leading, spacing: 6) {
                        label("HTML / JS source")
                        TextEditor(text: $vibeCode)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white)
                            .tint(.white)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 130, maxHeight: 180)
                            .padding(10)
                            .background(Color.white.opacity(0.05),
                                        in: RoundedRectangle(cornerRadius: 10))
                    }

                    divider

                    // Branch selector
                    VStack(alignment: .leading, spacing: 10) {
                        label("Select branch")
                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible())],
                            spacing: 10
                        ) {
                            ForEach(availableBranches) { branch in
                                branchButton(branch)
                            }
                        }
                    }

                    divider

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
                                .foregroundStyle(canSubmit ? .black : .black.opacity(0.35))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(
                                    Color.white.opacity(canSubmit ? 1 : 0.25),
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

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.4))
            .textCase(.uppercase)
            .kerning(0.5)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
    }

    // MARK: - Submit

    private func submitVibe() {
        // In production: POST vibe + branch to your backend moderation API.
        // The vibe is NOT added to the local feed — it's pending approval.
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
