import Foundation

/// Observable store for user-created custom personas.
///
/// Owns the persistence (load/upsert/delete) and in-memory state for custom
/// personas at `chat-buddy:personas.custom`. Extracted from `PersonaStore` so
/// the Model layer (`PersonaStore`) no longer depends on `StorageService`.
///
/// Used both as a singleton (`CustomPersonaStore.shared`) — wired into
/// `PersonaStore.customPersonasProvider` for non-view callers — and as an
/// `@Environment`-injected observable so views refresh reactively without
/// manual version counters.
@Observable final class CustomPersonaStore: StoreReloading {
    static let shared = CustomPersonaStore()

    private static let storageKey = "personas.custom"

    private(set) var customPersonas: [Persona] = []

    init() {
        load()
    }

    var customSocialCompanions: [Persona] {
        customPersonas.filter { $0.agentType == .socialCompanion }
    }

    var customTaskAgents: [Persona] {
        customPersonas.filter { $0.agentType == .taskSpecialist }
    }

    /// Reload custom personas from persisted storage. Called by
    /// `DataBackupCoordinator` after a backup import to refresh in-memory
    /// state with the freshly-written `personas.custom` data.
    func reloadFromStorage() {
        load()
    }

    /// Inserts or updates a custom persona, then persists.
    func upsert(_ persona: Persona) {
        var all = customPersonas
        if let index = all.firstIndex(where: { $0.id == persona.id }) {
            all[index] = persona
        } else {
            all.append(persona)
        }
        customPersonas = all
        save()
    }

    /// Deletes a custom persona by id, then persists.
    func delete(id: String) {
        customPersonas.removeAll { $0.id == id }
        save()
    }

    // MARK: - Persistence

    private func load() {
        customPersonas = StorageService.shared.get(Self.storageKey, default: [Persona]())
    }

    private func save() {
        StorageService.shared.set(Self.storageKey, value: customPersonas)
    }
}
