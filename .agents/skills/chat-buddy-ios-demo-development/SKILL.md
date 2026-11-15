---
name: chat-buddy-ios-demo-development
description: Implement, refactor, review, and test the native Chat Buddy iOS TestFlight Demo as a cloud-backed SwiftUI social client. Use when working on Sign in with Apple, SwiftData cache, realtime chat, APNs proactive messages, human/AI contacts, mixed groups, Moments, friend requests, identity linking, EventKit calendar actions, weather/search UI, sync, privacy, export, or TestFlight acceptance.
metadata:
  author: Luckycat133
  version: "2026-08-18-demo-v1"
  implementation_review: "2026-11-15"
  reviewed_commit: "24ab6b7aa1781388a48cd73fc6cbcfc76ae4c770"
  product: chat-buddy
  platform: ios
---

# Chat Buddy iOS Demo Development

Build the native iOS TestFlight client for Chat Buddy's shared cloud social world.

## Product outcome

Chat Buddy is a WeChat-style social app where human users and AI characters are first-class contacts. Characters have fixed public identities, separate relationships, memories with provenance, social agency, offline life, Moments, and friend-level capabilities. The iOS demo must make proactive messages, mixed groups, continuity, and Moments feel native and dependable.

The iOS app is a cloud client. It must not become a second implementation of character intelligence.

## Read the references

For implementation, review, or delivery claims, start with:

- Actual source ownership and migration caveats: [references/CURRENT_CHECKOUT.md](references/CURRENT_CHECKOUT.md)
- Delivery status, dependency order, and exit criteria: [references/ROADMAP.md](references/ROADMAP.md)
- Dated observations, CI scope, and unresolved findings: [references/VALIDATION_EVIDENCE.md](references/VALIDATION_EVIDENCE.md)

Then load only the product/design references the task requires:

- Product behavior and non-negotiable rules: [references/PRODUCT_CONTRACT.md](references/PRODUCT_CONTRACT.md)
- Complete demo flows and screens: [references/DEMO_EXPERIENCE.md](references/DEMO_EXPERIENCE.md)
- Shared data model, runtime, API, sync, and privacy: [references/DOMAIN_ARCHITECTURE.md](references/DOMAIN_ARCHITECTURE.md)
- Native iOS implementation plan: [references/IOS_IMPLEMENTATION.md](references/IOS_IMPLEMENTATION.md)
- Acceptance scenarios and TestFlight gates: [references/ACCEPTANCE.md](references/ACCEPTANCE.md)

`IOS_IMPLEMENTATION.md` describes the target design, including its original section 21 implementation sequence. `ROADMAP.md` is the current delivery-status overlay; neither a design paragraph nor a source comment is a passing acceptance record. This review changes implementation evidence, not the shared `2026-08-18-demo-v1` product contract.

When shared behavior changes, update both Web and iOS project skills to the same contract version. Do not imply that the Web repository or a deployed runtime was reviewed when only iOS was inspected.

## Settled product decisions

Treat these as requirements, not questions to reopen:

1. Web/cloud owns the companion runtime; iOS consumes versioned APIs and realtime events.
2. TestFlight uses hosted models and cloud data; testers do not enter API keys.
3. Chats is the default destination, not Dashboard.
4. Mira / 米拉 is the user's warm, reliable first official friend and performs onboarding through ordinary chat.
5. Humans and AIs can send friend requests, DM, create groups, invite, accept, decline, leave, post Moments, delete, and block.
6. Every invited human and AI confirms group membership.
7. Mixed groups have no visible fixed AI reply count; rapid user messages remain possible while AIs are responding.
8. Group and visible Moment memories may influence private chat; unrelated private branches may not.
9. AI-to-AI private chats are hidden from human clients.
10. Relationships are implicit and narrative; no affinity bars, unlocks, or automatic couple labels.
11. Characters retain original-setting identity; no game map or world traversal.
12. Character public identity is fixed; users may set private remarks only.
13. Same-template actors show one public identity in shared groups while private relationships remain separate.
14. Offline character life and proactive messages come from the cloud scheduler.
15. Moments is mandatory and shares the same actor/event system as chat.
16. Human friends and mixed human/AI groups are in the demo.
17. Companion capabilities are weather, calendar, and bounded search.
18. Calendar writes require explicit confirmation and truthful completion state.
19. Users can deny unsolicited AI DMs.
20. Unfriend preserves history; block stops contact; account deletion removes private data.

## Working method

### 1. Inspect the owning path

Read:

- the SwiftUI feature
- owning observable store/repository (the current cloud root uses `ObservableObject`)
- network contract fixture
- SwiftData model/migration
- deep-link/push handling when relevant
- nearest unit/UI tests
- relevant skill reference

Determine whether existing code is legacy local authority or new cloud-backed behavior. Trace the actual caller from the app root: a service, parser, or view that exists but is not wired into that route is only partial implementation.

### 2. Keep the client boundary

iOS may:

- render
- cache
- sync
- queue offline mutations
- request permissions
- execute approved native actions
- register push
- deep-link
- report structured results

iOS may not:

- compile character prompts
- call hosted chat models directly
- decide which AI replies
- extract authoritative memory
- simulate relationships
- create hidden AI conversations
- schedule durable proactive messages locally as the hosted source of truth

SpriteKit and other native animation remain presentation concerns, not character-runtime or memory authority. Preserve legacy import compatibility without silently falling back to legacy intelligence when cloud initialization fails.

### 3. Implement contract-first

For new cloud behavior:

