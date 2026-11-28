import Foundation

/// The server owns the archived snapshot and all live writes. This client
/// sends only a preview token, never archive bytes or a replacement message.
struct PortableBackupMergeService {
    let http: HTTPClient

    struct Counts: Decodable, Sendable, Equatable {
        struct Group: Decodable, Sendable, Equatable {
            let insert: Int
            let skip: Int
            let conflict: Int

            var isValid: Bool { insert >= 0 && skip >= 0 && conflict >= 0 }
        }

        let conversations: Group
        let messages: Group
        let attachments: Group

        var isValid: Bool { [conversations, messages, attachments].allSatisfy(\.isValid) }
        var hasInserts: Bool { [conversations, messages, attachments].contains { $0.insert > 0 } }
    }

    struct ConflictIDs: Decodable, Sendable {
        let conversations: [String]
        let messages: [String]
        let attachments: [String]
    }

    struct Preview: Decodable, Sendable {
        let archiveSha256: String
        let previewToken: String
        let counts: Counts
        let conflicts: ConflictIDs?
        let restoredConversationIds: [String]?
        let unsupportedConversationIds: [String]?
    }

    struct Receipt: Decodable, Sendable {
        let archiveSha256: String
        let counts: Counts
        let affectedConversationIds: [String]
        let affectedConversationStarts: [String: Int]
        let restoredConversationIds: [String]?
        let restoredAt: Date?
    }

    enum MergeError: Error, Equatable {
        case archiveChanged
        case invalidPreview
        case confirmationRequired
        case stalePreview
        case resultUnconfirmed
    }

    private struct PreviewRequest: Encodable, Sendable {}
    private struct CommitRequest: Encodable, Sendable {
        let previewToken: String
        let confirm: Bool
    }

    func preview(for backup: PortableAccountBackup) async throws -> Preview {
        let plan: Preview = try await http.send(Endpoints.portableBackupMergePreview,
                                                method: "POST", body: PreviewRequest())
        guard plan.archiveSha256 == backup.sha256 else { throw MergeError.archiveChanged }
        let archive = Set((backup.account?.conversations ?? []).compactMap { UUID(uuidString: $0.id) })
        guard plan.counts.isValid, !plan.previewToken.isEmpty,
              let restored = Self.checkedIDs(plan.restoredConversationIds),
              let unsupported = Self.checkedIDs(plan.unsupportedConversationIds),
              restored.count == plan.counts.conversations.insert,
              restored.isSubset(of: archive), unsupported.isSubset(of: archive),
              restored.isDisjoint(with: unsupported) else {
            throw MergeError.invalidPreview
        }
        return plan
    }

    func commit(_ plan: Preview, confirmed: Bool) async throws -> Receipt {
        guard confirmed, plan.counts.isValid, plan.counts.hasInserts, !plan.previewToken.isEmpty else {
            throw MergeError.confirmationRequired
        }
        let receipt: Receipt
        do {
            receipt = try await http.send(Endpoints.portableBackupMergeCommit, method: "POST",
                                          body: CommitRequest(previewToken: plan.previewToken, confirm: true))
        } catch let error as APIError where error.status == 409 {
            throw MergeError.stalePreview
        } catch {
            // A transport/decode failure can happen after a server commit.
            // Do not replay blindly or claim either success or no change.
            throw MergeError.resultUnconfirmed
        }
        let affected = Set(receipt.affectedConversationIds)
        let restored = Set(receipt.restoredConversationIds ?? [])
        let expectedRestore = Set(plan.restoredConversationIds ?? [])
        guard receipt.archiveSha256 == plan.archiveSha256, receipt.counts == plan.counts,
              !affected.isEmpty, affected.count <= 100, affected.count == receipt.affectedConversationIds.count,
              let affectedUUIDs = Self.checkedIDs(receipt.affectedConversationIds),
              let restoredUUIDs = Self.checkedIDs(receipt.restoredConversationIds),
              let previewUUIDs = Self.checkedIDs(plan.restoredConversationIds),
              restoredUUIDs == previewUUIDs, restored.count == expectedRestore.count,
              restored.isSubset(of: affected),
              (receipt.restoredAt != nil) == !restored.isEmpty,
              affectedUUIDs.count == affected.count,
              Set(receipt.affectedConversationStarts.keys) == affected,
              receipt.affectedConversationStarts.values.allSatisfy({ $0 >= 0 }) else {
            throw MergeError.resultUnconfirmed
        }
        return receipt
    }

    // Optional fields preserve compatibility with the additive-only Web
    // contract. Reject duplicate IDs even when UUID case differs.
    private static func checkedIDs(_ ids: [String]?) -> Set<UUID>? {
        let ids = ids ?? []
        let normalized = Set(ids.compactMap { UUID(uuidString: $0) })
        guard ids.count <= 1_000, normalized.count == ids.count else { return nil }
        return normalized
    }
}
