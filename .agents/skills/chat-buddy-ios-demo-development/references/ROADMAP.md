# iOS cloud-client delivery roadmap

**Reviewed:** 2026-11-15  
**Baseline:** `24ab6b7aa1781388a48cd73fc6cbcfc76ae4c770`  
**Shared product contract:** `2026-08-18-demo-v1` (unchanged)

This is the delivery-status overlay for `IOS_IMPLEMENTATION.md` section 21. That document remains the target architecture; `ACCEPTANCE.md` remains the unchanged A01–A25 product acceptance contract. [VALIDATION_EVIDENCE.md](VALIDATION_EVIDENCE.md) owns the dated evidence and finding IDs.

## Status rules

- **Implemented component:** an owning source path is present; this is not an end-to-end pass.
- **Partial / blocked:** parts exist but a known integration defect or missing route prevents claiming delivery.
- **Not verified:** acceptance evidence was not obtained in this review; this does not assert that no implementation exists.
- **Accepted:** only after the relevant scenario runs at identified client/server commits with recorded results and no open blocking finding.

No A01–A25 product scenario is newly marked accepted by this documentation review. Historical CI success is narrower: the selected iOS unit-test target passed on 2026-11-10 UTC.

## Implementation status at the baseline

| Workstream from the original plan | What is already present | Delivery status / remaining gate |
|---|---|---|
| Cloud client foundation | Cloud-default composition, typed REST, Keychain session, SwiftData schema, outbox and delta sync | **Partial / blocked** by F01–F04; do not rebuild the foundations from scratch. |
| Realtime | WebSocket receive/heartbeat/sequencer; event/gap callbacks run delta sync | **Partial**. Verify cancellation, concurrent sync, durable cursor behavior and visible UI refresh; do not call it delivered streaming. F06. |
| Chats and contacts | Four-tab cloud host, cache-backed chats list, optimistic composer, contact projections | **Implemented components**, not accepted user flows. F01/F02/F03 block dependable usage. |
| Mixed groups | Group creation/invite/decision API methods and group-state projection tests | **Partial / server acceptance unverified**. All invitees must confirm; AI independent decisions and membership privacy require joint runtime tests. |
| Mira onboarding | Server-state route and REST-to-cache hydration path; hydration/projection tests | **Partial**. Production auth, offline/error resumption, first unread chat and cross-device state require A01/A02 evidence. |
| Moments | Cloud tab and repository composition; audience/pagination projection tests | **Partial / end-to-end unverified**. Media upload, actual view knowledge, audience enforcement, notifications and later chat continuity are separate gates. |
| APNs proactive contact | Permission request, registration helper and payload parser | **Blocked**, not delivered push. Complete token callback/upload, pending route and authorized destination; prove signed-device delivery. F05. |
| Native capabilities | Calendar/weather/search objects are composed in CloudAppState | **Not accepted in this review**. Verify contextual permission, confirmation, truthful result and cloud contract under A20–A22. |
| Data rights | Deletion method and legacy import path exist | **Partial / blocked** for deletion. F02/F07; export/import require separate round-trip and privacy evidence. |
| SpriteKit/native visual layer | Retained native presentation/legacy features | Not cloud runtime authority and not a prerequisite for claiming memory/agency delivery. Visual parity/performance is not newly certified here. |

## Next milestone R0 — reliable, account-safe cloud vertical slice (P0)

**Goal:** one hosted account can enter the app, send a real message, reconnect, see the authoritative response, and leave without exposing or replaying data into another account. New social/animation breadth must not displace these repairs.

### R0.1 — repair the actual message wire body (F01)

