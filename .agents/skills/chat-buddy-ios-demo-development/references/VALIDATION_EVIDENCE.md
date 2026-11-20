# Validation evidence and review findings

**Review date:** 2026-11-15  
**Repository:** `Luckycat133/Chat_Buddy_iOS`  
**Source commit:** `24ab6b7aa1781388a48cd73fc6cbcfc76ae4c770`  
**Shared product contract:** `2026-08-18-demo-v1` (unchanged)

This is an implementation review and evidence ledger. It does not replace or relax `ACCEPTANCE.md`. All source paths below refer to the reviewed commit; future repairs must attach new evidence rather than rewriting this baseline as though it passed.

## E01 — historical CI, verified from GitHub metadata and workflow

- [Run 42760117909](https://github.com/Luckycat133/Chat_Buddy_iOS/actions/runs/42760117909), event `push`, branch `main`, head `24ab6b7aa1781388a48cd73fc6cbcfc76ae4c770`.
- GitHub reports `completed / success`; created `2026-11-10T05:07:27Z`, updated `2026-11-10T05:13:25Z`.
- `.github/workflows/ios-ci.yml` declares `macos-26`, Xcode 26.5, an available/created iPhone 17 Pro simulator and `xcodebuild test -only-testing:Chat_Buddy_iOSTests`.
- The workflow enables simulator ad-hoc signing: `CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY="-"`. Do not copy a signing-disabled command for Keychain coverage without accounting for its entitlement behavior.
- This evidence supports successful execution of the selected unit-test target at that commit. It does **not** certify the UI-test target, real cloud contract compatibility, physical-device APNs, Apple login, Store/TestFlight distribution, or multi-day social acceptance.
- No total test count or per-suite result is asserted here. The workflow configuration is not a separately re-run local toolchain report.

## E02 — isolated Foundation reproduction performed in this review

Environment: Linux, Swift 6.2.1 (`x86_64-unknown-linux-gnu`). This is not an Xcode, UIKit or SwiftData test.

The message repository stores JSON bytes, then `flushOne` passes `entry.bodyData` to `HTTPClient.send`. `HTTPClient.buildRequest` encodes every `Encodable` body again. Reproduction:

```swift
import Foundation
struct Body: Codable {
    let clientIdempotencyKey: String
    let content: String
}
let queued = try JSONEncoder().encode(
    Body(clientIdempotencyKey: "review-fixture", content: "hello")
)
let wire = try JSONEncoder().encode(queued)
let json = try JSONSerialization.jsonObject(with: wire, options: [.fragmentsAllowed])
print("wire is JSON object:", json is [String: Any])
print("wire is base64 string:", (json as? String).flatMap { Data(base64Encoded: $0) } == queued)
precondition(json is String)
```

Observed: `wire is JSON object: false`; `wire is base64 string: true`. This confirms the encoding mechanism underlying F01; it does not claim a live endpoint rejection was observed. The Foundation implementation also declares `.base64` as the default Data encoding strategy: [Swift Foundation JSONEncoder](https://github.com/swiftlang/swift-foundation/blob/main/Sources/FoundationEssentials/JSON/JSONEncoder.swift).

## Source-inspection findings (open at the baseline)

### F01 — P0: message outbox body is encoded twice

Evidence: `Chat_Buddy_iOS/Repositories/ConversationRepository.swift`, `enqueueMessage` and `flushOne`; `Chat_Buddy_iOS/Networking/HTTPClient.swift`, `buildRequest`.

`enqueueMessage` encodes `SendMessageBody` to Data. `flushOne` passes that Data as the generic request body. The client encodes it again, producing a JSON Base64 string instead of the expected message object. E02 reproduces the mechanism. Fix with an explicit raw-JSON transport path or a typed decoded mutation and exactly one encoding. Require a request-capture test through the real repository-to-HTTP route, with the same idempotency key across retry.

### F02 — P0: account lifetime does not isolate cached reads and old work

Evidence: `App/CloudAppState.swift`, `signOut`; `Persistence/ModelContainerFactory.swift`, `make`; `Repositories/ConversationRepository.swift`, `cachedConversationList`/`cachedMessages` (all under `Chat_Buddy_iOS/`).

`signOut` clears auth and changes stage, but does not stop realtime/sync, detach push, reset the bootstrapped-push flag, or dispose/isolate the existing container. The persistent store uses a common name; cached conversation reads have no current-account filter, and message reads filter only conversation ID. Outbox/cursor scoping does not establish read isolation. This is a source-supported cross-account exposure risk, not a claim that a live user's data leaked during this review.

Close only with coordinated teardown plus an A-to-B account-switch test covering cached rows, queued sends, restart, stale callbacks and deep links.

### F03 — P0: cloud initialization silently displays the legacy route

Evidence: `Chat_Buddy_iOS/Chat_Buddy_iOSApp.swift`, `content` and `bootstrapCloudIfNeeded`.

The cloud root is selected only when cloud mode is enabled **and** `cloud` is non-nil. Before initialization completes, and when container creation fails, the `else` branch renders `LegacyAppRoot`; the recorded `cloudError` is not rendered by that root switch. Normal cloud loading/failure must not look like successful legacy operation or ask hosted users to configure model keys. Add explicit startup/loading/error/retry states and an opt-in internal legacy boundary.

### F04 — P0: production authentication and refresh are not wired through the normal root

Evidence: `Chat_Buddy_iOS/Chat_Buddy_iOSApp.swift`, `CloudAppRoot`; `Features/Auth/SignInWithAppleView.swift`; `Networking/HTTPClient.swift`; `Networking/AuthSession.swift`; `App/CloudAppState.swift`.

The unauthenticated root uses `DevSignInView`, while the Apple button/exchange implementation exists separately. `HTTPClient` exposes an unauthorized handler, but the reviewed `CloudAppState` composition/bootstrap does not install it. `AuthSession.currentAccessToken` can reload expired material and return it; `isAuthenticated` only checks non-nil. A refresh API or token-rotation helper existing elsewhere does not prove that the main request route invokes it.

Wire normal Apple auth and a tested refresh/revocation owner. Also preserve sync failure state: the Apple sign-in extension unconditionally transitions to onboarding after `runInitialSync`, unlike the dev route's offline guard. Network failure in `routeAfterSync` currently falls through to ready; distinguish unknown onboarding state from completed onboarding.

### F05 — P0: APNs and precise navigation remain partial

Evidence: `Chat_Buddy_iOS/Capabilities/PushNotificationService.swift`; `App/CloudAppState.swift`, `bootstrapPushIfReady`/`handlePushRoute`; `Chat_Buddy_iOSApp.swift`; `Features/Chats/ChatsRootView.swift`.

The service requests permission and APNs registration and defines `registerDeviceToken`, but the reviewed app entry has no `UIApplicationDelegateAdaptor`/device-token callback connecting registration to that upload method. `handlePushRoute` selects a tab and discards destination identifiers; the chats navigation stack is not driven by a pending push route. The reviewed root also lacks URL entry handling. A route parser is not a delivered notification/deep-link flow.

Permission timing also needs correction: `routeAfterSync` invokes push bootstrap even after selecting onboarding, despite the comment promising an after-onboarding request. Close with contextual permission, token success/failure/retry, signed configuration, pending-route auth/sync, authorization-aware navigation and cold/warm device evidence. Apple documents the registration callback route in [Registering your app with APNs](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns).

### F06 — P1: realtime cache application is not yet a verified visible-update loop

Evidence: `App/CloudAppState.swift`, `handleRealtimeEvent`; `Sync/SyncCoordinator.swift`; `Networking/RealtimeClient.swift`; `Features/Chats/ChatsRootView.swift`.

Realtime/gap callbacks run delta sync. The chat list holds a copied `@State` array and reloads on task/appear/refresh; it does not subscribe to the published event or a committed-cache revision in the reviewed view. Cache writes alone therefore do not establish an updated visible preview/unread list. Streaming completion also must not be inferred from delta sync.

`runSync` has no explicit single-flight/coalescing guard across network suspension. Page application, outbox reconciliation and cursor writing are separate calls; crash/failure atomicity is not established by the coordinator source alone. Add overlap, replay, save-failure, cancellation, and active-screen tests before claiming durable/visible exactly-once behavior. Keep source-supported gaps distinct from stress-test outcomes not yet run.

### F07 — P0: deletion failure and cleanup must be made truthful

Evidence: `App/CloudAppState.swift`, `deleteAccount`; `Persistence/ModelContainerFactory.swift`, `destroyStore`; `Networking/AuthSession.swift`.

Any server deletion error is caught and followed by local teardown and unauthenticated stage. A timeout/5xx does not prove server deletion. Cleanup calls `KeychainService.clearAll` rather than the cloud session's `auth.clear`, while the live `AuthSession` retains in-memory fields. Store deletion guesses `.sqlite` filenames and suppresses errors while the app still owns the container. This review has not proven actual on-disk deletion or cloud Keychain cleanup.

Separate server accepted/pending/failed state from local sign-out, clear the owning cloud session, release/isolate store owners, and delete the configured store safely. Test offline/5xx, already-deleted response, retry, reboot and account switch. Do not claim A25 from reaching the auth screen.

## Existing automated coverage versus product claims

| Source inspected or located | What it supports | What it does not prove |
|---|---|---|
| `CloudClientTests.swift` (read) | Error mapping/flags, endpoint paths, environment defaults | Actual outbox HTTP JSON body, refresh integration or deployed API compatibility |
| `CloudFeatureTests.swift` (read in part) | Optimistic-row merge, failed/queued rows, dedup/tombstones, contact projection, onboarding state mapping and Moments endpoint/audience helpers | Independent AI decisions, real permissions/privacy enforcement or full UI route |
| `OutboxStoreTests`, `EventApplierTests`, `RealtimeSequencerTests`, `SyncCursorCodecTests`, `ConflictResolverTests` (located) | Existing targeted test suites to reuse and inspect when changing those owners | Disk restart, transport reconnect, concurrency and atomicity are not certified from filenames |
| `OnboardingHydrationTests`, `ContactsRepositoryTests`, `RemoteDTOFixtureTests` (located) | Existing regression/fixture suites; avoid duplicating the foundations | Cross-device runtime, device navigation or server membership acceptance |

CI E01 is a target-level historical result; this table describes review scope, not invented per-test run results.

## A01–A25 acceptance snapshot

| Scenario group | Status as of this review |
|---|---|
| A01–A03 onboarding / introduction | Partial client source; production auth and live runtime flow not accepted. F03/F04. |
| A04–A07, A13–A15 mixed groups / identity / agency | Client APIs/projection pieces present; joint server authorization/decision evidence not obtained. |
| A08–A10, A17–A18 memory / privacy / Moments continuity | Not verified against the cloud runtime; no client fixture can certify private-memory isolation. |
| A11–A12, A16, A24 social policy / offline world / block | Server behavior and cross-client enforcement not verified in this review. |
| A19 proactive reopen | Blocked client integration (F05), with server intent/dedupe and device delivery still unverified. |
| A20–A22 native capabilities | Not exercised in this review; retain original confirmation/truthfulness requirements. |
| A23 offline reconciliation | Outbox/reducer components exist; F01 blocks the normal wire body, and restart/reconnect acceptance remains open. |
| A25 account deletion | Blocked by F02/F07; server deletion and local cleanup need separate evidence. |

No live model calls, backend mutations, tester account deletion, push sends, Xcode runs or TestFlight upload were performed by this review.

## Reproducible next verification

Choose a real available destination; substitute its UDID, not the literal placeholder:

```bash
xcodebuild -project Chat_Buddy_iOS.xcodeproj -scheme Chat_Buddy_iOS -showdestinations
xcrun simctl list devices available

xcodebuild test \
  -project Chat_Buddy_iOS.xcodeproj \
  -scheme Chat_Buddy_iOS \
  -destination 'platform=iOS Simulator,id=<AVAILABLE_UDID>' \
  -only-testing:Chat_Buddy_iOSTests \
  -resultBundlePath /tmp/ChatBuddy-unit-<UNIQUE_RUN>.xcresult \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY='-'
```

Run the UI-test target separately after adding meaningful route/lifecycle scenarios. Simulator commands do not replace signed physical-device checks. Use disposable stores/accounts and approved staging endpoints for integration; do not trigger live traffic for an evidence-only documentation edit.

Future ledger entries must include: date, client commit, server/schema commit when applicable, build/toolchain/device/environment, scenario/test name, exact command or manual procedure, expected vs observed result, run/artifact ID, and unresolved limitations. Redact tokens, private transcripts and unnecessary personal data.
