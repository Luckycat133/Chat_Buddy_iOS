import AuthenticationServices
import Foundation
import os

/// Session lifecycle service per skill §"Authentication" (IOS_IMPLEMENTATION §5):
/// token refresh, multi-device revocation, and Apple credential revocation.
///
/// One refresh serves the protected requests rejected with the same token.
/// Transport failures preserve the offline session; a rejected refresh
/// delegates to the account owner's teardown.
public actor AuthService {

    /// Reasons the session can end; surfaced so app state can log or
    /// tailor the sign-in screen.
    public enum RevocationReason: Sendable, Equatable {
        case refreshRejected
        case appleCredentialRevoked
        case signedOut
    }

    private var onRevoked: (@Sendable (RevocationReason) async -> Void)?

    private enum Outcome: Sendable {
        case refreshed
        case rejected
        case unavailable
    }

    private let auth: AuthSession
    private let http: HTTPClient
    private let lifetime: CloudAccountLifetime?
    private var inFlight: Task<Outcome, Never>?
    private var revoked = false
    private let logger = CloudLogger.auth

    public init(auth: AuthSession, http: HTTPClient, lifetime: CloudAccountLifetime? = nil) {
        self.auth = auth
        self.http = http
        self.lifetime = lifetime
    }

    /// Install the 401 hook on the shared HTTPClient.
    public func installUnauthorizedHandler(on client: HTTPClient) async {
        await client.setUnauthorizedHandler { [weak self] rejectedToken in
            await self?.handleUnauthorized(rejectedToken: rejectedToken) ?? false
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
        guard let current = await auth.currentSession() else { return false }
        return await handleUnauthorized(rejectedToken: current.accessToken)
    }

    private func refresh(_ previous: SessionSnapshot) async -> Outcome {
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
                body: Body(refreshToken: previous.refreshToken),
                as: Response.self,
            )
            guard lifetime?.isActive != false, !response.accessToken.isEmpty,
                  response.accessExpiresAt > Date()
            else { return .unavailable }
            let applied = await auth.applyRefresh(
                previous: previous,
                accessToken: response.accessToken,
                refreshToken: response.refreshToken ?? previous.refreshToken,
                expiresAt: response.accessExpiresAt,
            )
            return applied ? .refreshed : .unavailable
        } catch let error as APIError where error.status == 401 || error.code == .unauthorized {
            return .rejected
        } catch {
            return .unavailable
        }
    }

    func handleUnauthorized(rejectedToken: String) async -> Bool {
        guard let current = await auth.currentSession(), !revoked, lifetime?.isActive != false else {
            return false
        }
        if current.accessToken != rejectedToken { return true }
        if let inFlight { return await inFlight.value == .refreshed }
        let task = Task { await refresh(current) }
        inFlight = task
        let outcome = await task.value
        inFlight = nil
        if outcome == .rejected { await performSessionRevocation(.refreshRejected) }
        return outcome == .refreshed
    }

    // MARK: - Revocation

    public func performSessionRevocation(_ reason: RevocationReason) async {
        guard !revoked, lifetime?.isActive != false else { return }
        revoked = true
        logger.notice("session revoked: \(String(describing: reason), privacy: .public)")
        if let onRevoked {
            await onRevoked(reason)
        } else {
            await auth.clear()
        }
    }

    /// Check the Sign in with Apple credential state (§5 "revoked
    /// credential"): a user who disconnects the app in Apple ID settings
    /// must land back on sign-in instead of a stale session.
    public func checkAppleCredentialRevoked() async -> Bool {
        guard let subject = await auth.activeAppleSubject() else { return false }
        let state = await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: subject) { state, _ in
                continuation.resume(returning: state)
            }
        }
        return state == .revoked
    }
}
