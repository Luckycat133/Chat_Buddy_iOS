import XCTest
@testable import Chat_Buddy_iOS

final class CloudClientTests: XCTestCase {
    func testAPIErrorCodeMapsUnknownServerCodeToOther() {
        XCTAssertEqual(APIErrorCode(rawValue: "NEW_CODE_FROM_SERVER"), .other)
        XCTAssertEqual(APIErrorCode(rawValue: "UNAUTHORIZED"), .unauthorized)
        XCTAssertEqual(APIErrorCode(rawValue: "MODEL_FAILURE"), .modelFailure)
    }

    func testAPIErrorConflictAndAuthFlags() {
        let conflict = APIError(code: .conflict, message: "x", status: 409, requestId: nil, details: nil)
        XCTAssertTrue(conflict.isConflict)
        XCTAssertFalse(conflict.isAuthFailure)

        let unauthorized = APIError(code: .unauthorized, message: "x", status: 401, requestId: nil, details: nil)
        XCTAssertTrue(unauthorized.isAuthFailure)
        XCTAssertFalse(unauthorized.isRetryable)
    }

    func testAPIErrorRetryableForModelAndInternalFailures() {
        let internal_ = APIError(code: .internal_, message: "x", status: 500, requestId: nil, details: nil)
        XCTAssertTrue(internal_.isRetryable)
        let validation = APIError(code: .validationFailed, message: "x", status: 422, requestId: nil, details: nil)
        XCTAssertFalse(validation.isRetryable)
    }

    func testEndpointsConstructStablePaths() {
        XCTAssertEqual(Endpoints.devSignIn(displayName: "Mia").path, "/v1/auth/dev-signin")
        XCTAssertEqual(Endpoints.actors.path, "/v1/actors")
        XCTAssertEqual(Endpoints.actor(id: "abc").path, "/v1/actors/abc")
        XCTAssertEqual(Endpoints.messages(conversationId: "c1", cursor: 5, limit: 50).path, "/v1/conversations/c1/messages")
        XCTAssertEqual(
            Endpoints.messages(conversationId: "c1", cursor: nil, limit: 25).path,
            "/v1/conversations/c1/messages",
        )
        XCTAssertEqual(Endpoints.friendRequestDecision(id: "r1").path, "/v1/friend-requests/r1/decision")
        XCTAssertEqual(Endpoints.invitationDecision(id: "i1").path, "/v1/invitations/i1/decision")
        XCTAssertEqual(Endpoints.accountExport.path, "/v1/account/export")
        XCTAssertTrue(Endpoints.sendMessage(conversationId: "c1", idempotencyKey: "k").requiresAuth)
    }

    func testAppEnvironmentResolvesDefaults() {
        let env = AppEnvironment.resolve()
        XCTAssertFalse(env.apiBaseURL.absoluteString.isEmpty)
        XCTAssertFalse(env.realtimeURL.absoluteString.isEmpty)
    }
}