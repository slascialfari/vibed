// Vibed/VibeStore.swift

import Foundation
import Combine

@MainActor
final class VibeStore: ObservableObject {
    @Published var vibes: [Vibe]
    
    private var userVibes: [Vibe]
    private let userDefaultsKey = "userVibes"

    init() {
        userVibes = Self.loadUserVibes(with: userDefaultsKey)
        vibes = Vibe.samples + userVibes
    }

    func publish(_ vibe: Vibe) {
        userVibes.append(vibe)
        saveUserVibes()
        vibes = Vibe.samples + userVibes
    }
    
    func delete(_ vibe: Vibe) {
        if let index = userVibes.firstIndex(where: { $0.id == vibe.id }) {
            userVibes.remove(at: index)
            saveUserVibes()
            vibes = Vibe.samples + userVibes
        }
    }
    
    private static func loadUserVibes(with key: String) -> [Vibe] {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Vibe].self, from: data) {
            return decoded
        }
        return []
    }
    
    private func saveUserVibes() {
        if let data = try? JSONEncoder().encode(userVibes) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
}
