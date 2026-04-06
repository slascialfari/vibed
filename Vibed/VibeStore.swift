// Vibed/VibeStore.swift

import Foundation
import Combine

@MainActor
final class VibeStore: ObservableObject {
    @Published var vibes: [Vibe]
    
    private var userVibes: [Vibe]
    private let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!

    var createdVibes: [Vibe] {
        userVibes
    }

    init() {
        userVibes = Self.loadUserVibes(from: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!)
        vibes = Vibe.samples + userVibes
    }

    func publish(_ vibe: Vibe) {
        userVibes.append(vibe)
        saveVibe(vibe)
        vibes = Vibe.samples + userVibes
    }
    
    func update(_ vibe: Vibe) {
        guard let index = userVibes.firstIndex(where: { $0.id == vibe.id }) else { return }
        userVibes[index] = vibe
        saveVibe(vibe)
        vibes = Vibe.samples + userVibes
    }

    func delete(_ vibe: Vibe) {
        if let index = userVibes.firstIndex(where: { $0.id == vibe.id }) {
            userVibes.remove(at: index)
            deleteVibeFile(vibe)
            vibes = Vibe.samples + userVibes
        }
    }
    
    private static func loadUserVibes(from documentsURL: URL) -> [Vibe] {
        let fileManager = FileManager.default
        do {
            let urls = try fileManager.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)
            let jsonURLs = urls.filter { $0.pathExtension == "json" }
            var vibes: [Vibe] = []
            for url in jsonURLs {
                if let data = try? Data(contentsOf: url),
                   let vibe = try? JSONDecoder().decode(Vibe.self, from: data) {
                    vibes.append(vibe)
                }
            }
            return vibes.sorted(by: { $0.createdAt < $1.createdAt })
        } catch {
            return []
        }
    }
    
    private func saveVibe(_ vibe: Vibe) {
        let url = documentsURL.appendingPathComponent("\(vibe.id.uuidString).json")
        if let data = try? JSONEncoder().encode(vibe) {
            try? data.write(to: url)
        }
    }
    
    private func deleteVibeFile(_ vibe: Vibe) {
        let url = documentsURL.appendingPathComponent("\(vibe.id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
    }
}
