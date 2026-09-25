import AuthenticationServices
import Foundation
import os

/// Session lifecycle service per skill §"Authentication" (IOS_IMPLEMENTATION §5):
/// token refresh, multi-device revocation, and Apple credential revocation.
///
/// Extracted as a standalone type so the flow is testable and so it can be
/// wired into `CloudAppState` with two lines once the tree quiesces:
///
///     let authService = AuthService(auth: auth, http: client)
///     await authService.installUnauthorizedHandler(on: client)
///
/// On every 401 the HTTPClient invokes the installed handler exactly once:
///   1. try `POST /v1/auth/refresh` with the stored refresh token
///   2. on success the session is updated (rotating refresh supported)
///   3. on failure the session is treated as revoked: clear Keychain
///      material, disconnect realtime, and report revocation so app state
///      can route to sign-in (multi-device sign-out lands here too).
public actor AuthService {

    /// Reasons the session can end; surfaced so app state can log or
    /// tailor the sign-in screen.
    public enum RevocationReason: Sendable, Equatable {
        case refreshRejected
        case appleCredentialRevoked
        case signedOut
    }

    /// Called after local session material is cleared. App state subscribes
    /// to route to `.unauthenticated` (CloudAppState owns `stage`).
    private var onRevoked: (@Sendable (RevocationReason) async -> Void)?

    private let auth: AuthSession
    private let http: HTTPClient
    private let logger = CloudLogger.auth

    public init(auth: AuthSession, http: HTTPClient) {
        self.auth = auth
        self.http = http
    }

    /// Install the 401 hook on the shared HTTPClient.
    public func installUnauthorizedHandler(on client: HTTPClient) async {
        await client.setUnauthorizedHandler { [weak self] in
            await self?.handleUnauthorized()
        }
    }

    /// Subscribe to revocation events (multi-device sign-out, Apple
    /// credential revoked, refresh rejected).
    public func setRevocationHandler(
        _ handler: @escaping @Sendable (RevocationReason) async -> Void,
    ) {
        self.onRevoked = handler
    }

    // MARK: - Token refresh

    /// Try refreshing the access token. Returns true on success.
    /// Rotating refresh tokens (DOMAIN_ARCHITECTURE §14) update the whole
    /// stored session; non-rotating servers reuse the current material.
    @discardableResult
    public func refreshSession() async -> Bool {
        guard let refreshToken = await auth.currentRefreshToken() else {
            return false
        }
        struct Body: Codable, Sendable { let refreshToken: String }
        struct Response: Codable, Sendable {
            let accessToken: String
            let accessExpiresAt: Date
            let refreshToken: String?
        }
        do {
            let response = try await http.send(
                Endpoints.refresh,
                method: "POST",
                body: Body(refreshToken: refreshToken),
                as: Response.self,
            )
            await auth.update(
                accessToken: response.accessToken,
                accessExpiresAt: response.accessExpiresAt,
            )
            if let rotated = response.refreshToken, rotated != refreshToken {
                await auth.rotate(refreshToken: rotated)
            }
            return true
        } catch {
            logger.notice("token refresh failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// 401 path: refresh once so the client's single retry can succeed.
    /// A rejected refresh means the session is dead server-side.
    func handleUnauthorized() async {
        if await refreshSession() { return }
        await performSessionRevocation(.refreshRejected)
    }

    // MARK: - Revocation

    /// Clear local session material and notify app state. Cached rows and
    /// the legacy UserDefaults import source are intentionally NOT erased.
    public func performSessionRevocation(_ reason: RevocationReason) async {
        logger.notice("session revoked: \(String(describing: reason), privacy: .public)")
        await auth.clear()
        await onRevoked?(reason)
    }

    /// Check the Sign in with Apple credential state (§5 "revoked
    /// credential"): a user who disconnects the app in Apple ID settings
    /// must land back on sign-in instead of a stale session.
    public func checkAppleCredentialRevoked() async -> Bool {
        guard let subject = await auth.activeAppleSubject() else { return false }
        let state = await ASAuthorizationAppleIDProvider().getCredentialState(forUserID: subject)
        return state == .revoked
    }
}
