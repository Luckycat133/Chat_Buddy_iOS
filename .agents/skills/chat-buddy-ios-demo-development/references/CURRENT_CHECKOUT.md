# Current checkout and migration evidence (reviewed 2026-10-03)

Paths are repository-relative. The root AGENTS/CLAUDE body contains a legacy native-port map (UserDefaults, direct provider APIs, affinity and Done tables). It describes compatibility code, not the cloud demo authority contract. Preserve importability of legacy data; do not delete that code just to make the documents agree. Current product behavior comes from this Skill and its shared contracts, with actual implementation verified from source.

## Trace existing cloud work before adding it again

Inspect the current cloud stores/repositories and their tests. The checkout already contains `CloudClientTests`, `RemoteDTOFixtureTests`, `OutboxStoreTests`, `EventApplierTests`, `RealtimeSequencerTests`, `SyncCursorCodecTests`, `ConflictResolverTests`, `ContactsRepositoryTests` and `OnboardingHydrationTests` in `Chat_Buddy_iOSTests/`. Their presence is a navigation aid, not a passing test report or a deployed service guarantee.

For offline send/reconnect, trace enqueue -> durable outbox -> server response -> realtime deduplication -> UI. Preserve the same idempotency identity across a retry. Conflicts remain visible rather than silently replaying as a new social action. Test revoked session and account switching; one account's cached or pending data must not reappear for another.

For push/deep links, separate simulator route tests from real APNs registration/delivery. Test cold and warm navigation to an authorized conversation. A payload decoded by a fixture does not prove server membership checks or device delivery.

## Legacy backup/import is its own contract

Read `Chat_Buddy_iOS/Services/Storage/DataBackupCoordinator.swift`, `DataImporter.swift`, `DataExporter.swift` and `StorageService.swift`, plus `docs/WebToiOSMigration/`. Inspect the exact accepted backup schema/version before assuming a Web JSON export is accepted. An old local backup and a new cloud cache snapshot are not interchangeable formats.

Use a disposable store/container and explicit fixture backup. Check version rejection, complete decode/validation, image restoration and all store reloads. Verify real counts/IDs/text before and after import, then restart and export again. Do not infer whole-import atomicity from one validated storage operation or a temporary image directory: inspect failure handling across storage, images, credentials and settings. Preserve the user's original backup and live app data until an authorized migration is accepted.

`includeSensitiveData` is a deliberate export choice; default evidence must not expose API/session secrets or private transcripts. Hosted demo users should not be sent to legacy provider-key setup to work around a server error.

## Targeted verification

Choose the affected tests from the table above; select an available simulator from the live Xcode destinations rather than trusting the old fixed iPhone 17 Pro/iOS 26.2 line. Use the existing build-ios-apps plugin for platform mechanics when available. Report fixture tests, build, launch, visible flow, live server and device push as separate evidence. A small UI/doc change does not require every acceptance scenario or TestFlight upload.
