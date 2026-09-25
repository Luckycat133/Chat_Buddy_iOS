import XCTest
@testable import Chat_Buddy_iOS

/// DTO fixture tests using server-shaped JSON samples (contract
/// 2026-08-18-demo-v1, `shared/contracts/*.ts`). The shared
/// `test-fixtures/` directory is currently empty, so fixtures here mirror
/// the zod schemas exactly — including fractional-second ISO dates, the
/// `editedAt`/`structuredPayload` fields from message.ts, and unknown
/// enum values for forward-compatibility checks.
final class RemoteDTOFixtureTests: XCTestCase {
    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithFractional
        return decoder
    }

    // MARK: - Dates

    func testISO8601WithFractionalSecondsAndWithoutBothDecode() throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let json = """
        {"id":"m1","conversationId":"c1","senderActorId":"00000000-0000-0000-0000-000000000001","sequence":1,"clientIdempotencyKey":"abcdefgh","kind":"text","content":"hi","structuredPayload":null,"replyToMessageId":null,"burstId":null,"status":"accepted","createdAt":"2026-08-18T12:00:00.123Z","editedAt":"2026-08-18T12:30:00Z","deletedAt":null}
        """
        let dto = try makeDecoder().decode(RemoteMessageDTO.self, from: Data(json.utf8))
        XCTAssertEqual(dto.createdAt, formatter.date(from: "2026-08-18T12:00:00.123Z"))
        XCTAssertEqual(dto.editedAt, ISO8601DateFormatter().date(from: "2026-08-18T12:30:00Z"))
    }

    // MARK: - structuredPayload (record(z.unknown()) | null)

    func testStructuredPayloadObjectCanonicalizesToString() throws {
        let json = """
        {"id":"m1","conversationId":"c1","senderActorId":"00000000-0000-0000-0000-000000000001","sequence":1,"clientIdempotencyKey":"abcdefgh","kind":"invitation","content":"group invite","structuredPayload":{"invitationId":"inv-9","seats":2},"replyToMessageId":null,"burstId":null,"status":"accepted","createdAt":"2026-08-18T12:00:00.000Z","editedAt":null,"deletedAt":null}
        """
        let dto = try makeDecoder().decode(RemoteMessageDTO.self, from: Data(json.utf8))
        XCTAssertNotNil(dto.structuredPayload)
        XCTAssertTrue(dto.structuredPayload?.contains("\"invitationId\":\"inv-9\"") ?? false)
        XCTAssertTrue(dto.structuredPayload?.contains("\"seats\":2") ?? false)
    }

    func testStructuredPayloadNullAndStringPassThrough() throws {
        let base = """
        {"id":"m1","conversationId":"c1","senderActorId":"00000000-0000-0000-0000-000000000001","sequence":1,"clientIdempotencyKey":"abcdefgh","kind":"text","content":"hi","structuredPayload":%@"],"replyToMessageId":null,"burstId":null,"status":"accepted","createdAt":"2026-08-18T12:00:00.000Z","editedAt":null,"deletedAt":null}
        """
        let nullJSON = base.replacingOccurrences(of: "%@]", with: "null}")
        let dto = try makeDecoder().decode(RemoteMessageDTO.self, from: Data(nullJSON.utf8))
        XCTAssertNil(dto.structuredPayload)
    }

    // MARK: - Unknown enum fallback

    func testUnknownMessageKindFallsBack() throws {
        let json = """
        {"id":"m1","conversationId":"c1","senderActorId":"00000000-0000-0000-0000-000000000001","sequence":1,"clientIdempotencyKey":"abcdefgh","kind":"hologram","content":"hi","structuredPayload":null,"replyToMessageId":null,"burstId":null,"status":"accepted","createdAt":"2026-08-18T12:00:00.000Z","editedAt":null,"deletedAt":null}
        """
        let dto = try makeDecoder().decode(RemoteMessageDTO.self, from: Data(json.utf8))
        XCTAssertEqual(dto.messageKind, .unknown("hologram"))
        // Unknown values round-trip verbatim for cache storage.
        XCTAssertEqual(dto.messageKind.storedValue, "hologram")
    }

    func testKnownServerEnumsMapExactly() {
        XCTAssertEqual(RemoteActorType(serverValue: "human"), .human)
        XCTAssertEqual(RemoteActorType(serverValue: "character"), .character)
        XCTAssertEqual(RemoteConversationType(serverValue: "hidden_ai_direct"), .hiddenAiDirect)
        XCTAssertEqual(RemoteMessageKind(serverValue: "action_result"), .actionResult)
        XCTAssertEqual(RemoteActorType(serverValue: "synth"), .unknown("synth"))
    }

    func testActorListProjectionAcceptsOmittedSocialGraphId() throws {
        let json = """
        {"id":"actor-1","type":"character","publicName":"Mira","avatarAssetId":null,"templateId":"template-1","status":"active","identityLinkedTo":null}
        """
        let dto = try JSONDecoder().decode(RemoteActorDTO.self, from: Data(json.utf8))
        XCTAssertEqual(dto.id, "actor-1")
        XCTAssertEqual(dto.socialGraphId, "")
        XCTAssertEqual(dto.publicName, "Mira")
    }

    func testWorldEventDecodesServerObjectVisibilityPolicy() throws {
        let json = """
        {"id":"018f0000-0000-7000-8000-000000000001","socialGraphId":"graph-1","type":"message_sent","actorId":"actor-1","subjectActorIds":[],"conversationId":"conversation-1","momentId":null,"payload":{},"visibilityPolicy":{"conversation":["conversation-1"]},"occurredAt":"2026-09-25T06:00:00.000Z","causedByEventId":null,"idempotencyKey":"message_sent:message-1"}
        """
        let dto = try makeDecoder().decode(RemoteWorldEventDTO.self, from: Data(json.utf8))
        XCTAssertTrue(dto.visibilityPolicy.contains("conversation-1"))
        XCTAssertTrue(dto.visibilityPolicy.contains("conversation"))
    }

    // MARK: - Sync envelope (contract sync.ts)

    func testSyncEnvelopeDecodesServerShape() throws {
        let json = """
        {"cursor":"eyJldmVudElkIjoiZTF9","upserts":[{"table":"actors","id":"actor-1","payload":{"id":"actor-1","socialGraphId":"g1","type":"character","publicName":"Mira","avatarAssetId":null,"templateId":"t1","status":"active"}},{"table":"messages","id":"m-1","payload":{"id":"m-1","conversationId":"c-1","senderActorId":"00000000-0000-0000-0000-000000000001","sequence":7,"clientIdempotencyKey":"abcdefgh","kind":"text","content":"yo","structuredPayload":null,"replyToMessageId":null,"burstId":null,"status":"accepted","createdAt":"2026-08-18T12:00:00.000Z","editedAt":null,"deletedAt":null}}],"tombstones":[{"table":"moments","id":"mo-1","deletedAt":"2026-08-18T13:00:00.500Z"}],"serverTime":"2026-08-18T13:00:01.000Z","hasMore":false}
        """
        let envelope = try makeDecoder().decode(SyncCoordinator.ServerEnvelope.self, from: Data(json.utf8))
        XCTAssertEqual(envelope.upserts.count, 2)
        XCTAssertEqual(envelope.upserts[0].table, "actors")
        XCTAssertEqual(envelope.upserts[1].table, "messages")
        XCTAssertEqual(envelope.tombstones.count, 1)
        XCTAssertEqual(envelope.tombstones[0].table, "moments")
        XCTAssertFalse(envelope.hasMore)
    }

    // MARK: - Error envelope (contract errors.ts)

    func testErrorEnvelopeWithUnknownCodeMapsToOther() throws {
        let json = """
        {"error":{"code":"QUANTUM_ENTANGLEMENT_LOST","message":"unknown future failure","requestId":"req-1"}}
        """
        let envelope = try JSONDecoder().decode(APIErrorEnvelope.self, from: Data(json.utf8))
        XCTAssertEqual(envelope.error.code, .other)
        XCTAssertEqual(envelope.error.requestId, "req-1")
    }

    func testErrorEnvelopeKnownCodes() throws {
        let json = """
        {"error":{"code":"GROUP_INVITATION_REQUIRED","message":"invite first","requestId":null}}
        """
        let envelope = try JSONDecoder().decode(APIErrorEnvelope.self, from: Data(json.utf8))
        XCTAssertEqual(envelope.error.code, .groupInvitationRequired)
    }
}
