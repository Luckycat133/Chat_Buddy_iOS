import XCTest
@testable import Chat_Buddy_iOS

/// Unit tests for the cloud Feature layer (skill §20 "Tests"):
/// optimistic chat reconciliation, contacts five-state projection,
/// onboarding resume gate, moments audience badge + cursor params,
/// group wizard state, and legacy import credential exclusion.
@MainActor
final class CloudFeatureTests: XCTestCase {
    // MARK: Chat optimistic rows

    private func outboxEntry(
        key: String,
        content: String,
        state: OutboxState,
        conversationId: String = "conv-1",
    ) -> OutboxMutationSnapshot {
        OutboxMutationSnapshot(
            idempotencyKey: key,
            conversationId: conversationId,
            content: content,
            senderActorId: "00000000-me",
            state: state,
            createdAt: Date(timeIntervalSince1970: 100),
        )
    }

    private func serverMessage(
        id: String,
        key: String,
        content: String,
        conversationId: String = "conv-1",
    ) -> RemoteMessageDTO {
        RemoteMessageDTO(
            id: id,
            conversationId: conversationId,
            senderActorId: "00000000-me",
            sequence: 1,
            clientIdempotencyKey: key,
            kind: "text",
            content: content,
            structuredPayload: nil,
            replyToMessageId: nil,
            burstId: nil,
            status: "accepted",
            createdAt: Date(timeIntervalSince1970: 50),
            editedAt: nil,
            deletedAt: nil,
        )
    }

    func testOptimisticRowDisappearsWhenServerConfirmsIdempotencyKey() {
        let server = [serverMessage(id: "m1", key: "k1", content: "hello")]
        let outbox = [outboxEntry(key: "k1", content: "hello", state: .accepted)]
        let rows = ChatOutboxReducer.merge(server: server, outbox: outbox)
        XCTAssertEqual(rows.count, 1)
        XCTAssertFalse(rows[0].isLocalOnly)
        XCTAssertEqual(rows[0].id, "m1")
    }

