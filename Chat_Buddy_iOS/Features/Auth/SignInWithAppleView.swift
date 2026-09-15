import SwiftUI
import AuthenticationServices
import os

/// Sign in with Apple flow per skill §"Authentication":
///   - obtain identity token and authorization code
///   - send to `/v1/auth/apple`
///   - server verifies with `jose` against Apple's JWKS
///   - store refresh/session material in Keychain
///   - register device + APNs token
///   - run initial sync
///   - route into the Mira chat or the Chats list
public struct SignInWithAppleView: View {
    @EnvironmentObject private var cloud: CloudAppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var error: String?
    @State private var inFlight = false
    private let logger = CloudLogger.auth

    public init() {}

    public var body: some View {
        SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = [.fullName, .email]
        } onCompletion: { result in
            switch result {
            case .success(let authorization):
                guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                    Task { @MainActor in self.error = "Unexpected credential type" }
                    return
                }
                Task { await handle(credential: credential) }
            case .failure(let failure):
                Task { @MainActor in
                    self.error = failure.localizedDescription
                }
            }
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 48)
            .accessibilityLabel("Sign in with Apple")
            .overlay(alignment: .bottom) {
                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.top, 8)
                }
            }
    }

    private func handle(credential: ASAuthorizationAppleIDCredential) async {
        inFlight = true
        defer { inFlight = false }
        do {
            guard let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                throw SignInError.missingIdentityToken
            }
            let firstName = credential.fullName?.givenName ?? ""
            let displayName = firstName.isEmpty ? "Apple User" : firstName
            try await cloud.signInWithApple(
                identityToken: token,
                authorizationCode: credential.authorizationCode.flatMap {
                    String(data: $0, encoding: .utf8)
                },
                displayName: displayName,
            )
            self.error = nil
        } catch {
            self.error = String(describing: error)
            logger.error("Sign in with Apple failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public enum SignInError: Error, Sendable {
        case missingIdentityToken
    }
}

extension CloudAppState {
    /// Server-side exchange. The server verifies the Apple JWT against
    /// Apple's JWKS using `jose`, then issues access + refresh tokens.
    public func signInWithApple(
        identityToken: String,
        authorizationCode: String?,
        displayName: String,
    ) async throws {
        struct Body: Codable {
            let identityToken: String
            let authorizationCode: String?
            let displayName: String
        }
        struct Response: Codable {
            let accessToken: String
            let accessExpiresAt: Date
            let refreshToken: String
            let refreshExpiresAt: Date
            let accountId: String
            let actorId: String
        }
        let response = try await http.send(
            APIEndpoint(path: "/v1/auth/apple", requiresAuth: false),
            method: "POST",
            body: Body(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                displayName: displayName,
            ),
            as: Response.self,
        )
        await auth.update(
            tokens: AuthTokens(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                accountId: response.accountId,
                actorId: response.actorId,
                accessExpiresAt: response.accessExpiresAt,
            ),
        )
        await runInitialSync()
        // `stage` has a private setter; onboarding flows transition via
        // the explicit gate on CloudAppState.
        transition(to: .onboarding)
    }
}
