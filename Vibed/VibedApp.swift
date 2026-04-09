// Vibed/VibedApp.swift

import SwiftUI
import AVFoundation

@main
struct VibedApp: App {

    @StateObject private var auth = AuthManager()

    init() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Non-fatal: audio falls back to default behaviour
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)
                .onOpenURL { url in
                    // Handle vibed://auth/callback from Supabase GitHub OAuth
                    guard url.scheme == "vibed", url.host == "auth" else { return }
                    Task { await auth.handleCallback(url: url) }
                }
        }
    }
}