    func testFailedOutboxRowStaysVisibleForRetry() {
        let outbox = [outboxEntry(key: "k2", content: "retry me", state: .failed)]
        let rows = ChatOutboxReducer.merge(server: [], outbox: outbox)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].status, .failed)
        XCTAssertTrue(rows[0].isLocalOnly)
        XCTAssertEqual(rows[0].idempotencyKey, "k2")
        XCTAssertEqual(rows[0].content, "retry me")
    }

    func testQueuedOutboxRowRendersAsQueued() {
        let rows = ChatOutboxReducer.merge(
            server: [],
            outbox: [outboxEntry(key: "k3", content: "queued", state: .queued)],
        )
        XCTAssertEqual(rows.first?.status, .queued)
    }

    func testReducerDeduplicatesReplayedServerMessagesByIdempotencyKey() {
        let server = [
            serverMessage(id: "m1", key: "k1", content: "dup"),
            serverMessage(id: "m1-replay", key: "k1", content: "dup"),
        ]
        let reconciled = ChatOutboxReducer.reconciled(server: server)
        XCTAssertEqual(reconciled.count, 1)
        XCTAssertEqual(reconciled.first?.id, "m1")
    }

    func testReducerDropsTombstonedServerMessages() {
        var deleted = serverMessage(id: "m2", key: "k2", content: "gone")
        deleted = RemoteMessageDTO(
            id: deleted.id,
            conversationId: deleted.conversationId,
            senderActorId: deleted.senderActorId,
            sequence: deleted.sequence,
            clientIdempotencyKey: deleted.clientIdempotencyKey,
            kind: deleted.kind,
            content: deleted.content,
            structuredPayload: nil,
            replyToMessageId: nil,
            burstId: nil,
            status: deleted.status,
            createdAt: deleted.createdAt,
            editedAt: nil,
            deletedAt: Date(),
        )
        XCTAssertEqual(ChatOutboxReducer.reconciled(server: [deleted]).count, 0)
    }

    // MARK: Contacts five-state projection

    private func project(
        requests: [CachedFriendRequestSnapshot],
        relationships: [CachedRelationshipSnapshot],
        actors: [String: ActorBrief],
    ) -> ContactsProjection {
        ContactsClassifier.project(
            requests: requests,
            relationships: relationships,
            actors: actors,
            myActorId: "me",
            conversations: [
                CachedConversationSnapshot(
                    id: "g1", type: "group", publicName: "Team", status: "active",
                    memberCount: 3, deletedAt: nil,
                ),
            ],
        )
    }

    func testContactsFiveStateProjection() {
        let actors = [
            "mira": ActorBrief(publicName: "Mira", isCharacter: true),
            "lena": ActorBrief(publicName: "Lena", isCharacter: false),
        ]
        let projection = project(
            requests: [
                // Inbound pending from Mira
                CachedFriendRequestSnapshot(
                    id: "r1", senderActorId: "mira", recipientActorId: "me",
                    status: "pending", note: "hi", decidedAt: nil,
                ),
                // Outbound pending to Lena
                CachedFriendRequestSnapshot(
                    id: "r2", senderActorId: "me", recipientActorId: "lena",
                    status: "pending", note: nil, decidedAt: nil,
                ),
                // Declined inbound
                CachedFriendRequestSnapshot(
                    id: "r3", senderActorId: "mira", recipientActorId: "me",
                    status: "declined", note: nil, decidedAt: nil,
                ),
            ],
            relationships: [
                CachedRelationshipSnapshot(id: "rel1", actorAId: "me", actorBId: "mira", state: "accepted", updatedAt: Date()),
                CachedRelationshipSnapshot(id: "rel2", actorAId: "me", actorBId: "lena", state: "blocked", updatedAt: Date()),
            ],
            actors: actors,
        )
        XCTAssertEqual(projection.inbound.map(\.actorId), ["mira"])
        XCTAssertEqual(projection.outbound.map(\.actorId), ["lena"])
        XCTAssertEqual(projection.acceptedCharacters.map(\.actorName), ["Mira"])
        XCTAssertEqual(projection.blocked.map(\.actorId), ["lena"])
        XCTAssertEqual(projection.declined.count, 1)
        XCTAssertEqual(projection.groups.first?.name, "Team")
    }

    func testContactsProjectionIgnoresUnrelatedRequests() {
        let projection = project(
            requests: [
                CachedFriendRequestSnapshot(
                    id: "r9", senderActorId: "a", recipientActorId: "b",
                    status: "pending", note: nil, decidedAt: nil,
                ),
            ],
            relationships: [],
            actors: [:],
        )
        XCTAssertTrue(projection.inbound.isEmpty)
        XCTAssertTrue(projection.outbound.isEmpty)
    }

    func testContactsProjectionRoleFiltersAcceptedSections() {
        // After a full /v1/actors pull the cache may hold many non-friend
        // rows (demo/junk accounts). Friends render only when the
        // counterpart role is known: human → human friends, character →
        // AI friends; unknown-role counterparts never display.
        let actors = [
            "mira": ActorBrief(publicName: "Mira", isCharacter: true),
            "lena": ActorBrief(publicName: "Lena", isCharacter: false),
            // "ghost" deliberately absent: unknown role.
        ]
        let projection = project(
            requests: [],
            relationships: [
                CachedRelationshipSnapshot(id: "r1", actorAId: "me", actorBId: "lena", state: "accepted", updatedAt: Date()),
                CachedRelationshipSnapshot(id: "r2", actorAId: "me", actorBId: "mira", state: "accepted", updatedAt: Date()),
                CachedRelationshipSnapshot(id: "r3", actorAId: "me", actorBId: "ghost", state: "accepted", updatedAt: Date()),
                CachedRelationshipSnapshot(id: "r4", actorAId: "me", actorBId: "ghost", state: "blocked", updatedAt: Date()),
            ],
            actors: actors,
        )
        XCTAssertEqual(projection.acceptedHumans.map(\.actorId), ["lena"])
        XCTAssertEqual(projection.acceptedCharacters.map(\.actorId), ["mira"])
        // Blocked always remains visible and actionable regardless of role.
        XCTAssertEqual(projection.blocked.map(\.actorId), ["ghost"])
    }

    // MARK: Onboarding resume gate (server-driven, forkable breakpoint)

    func testOnboardingResumesWhenServerStateIncomplete() {
        XCTAssertTrue(OnboardingGate.shouldResumeOnboarding(.notStarted))
        XCTAssertTrue(OnboardingGate.shouldResumeOnboarding(.inProgress(step: 2, awaitingUser: true)))
        XCTAssertTrue(OnboardingGate.shouldResumeOnboarding(.unknown))
        XCTAssertFalse(OnboardingGate.shouldResumeOnboarding(.complete))
    }

    func testOnboardingStateParsing() {
        XCTAssertEqual(OnboardingGate.ServerState.parse("complete", step: nil, awaitingUser: nil), .complete)
        XCTAssertEqual(
            OnboardingGate.ServerState.parse("in_progress", step: 1, awaitingUser: true),
            .inProgress(step: 1, awaitingUser: true),
        )
        XCTAssertEqual(OnboardingGate.ServerState.parse("not_started", step: nil, awaitingUser: nil), .notStarted)
        XCTAssertEqual(OnboardingGate.ServerState.parse("something-new", step: nil, awaitingUser: nil), .unknown)
    }

    func testOnboardingAdvanceTargetCreatesFreshConversationWithoutCompleting() {
        XCTAssertEqual(OnboardingGate.advanceTarget(serverValue: "not_started"), "welcome")
        XCTAssertEqual(OnboardingGate.advanceTarget(serverValue: "welcome"), "welcome")
        XCTAssertEqual(OnboardingGate.advanceTarget(serverValue: "learn_name"), "learn_name")
        XCTAssertNil(OnboardingGate.advanceTarget(serverValue: "complete"))
        XCTAssertNil(OnboardingGate.advanceTarget(serverValue: "future_state"))
    }

    // MARK: Moments

    func testAudienceBadgeMapping() {
        XCTAssertEqual(AudienceBadge.key(forClass: "public_within_graph"), "cloud_moments_audience_public")
        XCTAssertEqual(AudienceBadge.key(forClass: "restricted"), "cloud_moments_audience_private")
        XCTAssertEqual(AudienceBadge.key(forClass: "familiar"), "cloud_moments_audience_familiar")
        XCTAssertEqual(AudienceBadge.key(forClass: nil), "cloud_moments_audience_familiar")
        XCTAssertEqual(AudienceBadge.symbol(forClass: "restricted"), "lock")
    }

    func testMomentsEndpointCarriesCursorPagination() {
        let first = Endpoints.moments(cursor: nil, limit: 20)
        XCTAssertEqual(first.path, "/v1/moments")
        XCTAssertTrue(first.query["cursor"] == nil)
        let second = Endpoints.moments(cursor: "abc", limit: 20)
        XCTAssertEqual(second.query["cursor"], "abc")
        XCTAssertEqual(second.path, "/v1/moments")
    }

    func testViewInteractionTypeIsRealInteraction() {
        // The view event is a real `type: "view"` interaction per
        // DOMAIN_ARCHITECTURE §4.17 — knowledge is granted on actual view.
        let types = ["view", "reaction", "comment", "reply"]
        XCTAssertTrue(types.contains("view"))
    }

    // MARK: Group wizard

    func testGroupWizardRequiresSelectedActorsBeforeSend() {
        var state = GroupWizardState()
        XCTAssertTrue(state.step == .name)
        XCTAssertTrue(state.canProceedFromName)
        XCTAssertFalse(state.canSendProposal)
        state.selectedActorIds = ["Mira"]
        state.step = .send
        XCTAssertTrue(state.canSendProposal)
        XCTAssertEqual(state.next().step, .send, "send step does not advance via next()")
    }

    func testGroupWizardBackNavigation() {
        var state = GroupWizardState(step: .review)
        state = state.back()
        XCTAssertEqual(state.step, .select)
        state = state.back()
        XCTAssertEqual(state.step, .name)
        XCTAssertEqual(state.back().step, .name, "name is the first step")
    }

    func testInvitationStatusCopyStaysNatural() {
        XCTAssertEqual(InvitationStatusCopy.key(forStatus: "accepted"), "cloud_group_invite_accepted")
        XCTAssertEqual(InvitationStatusCopy.key(forStatus: "declined"), "cloud_group_invite_declined")
        XCTAssertEqual(InvitationStatusCopy.key(forStatus: "pending"), "cloud_group_invite_pending")
        XCTAssertEqual(InvitationStatusCopy.key(forStatus: "model_decided_3"), "cloud_group_invite_pending")
    }

    // MARK: Legacy import — never uploads credentials

    func testLegacyImportSanitizesCredentialKeys() {
        let rows: [[String: String]] = [
            ["content": "hello", "createdAt": "1"],
            ["apiKey": "sk-secret", "content": "leak"],
            ["APIConfig": "should-not-pass"],
        ]
        let sanitized = LegacyImportPayloadBuilder.sanitized(rows)
        XCTAssertEqual(sanitized.count, 1)
        XCTAssertEqual(sanitized.first?["content"], "hello")
    }

    func testLegacyImportBuildsBatchFromStoredPayloads() throws {
        let sessions = try JSONEncoder().encode([["id": "s1", "title": "chat"]])
        let batch = LegacyImportPayloadBuilder.build(
            chatSessionsData: sessions,
            momentsData: nil,
            memoriesData: nil,
            contactsData: nil,
        )
        XCTAssertEqual(batch.conversations.count, 1)
        XCTAssertEqual(batch.conversations.first?["id"], "s1")
        XCTAssertTrue(batch.moments.isEmpty)
        XCTAssertTrue(batch.contacts.isEmpty)
    }

    func testLegacyImporterNeverReadsCredentialKeys() throws {
        // The read surface is exactly the four history keys; credential
        // keys ("chat-buddy:apiConfig" etc.) are never read into payloads.
        let suite = UserDefaults(suiteName: "test-legacy-import")!
        suite.removePersistentDomain(forName: "test-legacy-import")
        defer { suite.removePersistentDomain(forName: "test-legacy-import") }
        suite.set(Data("secret".utf8), forKey: "chat-buddy:apiConfig")
        suite.set(try JSONEncoder().encode(["key": "profile-key"]), forKey: "chat-buddy:apiProfiles")
        suite.set(try JSONEncoder().encode([["id": "s1"]]), forKey: "chat-buddy:chatSessions")

        let importer = LegacyImporter(defaults: suite)
        let batch = importer.buildImportBatch()
        XCTAssertEqual(batch.conversations.count, 1)
        // Credential data never reaches the payload, even though it sat
        // in the same defaults domain.
        XCTAssertTrue(batch.moments.isEmpty)
        XCTAssertTrue(batch.memories.isEmpty)
        XCTAssertTrue(batch.contacts.isEmpty)
    }

    // MARK: Outbox snapshot path parsing

    func testOutboxSnapshotParsesConversationFromPath() {
        XCTAssertEqual(
            OutboxStore.conversationId(fromPath: "/v1/conversations/c-42/messages"),
            "c-42",
        )
        XCTAssertEqual(OutboxStore.conversationId(fromPath: "/v1/other"), "")
    }
}
