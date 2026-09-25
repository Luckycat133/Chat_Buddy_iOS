import Foundation

/// One-shot importer for the legacy UserDefaults arrays used by the
/// pre-cloud `ChatStore`, `MomentsStore`, and `CharacterMemory`.
///
/// Per skill §"Replace local authority with cache":
///   - detect
///   - preview counts
///   - map persona IDs to template IDs
///   - upload normalized import batch via `/v1/account/import`
///   - show result
///   - mark migration complete
///
/// Per skill §"Never upload":
///   - do not upload stored API credentials
///   - never upload hidden AI transcripts
///   - the importer only forwards user-visible history.
public final class LegacyImporter {
    public struct LegacySnapshot: Sendable, Equatable {
        public let conversations: Int
        public let messages: Int
        public let moments: Int
        public let memories: Int
        public let contacts: Int
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Read-only inventory of legacy storage. Used to render the
    /// "Import previous data?" UI before any destructive action.
    ///
    /// The legacy runtime persists through `StorageService`, which stores
    /// JSON `Data` under `chat-buddy:`-prefixed keys ("chatSessions",
    /// "moments", "memories", "friends.groups"). The former keys here
    /// ("chatStore.conversations.count" etc.) were written by nothing in
    /// the whole project, so `hasLegacyData` was always false.
    public func snapshot() -> LegacySnapshot {
        LegacySnapshot(
            conversations: countElements("chat-buddy:chatSessions"),
            // Messages live inside each chat session payload; an exact
            // count requires decoding `ChatSession`. TODO when the upload
            // flow is implemented.
            messages: 0,
            moments: countElements("chat-buddy:moments"),
            memories: countElements("chat-buddy:memories"),
            contacts: countElements("chat-buddy:friends.groups"),
        )
    }

    /// Count top-level array/dictionary elements of a JSON payload stored
    /// in UserDefaults. Avoids coupling the importer to legacy Codable types.
    private func countElements(_ key: String) -> Int {
        guard let data = defaults.data(forKey: key) else { return 0 }
        let object = try? JSONSerialization.jsonObject(with: data, options: [])
        if let array = object as? [Any] { return array.count }
        if let dict = object as? [String: Any] { return dict.count }
        return 0
    }

    /// True when there is anything worth importing.
    public var hasLegacyData: Bool {
        let snap = snapshot()
        return snap.conversations + snap.messages + snap.moments + snap.memories + snap.contacts > 0
    }

    /// Read the raw legacy payloads for import. Returns only the four
    /// user-visible history keys; API credential keys are deliberately
    /// never read here.
    public func readLegacyPayloads() -> (
        chatSessions: Data?, moments: Data?, memories: Data?, contacts: Data?,
    ) {
        (
            defaults.data(forKey: "chat-buddy:chatSessions"),
            defaults.data(forKey: "chat-buddy:moments"),
            defaults.data(forKey: "chat-buddy:memories"),
            defaults.data(forKey: "chat-buddy:friends.groups"),
        )
    }

    /// Build the normalized upload batch. Structurally excludes
    /// credentials via `LegacyImportPayloadBuilder.sanitized`.
    public func buildImportBatch() -> LegacyImportPayloadBuilder.Batch {
        let payloads = readLegacyPayloads()
        return LegacyImportPayloadBuilder.build(
            chatSessionsData: payloads.chatSessions,
            momentsData: payloads.moments,
            memoriesData: payloads.memories,
            contactsData: payloads.contacts,
        )
    }

    /// Erase legacy keys after a successful import or an explicit "skip".
    ///
    /// CONTRACT: call this ONLY after the import flow has completed
    /// successfully (or the user explicitly declined import).
    /// The legacy keys are the import source; deleting them first loses
    /// user history forever. (signOut must NOT call this — see
    /// `CloudAppState.signOut`.) API credentials (apiConfig/apiProfiles)
    /// are intentionally preserved: never uploaded, never auto-deleted.
    public func eraseLegacyKeys() {
        let legacyKeys = [
            "chat-buddy:chatSessions",
            "chat-buddy:moments",
            "chat-buddy:memories",
            "chat-buddy:friends.groups",
            "chat-buddy:friends.meta",
        ]
        for key in legacyKeys {
            defaults.removeObject(forKey: key)
        }
        // Older ad-hoc prefixes, kept for backward safety.
        let mirror = defaults.dictionaryRepresentation()
        for key in mirror.keys where key.hasPrefix("chatStore.") || key.hasPrefix("momentsStore.")
            || key.hasPrefix("memoryStore.") || key.hasPrefix("contactsStore.") {
            defaults.removeObject(forKey: key)
        }
    }
}