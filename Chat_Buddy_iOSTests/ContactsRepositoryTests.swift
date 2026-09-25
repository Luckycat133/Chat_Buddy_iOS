import Foundation
import SwiftData
import XCTest
@testable import Chat_Buddy_iOS

/// Contacts refresh must use the server actor projection and merge it into
/// SwiftData. A cache-only refresh cannot resolve a newly-created friend.
@MainActor
final class ContactsRepositoryTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try super.setUp()
        container = try ModelContainerFactory.makeInMemory(schema: ModelContainerFactory.schema)
        context = ModelContext(container)
        ContactsFixtureURLProtocol.requestedPaths = []
        ContactsFixtureURLProtocol.responses = [
            "/v1/actors": """
            {"items":[{"id":"actor-mira","type":"character","publicName":"Mira","avatarAssetId":null,"templateId":"mira","status":"active","identityLinkedTo":null}]}
            """,
            "/v1/friend-requests": #"{"items":[]}"#,
            "/v1/relationships": #"{"items":[]}"#,
        ]
    }

    override func tearDown() async throws {
        ContactsFixtureURLProtocol.requestedPaths = []
        ContactsFixtureURLProtocol.responses = [:]
        context = nil
        container = nil
        try await super.tearDown()
    }

    func testRefreshPullsActorsAndMergesServerProjectionIntoCache() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ContactsFixtureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let environment = AppEnvironment.development
        let client = HTTPClient(
            environment: environment,
            session: AuthSession(environment: environment, service: "contacts-tests"),
            urlSession: session,
        )
        let repository = ContactsRepository(http: client, context: context)

        try await repository.refresh(myActorId: "me")

        XCTAssertEqual(ContactsFixtureURLProtocol.requestedPaths.first, "/v1/actors")
        let actor = try context.fetch(
            FetchDescriptor<CachedActor>(predicate: #Predicate { $0.id == "actor-mira" }),
        ).first
        XCTAssertEqual(actor?.publicName, "Mira")
        XCTAssertEqual(actor?.type, "character")
    }
}

private final class ContactsFixtureURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestedPaths: [String] = []
    nonisolated(unsafe) static var responses: [String: String] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        Self.requestedPaths.append(path)
        let body = Self.responses[path] ?? #"{"items":[]}"#
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"],
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
