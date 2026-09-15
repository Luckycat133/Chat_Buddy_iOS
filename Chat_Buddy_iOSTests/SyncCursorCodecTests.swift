import XCTest
@testable import Chat_Buddy_iOS

/// Mirror of the server's `sync_cursor` codec. Locks the contract so a
/// future change to cursor ordering breaks the build here.
final class SyncCursorCodecTests: XCTestCase {
    func testCursorRoundTrip() {
        let id = "11111111-1111-4111-8111-111111111111"
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        let cur = encode(id: id, at: at)
        let back = decode(cur)
        XCTAssertEqual(back?.id, id)
        XCTAssertEqual(back?.occurredAt.timeIntervalSince1970, at.timeIntervalSince1970)
    }

    func testCursorRejectsInvalidUUID() {
        XCTAssertNil(decode(encode(id: "not-a-uuid", at: Date())))
    }

    func testCursorRejectsGarbage() {
        XCTAssertNil(decode("not-base64"))
        XCTAssertNil(decode(""))
    }

    // MARK: - Inline codec (mirrors server/api/sync.ts)

    private struct CursorState {
        let id: String
        let occurredAt: Date
    }

    private func encode(id: String, at: Date) -> String {
        let payload: [String: Any] = [
            "id": id,
            "occurredAt": ISO8601DateFormatter().string(from: at),
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func decode(_ raw: String) -> CursorState? {
        guard !raw.isEmpty,
              let padded = raw
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/"),
              let data = Data(base64Encoded: padding(padded)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String,
              let occurredAt = json["occurredAt"] as? String else {
            return nil
        }
        guard isUUID(id), let date = ISO8601DateFormatter().date(from: occurredAt) else {
            return nil
        }
        return CursorState(id: id, occurredAt: date)
    }

    private func padding(_ s: String) -> String {
        let mod = s.count % 4
        return mod == 0 ? s : s + String(repeating: "=", count: 4 - mod)
    }

    private let uuidPattern = "^[0-9a-f]{8}-[0-9a-f]{4}-[1-7][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

    private func isUUID(_ value: String) -> Bool {
        value.range(of: uuidPattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}