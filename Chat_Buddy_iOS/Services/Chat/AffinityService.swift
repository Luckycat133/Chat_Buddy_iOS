import Foundation

/// Tracks per-persona affinity scores (0–100), enforces a 5-minute chat cooldown,
/// and persists scores to UserDefaults.
@Observable final class AffinityService {

    /// Current affinity scores keyed by persona ID.
    private(set) var scores: [String: Int] = [:]

    /// In-memory cooldown tracker — not persisted across launches.
    private var cooldowns: [String: Date] = [:]

    private static let cooldownDuration: TimeInterval = 5 * 60   // 5 minutes
    private static let storageKey = "chat-buddy:intimacy"

    init() { load() }

    // MARK: - Public

    /// Current score for a persona (0–100).
    func score(for personaId: String) -> Int {
        scores[personaId] ?? 0
    }

    /// Current affinity level for a persona.
    func level(for personaId: String) -> AffinityLevel {
        AffinityLevel.level(for: score(for: personaId))
    }

    /// Directly boosts intimacy by a given amount (for gifts).
    func addBoost(_ amount: Int, for personaId: String) {
        let current = scores[personaId] ?? 0
        scores[personaId] = min(current + amount, 100)
        save()
    }

    /// Increments the score by 1 if the 5-minute cooldown has expired.
    /// Safe to call on every message send — the cooldown prevents spam.
    func addChatIntimacy(for personaId: String) {
        let now = Date()
        let lastGain = cooldowns[personaId] ?? .distantPast
        guard now.timeIntervalSince(lastGain) >= Self.cooldownDuration else { return }

        cooldowns[personaId] = now
        let current = scores[personaId] ?? 0
        scores[personaId] = min(current + 1, 100)
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([String: Int].self, from: data) else { return }
        scores = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(scores) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