- [x] Send the stored, pre-encoded JSON bytes through `HTTPClient.sendJSON`.
- [x] Capture the actual `enqueueMessage` → `flushOne` request with `URLProtocol`. Assert the JSON object, `content`, `clientIdempotencyKey`, and `Idempotency-Key`.
- [x] Simulate a lost response and retry the same message. Check failure and HTTP 409 through the chat-row projection, then apply the same authoritative echo twice through delta sync.
- [x] Reopen a file-backed SwiftData store and replay the exact bytes and key. See [E03](VALIDATION_EVIDENCE.md#e03--r01-local-simulator-regression).
- [ ] Observe an app restart, cloud reconnect, and visible realtime echo against the hosted service for A23.

### R0.2 — unify session/cache/task lifetime (F02/F07)

- [x] Scope the SwiftData stores, transport and old callbacks to the active account. Sign-out, revocation and accepted deletion use one teardown path. Switching accounts stops the previous scope before using the new session.
- [x] Preserve owner-tagged outbox records during migration from the former shared store. SwiftData erases the configured current store after the server acknowledges a deletion request.
- [x] Verify A/B, restart, delayed A response, retryable deletion failure, one lost-receipt replay and account-scoped erase in the simulator with fixture transport. See [E04](VALIDATION_EVIDENCE.md#e04--r02-and-r03-local-simulator-regression).
- [ ] Verify the same A/B scene against the hosted service, including device ownership. Observe a production deletion receipt and scheduled server purge. Test host restart after an unconfirmed deletion and cleanup failure recovery on the release configuration.

### R0.3 — production auth and deterministic bootstrap (F03/F04)

- [x] Show cloud startup progress and retry on startup failure. The release client uses the cloud route. Diagnostic sign-in and the legacy root remain selectable in debug builds.
- [x] Wire the native Apple sign-in action and single-flight HTTP refresh into the cloud root. The fixture proves concurrent 401 delivery, token rotation, authenticated replay and revocation.
- [x] Honor failed sync and onboarding reads. A successful retry runs the normal post-sync routing.
- [ ] Verify signed Apple authorization with the matching Web endpoint, provisioned app identity and hosted configuration. Exercise the release UI and actual reconnect against the hosted service.

**R0 exit:** new transport/lifecycle tests pass plus the existing unit target; cloud startup, actual send and A/B isolation pass in the simulator. Record exact commits, toolchain and failing/passing cases before closing F01–F04/F07. No physical APNs claim is made at R0.

## R1 — delivered realtime and notification route (P0)

Depends on R0 account lifecycle and usable auth.

- [ ] Wire APNs success/failure callbacks into the token-upload method; retry registration safely and bind device ownership to the current account.
- [ ] Verify Push Notifications/signing/environment configuration on the signed app; confirm server device registration and a server-persisted message before push.
- [ ] Unify URL/push entry with a pending route containing conversation/message/request/invitation/Moment IDs. Preserve it through cold auth and sync, validate authorization, navigate, then mark only actually visible content read.
- [ ] Denied permission, delayed registration, revoked account, removed membership, blocked/deleted destination and foreground notification must have tested outcomes.
- [ ] Serialize/coalesce delta sync; inject page replay, out-of-order completion and persistence failures. Cursor must not outrun committed state or regress.
- [ ] Publish committed cache changes to active chat/list/Moments views. Add started/delta/completed/failed stream handling only against the real contract; a full delta refresh is not stream rendering.
- [ ] Prove background/foreground pause/resume and intentional disconnect do not reconnect an obsolete account.

**R1 exit:** simulator cold/warm routing and reconnect UI tests, then physical TestFlight APNs cold-launch -> correct authorized chat/message, with device/build/environment and message/job IDs recorded. A19/A23 still require their server-side dedupe/intent evidence.

## R2 — joint social acceptance with Web/cloud (P0 product gates)

Depends on R0/R1. Do not implement the missing intelligence in Swift.

- [ ] Freeze matching iOS/server schema/fixtures and record both commits and environment.
- [ ] A01–A03: Mira onboarding, resume and real requests, not local scripted substitutes.
- [ ] A04–A07/A13–A15: mixed human/AI invitations, accepted-only visibility, independent group decisions, loop termination and same-template public identity without merging private histories.
- [ ] A08–A10/A17–A18: authorized group/Moment continuity; negative tests for unrelated private memory, invisible posts and hidden AI transcripts across API, sync, search, export and diagnostics.
- [ ] A11/A12/A16/A19/A24: DM policy, blocking, durable offline world/proactive intents, timing/expiry/mute and server deduplication.
- [ ] A20–A22/A25: confirmed native actions, truthful failures and real account deletion, with privacy-safe evidence.

**R2 exit:** an A01–A25 matrix states client result, server result and evidence separately. No “whole demo complete” label while a required scenario is blocked or unverified.

## R3 — release hardening and multi-day evaluation

- [ ] English/Simplified Chinese, Dynamic Type, VoiceOver, Reduce Motion and permission-denied flows receive visible-flow review, not just string presence checks.
- [ ] Signed-device checks cover Apple auth, APNs, EventKit, Photos, background reconnect and deletion; capture server/client revisions and TestFlight build.
- [ ] Verify export/import round-trip with disposable data and no secret leakage; preserve original backup until acceptance.
- [ ] Run the existing three-day social evaluation in `ACCEPTANCE.md`; record voluntary returns, authorized continuity, distinct characters, notification annoyance and privacy failures.

Animation polish and extra social breadth follow a stable core route. Human friends, mixed groups and Moments remain required product scope; this ordering is not a scope reduction.

## Status maintenance

When closing a checkbox, update `VALIDATION_EVIDENCE.md` in the same change with command, artifact/run ID, client/server commit, environment, observed outcome and remaining limitation. Source fixes do not retroactively make the 2026-11-10 CI a live-runtime acceptance run. Do not update the shared product contract version for evidence-only changes.