1. use or update the shared contract
2. add decoding fixtures and actual HTTP request-body assertions
3. map DTO to cache model
4. update repository
5. update sync/realtime application
6. build SwiftUI state
7. handle loading/offline/error/denied
8. add deep-link or push behavior
9. add tests

Do not infer API payloads from UI needs without updating the shared contract. Pre-encoded JSON `Data` must not be passed back through a generic `JSONEncoder` body path; test the bytes reaching `URLProtocol`, not only the endpoint path or DTO.

### 4. Make offline behavior explicit

Every mutation has:

- client idempotency key
- queued/sending/accepted/failed/conflict state
- restart persistence when supported
- server reconciliation
- duplicate realtime protection

Never replace the whole local cache with an older snapshot. Prove account scoping for reads as well as outbox/cursors. Logout, revocation, deletion, and account switching must stop old tasks, detach device ownership, clear session material, and dispose or isolate old cache state before another account can read or replay it. An actor type alone does not prove single-flight synchronization across suspension points.

### 5. Treat native capabilities as confirmed actions

For EventKit or another native action:

- show what will happen
- require confirmation for writes
- perform through the capability service
- return structured success/failure to server
- let the character speak only after authoritative result

The model cannot declare a native action complete. Account deletion also needs truthful completion: a network failure is not proof that server deletion started or completed.

### 6. Preserve social and privacy rules

Before displaying or acting on data, respect server authorization:

- pending invitees are not active members
- hidden AI conversations are never cached
- blocked actors cannot contact
- denied AI DM permission is enforced
- identity links change public projection, not private history
- group memories may appear later only through server-authorized character behavior

Do not add client-only privacy rules as a substitute for server enforcement.

### 7. Test the complete route

For a feature, test:

- cold launch
- warm launch
- offline cache
- reconnect
- push/deep link
- permission denied
- account/session revoked
- localization
- accessibility

Then run the relevant acceptance scenario. APNs route decoding, permission prompts, server device registration, and physical-device delivery are four different checks. Preserve pending route identifiers through authentication and sync; merely selecting a tab is not deep-link completion.

## Current-repository corrections

The checkout already has a cloud-default `CloudAppState`, `HTTPClient`, `AuthSession`, repositories, SwiftData cache, outbox, and realtime/sync components alongside the legacy native port and its own `AIPipeline`. Do not plan these components as if absent, and do not promote their existence into a release claim. The reviewed integration blockers are tracked in `ROADMAP.md` and `VALIDATION_EVIDENCE.md`.

For the cloud demo:

- do not extend Swift `AIPipeline` as the hosted intelligence source
- do not persist full chat or memory arrays in UserDefaults
- do not keep affinity score as relationship authority
- do not run background Moments generation independently from cloud
- do not maintain provider profiles in the TestFlight primary flow
- do not block the composer while an AI is responding
- do not create a second schema that only resembles the Web API
- do keep legacy local data readable for one-time import
- do use Keychain for session secrets
- do use SwiftData for cloud cache
- do use APNs and server-persisted messages for proactive contact
- do keep development login and legacy runtime behind explicit internal-only boundaries

## Native UX defaults

- SwiftUI and system navigation first
- Liquid Glass only where it improves hierarchy
- Dynamic Type and VoiceOver from first implementation
- contextual permission prompts
- standard sheets for confirmations
- familiar chat and Moments patterns
- no professional tool workspace
- no visible debug relationship numbers
- no hidden transcript inspector in user builds

## Default design choices

When the references do not specify a low-level detail, choose the simplest native design that preserves:

1. cloud authority
2. privacy and provenance
3. offline resilience
4. platform conventions
5. accessibility
6. contract compatibility
7. TestFlight delivery speed

Do not send routine implementation choices back to the product owner. Record a reversible assumption and proceed.

## Quality bar

A change is not done unless:

- DTO fixtures decode and request bodies match the contract
- cache migration and account isolation are safe
- realtime events are idempotent and committed changes reach the visible UI
- loading/offline/error/permission-denied states exist
- cold and warm deep links work when relevant
- English and Simplified Chinese are complete
- Dynamic Type and VoiceOver are reviewed
- no model/provider secret is embedded
- no hidden AI transcript is exposed
- native writes are confirmed and truthful
- tests match [references/ACCEPTANCE.md](references/ACCEPTANCE.md)

For platform-specific target behavior, follow [references/IOS_IMPLEMENTATION.md](references/IOS_IMPLEMENTATION.md). For execution commands and what actually passed, follow the dated [validation evidence](references/VALIDATION_EVIDENCE.md), not a hard-coded simulator name in an older document.

## Delivery evidence and bounded validation

For every status update record the source commit, affected paths, test command/target, environment, result, and remaining gate. Distinguish source inspection, isolated reproduction, historical CI, current simulator/UI execution, live server verification, and signed physical-device/TestFlight verification. Never turn `A01`–`A25` green from a class name or unrelated unit test.

At the reviewed commit, GitHub run `42760117909` passed on 2026-11-10 UTC; its workflow selects only `Chat_Buddy_iOSTests`. It is not a UI-test, live-cloud, APNs, or TestFlight acceptance report. Recheck the workflow and commit before reusing this historical evidence.

Read the checkout reference before legacy import/export or release claims. Select acceptance scenarios relevant to the change; narrow documentation/tooling work does not trigger live model calls, account mutations, the full native/cloud release checklist, or a TestFlight upload. A documentation-only review must not claim to have repaired the Swift findings it records.
