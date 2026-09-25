import Foundation
import os
#if canImport(UIKit)
import UIKit
#endif

/// Moments media upload per skill §"Moments / Compose":
///   - PhotosPicker selection is compressed client-side (JPEG, long edge
///     bounded, adaptive quality) before any upload.
///   - Upload goes to a server-issued signed URL; the server returns an
///     `assetId` that the moment compose body references.
///   - Progress is reported in 0...1 so the compose UI can show a bar.
///
/// REVERSIBLE ASSUMPTION: the contract specifies signed-URL media upload
/// without pinning the route; we use `POST /v1/media` → `{ assetId,
/// uploadUrl }`, then `PUT` bytes to `uploadUrl`.
public final class MediaUploadService: Sendable {
    private let http: HTTPClient
    private let session: URLSession
    private let logger = CloudLogger.capability

    public init(http: HTTPClient, session: URLSession = .shared) {
        self.http = http
        self.session = session
    }

    // MARK: Compression

    /// Max long-edge in points; keeps Moments images at display quality
    /// while shrinking payloads to a few hundred KB.
    public static let maxLongEdge: CGFloat = 1600

    /// Compress a picked image to JPEG bytes. Returns nil when the image
    /// cannot be normalized (caller shows a friendly failure state).
    @MainActor
    public static func compress(_ image: UIImage) -> Data? {
        let size = image.size
        let longEdge = max(size.width, size.height)
        var normalized = image
        if longEdge > maxLongEdge, longEdge > 0 {
            let scale = maxLongEdge / longEdge
            let newSize = CGSize(width: size.width * scale, height: size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            normalized = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        }
        // Adaptive quality: start high, drop until <= ~800 KB.
        for quality in [0.85, 0.7, 0.55, 0.4] {
            if let data = normalized.jpegData(compressionQuality: quality),
               data.count <= 800_000 {
                return data
            }
        }
        return normalized.jpegData(compressionQuality: 0.35)
    }

    // MARK: Upload

    public struct UploadResult: Sendable, Equatable {
        public let assetId: String
    }

    public func upload(
        _ data: Data,
        mimeType: String = "image/jpeg",
        progress: @escaping @Sendable (Double) -> Void,
    ) async throws -> UploadResult {
        // 1. Ask for a signed slot.
        struct RequestBody: Codable, Sendable {
            let contentType: String
            let byteCount: Int
        }
        struct SlotResponse: Codable, Sendable {
            let assetId: String
            let uploadUrl: String
        }
        let slot = try await http.send(
            Endpoints.media,
            method: "POST",
            body: RequestBody(contentType: mimeType, byteCount: data.count),
            as: SlotResponse.self,
        )

        // 2. PUT the bytes to the signed URL with progress.
        guard let url = URL(string: slot.uploadUrl) else {
            throw APIError(
                code: .internal_,
                message: "invalid signed upload url",
                status: 500,
                requestId: nil,
                details: nil,
            )
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(mimeType, forHTTPHeaderField: "content-type")
        progress(0.05)
        let (_, response) = try await session.upload(for: request, from: data)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            logger.notice("media upload failed with status \(status, privacy: .public)")
            throw APIError(
                code: .internal_,
                message: "media upload failed",
                status: status,
                requestId: nil,
                details: nil,
            )
        }
        progress(1.0)
        return UploadResult(assetId: slot.assetId)
    }
}
