// Vibed/VibeStore.swift

import Foundation
import Combine

@MainActor
final class VibeStore: ObservableObject {
    @Published var vibes: [Vibe]

    init() {
        vibes = Vibe.samples
    }

    func publish(_ vibe: Vibe) {
        vibes.append(vibe)
    }
}
