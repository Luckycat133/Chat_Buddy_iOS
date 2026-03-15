import Foundation

/// Manages per-persona long-term memory records.
///
/// Responsibilities:
/// - Persist and load memories from UserDefaults
/// - Deduplicate near-identical facts (Jaccard similarity > 0.85)
/// - Apply time-decay soft-deletion on init
/// - Track `lastRecalledAt` when memories are injected into prompts
@Observable final class MemoryService {

    // MARK: - State

    private(set) var memoriesByPersona: [String: [CharacterMemory]] = [:]

    // MARK: - Constants

    static let storageKey = "memories"
    /// Survival days = importance × daysPerImportance  (e.g. importance 5 → 15 days)
    private static let daysPerImportance = 3.0
    /// Jaccard similarity threshold above which a new fact is considered a duplicate.
    private static let deduplicationThreshold = 0.85

    // MARK: - Init

    init() {
        load()
        applyDecay()
    }

    // MARK: - Public Read

    /// Active (non-forgotten) memories for a persona, newest-first.
    func memories(for personaId: String) -> [CharacterMemory] {
        (memoriesByPersona[personaId] ?? [])
            .filter { !$0.isForgotten }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Top `limit` relevant memories sorted by importance desc then recency.
    /// Updates `lastRecalledAt` on each returned record and persists.
    func relevantMemories(for personaId: String, limit: Int = 10) -> [CharacterMemory] {
        let active = memories(for: personaId)
        let top = Array(
            active.sorted {
                if $0.importance != $1.importance { return $0.importance > $1.importance }
                return $0.lastRecalledAt > $1.lastRecalledAt
            }
            .prefix(limit)
        )

        // Update lastRecalledAt for returned records
        let ids = Set(top.map { $0.id })
        let now = Date()
        if var list = memoriesByPersona[personaId] {
            for i in list.indices where ids.contains(list[i].id) {
                list[i].lastRecalledAt = now
            }
            memoriesByPersona[personaId] = list
            save()
        }

        return top
    }

    func hasMemories(for personaId: String) -> Bool {
        memories(for: personaId).isEmpty == false
    }

    // MARK: - Public Write

    /// Adds a new memory fact, skipping near-duplicates (Jaccard > 0.85).
    func addMemory(personaId: String, fact: String, category: MemoryCategory, importance: Int) {
        let active = memories(for: personaId)

        // Deduplication check
        for existing in active {
            if jaccardSimilarity(fact, existing.fact) > Self.deduplicationThreshold {
                return
            }
        }

        let now = Date()
        let memory = CharacterMemory(
            personaId: personaId,
            fact: fact,
            category: category,
            importance: max(1, min(10, importance)),
            createdAt: now,
            lastRecalledAt: now
        )

        var list = memoriesByPersona[personaId] ?? []
        list.append(memory)
        memoriesByPersona[personaId] = list
        save()
    }

    /// Soft-deletes a single memory by ID.
    func forgetMemory(id: String, personaId: String) {
        guard var list = memoriesByPersona[personaId] else { return }
        for i in list.indices where list[i].id == id {
            list[i].isForgotten = true
        }
        memoriesByPersona[personaId] = list
        save()
    }

    /// Removes all memory records for a persona (hard delete for clear-all).
    func forgetAll(for personaId: String) {
        memoriesByPersona.removeValue(forKey: personaId)
        save()
    }

    // MARK: - Persistence

    private func load() {
        let data: MemoriesData = StorageService.shared.get(Self.storageKey, default: MemoriesData(memoriesByPersona: [:]))
        memoriesByPersona = data.memoriesByPersona
    }

    private func save() {
        StorageService.shared.set(Self.storageKey, value: MemoriesData(memoriesByPersona: memoriesByPersona))
    }

    // MARK: - Time Decay

    /// Soft-deletes memories that have not been recalled within their survival window.
    private func applyDecay() {
        let now = Date()
        var changed = false
        for personaId in memoriesByPersona.keys {
            guard var list = memoriesByPersona[personaId] else { continue }
            for i in list.indices where !list[i].isForgotten {
                let survivalSeconds = Double(list[i].importance) * Self.daysPerImportance * 86400
                let elapsed = now.timeIntervalSince(list[i].lastRecalledAt)
                if elapsed > survivalSeconds {
                    list[i].isForgotten = true
                    changed = true
                }
            }
            memoriesByPersona[personaId] = list
        }
        if changed { save() }
    }

    // MARK: - Jaccard Similarity

    /// Word-level Jaccard similarity between two strings (lowercased, whitespace-tokenized).
    private func jaccardSimilarity(_ a: String, _ b: String) -> Double {
        let setA = Set(a.lowercased().split(separator: " ").map(String.init))
        let setB = Set(b.lowercased().split(separator: " ").map(String.init))
        guard !setA.isEmpty || !setB.isEmpty else { return 1.0 }
        let intersection = setA.intersection(setB).count
        let union = setA.union(setB).count
        return Double(intersection) / Double(union)
    }
}
