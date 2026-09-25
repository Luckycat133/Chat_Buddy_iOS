import Foundation
import os

/// Account-level data operations per skill §"Data export and deletion":
///
///   - Server export: request → download archive → share sheet.
///   - Legacy import: one-time normalized batch upload built by
///     `LegacyImportPayloadBuilder` — API credentials are NEVER included
///     (they are neither read into the payload nor uploaded).
///   - Account deletion is driven by `CloudAppState.deleteAccount()`.
public struct AccountService: Sendable {
    private let http: HTTPClient
    private let session: URLSession
    private let logger = CloudLogger.capability

    public init(http: HTTPClient, session: URLSession = .shared) {
        self.http = http
        self.session = session
    }

    // MARK: Export

    public struct ExportManifest: Sendable, Equatable {
        public let downloadUrl: String?
        public let expiresAt: Date?
    }

    /// Request a server-side export of messages, Moments, contacts,
    /// user-visible memory-derived data, settings, and a media manifest.
    public func requestExport() async throws -> ExportManifest {
        struct Response: Codable, Sendable {
            let downloadUrl: String?
            let expiresAt: Date?
        }
        let response = try await http.send(
            Endpoints.accountExport,
            method: "POST",
            body: Optional<EmptyBody>.none,
            as: Response.self,
        )
        return ExportManifest(downloadUrl: response.downloadUrl, expiresAt: response.expiresAt)
    }

    /// Download the export archive bytes (presented via a share sheet).
    public func downloadExport(url: String) async throws -> Data {
        guard let url = URL(string: url) else {
            throw APIError(
                code: .internal_,
                message: "invalid export url",
                status: 500,
                requestId: nil,
                details: nil,
            )
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw APIError(
                code: .internal_,
                message: "export download failed",
                status: status,
                requestId: nil,
                details: nil,
            )
        }
        return data
    }

    // MARK: Legacy import

    public struct ImportResult: Sendable, Equatable {
        public let accepted: Bool
        public let summary: String?
    }

    /// Upload the normalized one-time legacy import batch. The batch is
    /// produced by `LegacyImportPayloadBuilder`, which structurally
    /// excludes any credential-shaped keys.
    public func importLegacyBatch(_ batch: LegacyImportPayloadBuilder.Batch) async throws -> ImportResult {
        struct Body: Codable, Sendable {
            let conversations: [[String: String]]
            let moments: [[String: String]]
            let memories: [[String: String]]
            let contacts: [[String: String]]
            let source: String
        }
        struct Response: Codable, Sendable {
            let accepted: Bool
            let summary: String?
        }
        let response = try await http.send(
            Endpoints.accountImport,
            method: "POST",
            body: Body(
                conversations: batch.conversations,
                moments: batch.moments,
                memories: batch.memories,
                contacts: batch.contacts,
                source: "ios-legacy-userdefaults",
            ),
            as: Response.self,
        )
        return ImportResult(accepted: response.accepted, summary: response.summary)
    }
}
