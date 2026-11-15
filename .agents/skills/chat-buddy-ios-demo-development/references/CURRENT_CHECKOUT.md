# Current checkout and migration evidence

**Reviewed:** 2026-11-15  
**Source baseline:** `24ab6b7aa1781388a48cd73fc6cbcfc76ae4c770` (`main` at review)  
**Product contract:** `2026-08-18-demo-v1` (unchanged)

Paths below are repository-relative. This is a source/CI review, not a new simulator or device run. See [ROADMAP.md](ROADMAP.md) for delivery gates and [VALIDATION_EVIDENCE.md](VALIDATION_EVIDENCE.md) for findings, reproduction, and acceptance facts.

## Actual owning paths

| Area | Current implementation and boundary |
|---|---|
| App entry | `Chat_Buddy_iOS/Chat_Buddy_iOSApp.swift`: `CBUseCloudRuntime` defaults to true. `CloudAppRoot` routes loading/auth/onboarding/ready/offline; `ChatsTabHost` contains Chats, Contacts, Moments, Me. Legacy root remains present. |
| Cloud composition | `Chat_Buddy_iOS/App/CloudAppState.swift`: `ObservableObject`; owns auth/HTTP/realtime/sync/repositories/native capability objects. It is not the legacy local `AppState` or a second AI runtime. |
| Transport and session | `Networking/HTTPClient.swift`, `AuthSession.swift`, `RealtimeClient.swift` under `Chat_Buddy_iOS/`. Typed REST, Keychain session storage, WebSocket callbacks/heartbeat/sequencer are implemented. Production route and lifecycle integration remain incomplete. |
| Local read model | `Persistence/ModelContainerFactory.swift`: persistent `ChatBuddyCloudCache` and a shared schema. `Repositories/ConversationRepository.swift` offers cache reads, group creation/invitation calls, onboarding hydration, and message enqueue/flush. |
| Delta sync | `Sync/SyncCoordinator.swift`: cursor-based fetch, pagination, `EventApplier`, tombstones/idempotency reconciliation and cursor advance. Cloud realtime callbacks currently trigger delta sync rather than targeted UI updates. |
| Chat feature | `Features/Chats/ChatsRootView.swift`, `CloudChatViewModel.swift`: cache-backed chat list, optimistic rows, draft cleared before waiting on send, retry by existing idempotency key. The HTTP send path has a confirmed encoding defect; see F01. |
| Apple sign-in | `Features/Auth/SignInWithAppleView.swift` contains the Apple button and token-exchange extension. The current unauthenticated root still selects `DevSignInView`; source existence is not production-login delivery. |
| Push | `Capabilities/PushNotificationService.swift`: authorization, APNs registration request, a token-upload method, and route decoding. The reviewed app root does not wire an app-delegate token callback; push route handling in `CloudAppState` only selects a tab. |
| Social UI | The root wires Contacts and cloud Moments; `ConversationRepository` has group shell/invite/decision APIs. Unit projections cover some group/contact/Moments states. AI decisions, membership authorization, proactive scheduling, and memory continuity still require shared-server evidence. |

Do not replace these existing cloud components with a new similarly named networking stack. Inspect and repair the owning route first. SwiftUI/SpriteKit presentation does not own actor decisions, durable proactive timing, or authoritative memory.

## Delivery assessment

Cloud client foundations are source-present and the reviewed commit has a successful unit-test CI run. The application is **not yet evidenced as a release-ready hosted social client**. Known blockers include message-body double encoding, account/cache lifecycle isolation, cloud-startup fallback, production auth wiring, and complete APNs navigation. Details and exit criteria are maintained once in the evidence/roadmap references, not as unchecked historical feature lists.

The root `AGENTS.md`/`CLAUDE.md` and `docs/DEVELOPMENT.md` retain a legacy native-port map (UserDefaults, direct provider APIs, affinity and Done tables). Those describe compatibility code, not the cloud demo authority contract. Preserve importability of legacy data; do not delete that code just to make the documents agree. Hosted testers must not be routed to provider-key setup to mask a server or startup error.

## Existing tests: reuse, then close integration gaps

`Chat_Buddy_iOSTests/` contains `CloudClientTests`, `CloudFeatureTests`, `RemoteDTOFixtureTests`, `OutboxStoreTests`, `EventApplierTests`, `RealtimeSequencerTests`, `SyncCursorCodecTests`, `ConflictResolverTests`, `ContactsRepositoryTests`, `OnboardingHydrationTests`, `DeviceSettingsStoreTests`, and `ViewDataMappingTests`, alongside legacy tests.

Presence is a navigation aid. The historical CI result applies to its selected test target; do not invent a per-suite result/count, or infer live-server compatibility. In particular, `CloudClientTests` checks error flags, endpoint paths and environment defaults, not the outgoing outbox HTTP body. `CloudFeatureTests` exercises pure projections/reducers; its existence does not establish end-to-end group agency, notification delivery, or privacy enforcement.

For offline send/reconnect, trace enqueue -> durable outbox -> actual HTTP request bytes -> server response -> realtime/delta reconciliation -> visible UI. Preserve the same idempotency identity across retry. Test revoked sessions and account switching; account-scoped cursors/outbox alone do not isolate all cached messages or conversation reads.

For push/deep links, separate parser fixtures from app-delegate wiring, device-token upload, physical APNs delivery, and authorized cold/warm destination navigation. Preserve route IDs through auth and sync, and verify deleted/blocked/not-a-member fallback without leaking cached content.

## Legacy backup/import is its own contract

Read `Chat_Buddy_iOS/Services/Storage/DataBackupCoordinator.swift`, `DataImporter.swift`, `DataExporter.swift` and `StorageService.swift`, plus `docs/WebToiOSMigration/`. Inspect the exact accepted backup schema/version before assuming a Web JSON export is accepted. An old local backup and a new cloud cache snapshot are not interchangeable formats. These remain inspection targets for an import change, not newly certified flows in this review.

Use a disposable store/container and explicit fixture backup. Check version rejection, complete decode/validation, image restoration and all store reloads. Verify real counts/IDs/text before and after import, then restart and export again. Do not infer whole-import atomicity from one validated storage operation or a temporary image directory: inspect failure handling across storage, images, credentials and settings. Preserve the user's original backup and live app data until an authorized migration is accepted.

`includeSensitiveData` is a deliberate export choice; default evidence must not expose API/session secrets or private transcripts.

## Targeted verification

Select an installed simulator from `xcodebuild -showdestinations` / `xcrun simctl list devices available`, not a stale fixed destination from a design document. The reviewed CI workflow declares `macos-26`, Xcode 26.5, and `-only-testing:Chat_Buddy_iOSTests` with simulator ad-hoc signing. This is the workflow configuration, not an independently re-run toolchain report.

Report build, unit target, UI target, visible flow, live server and device push separately. A small documentation change does not require live traffic or a TestFlight upload. The 2026-11-15 review ran only an isolated Foundation encoding reproduction on Linux Swift 6.2.1; it did not run the Xcode app, SwiftData, UIKit or APNs locally.
