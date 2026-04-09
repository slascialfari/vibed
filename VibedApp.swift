// Vibed/VibedApp.swift

import SwiftUI
import AVFoundation

@main
struct VibedApp: App {

    init() {
        // Configure the audio session so that Web Audio API inside WKWebView
        // can produce sound regardless of the silent/vibrate switch, and without
        // interrupting other apps' audio.
        //
        // Without this the default .soloAmbient session silences all WebView
        // audio whenever the ringer switch is off — the most common cause of
        // Web Audio silence in WKWebView apps.
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Non-fatal: audio will fall back to default silent-switch behaviour
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
