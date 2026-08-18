# iOS TestFlight Demo Implementation Plan

**Repository:** `Luckycat133/Chat_Buddy_iOS`  
**Default branch:** `main`  
**Role:** native iOS client for the shared cloud social world

## 1. Ownership boundary

The iOS app owns:

- native SwiftUI presentation
- Sign in with Apple client flow
- local cache and offline outbox
- realtime connection
- APNs registration and deep linking
- EventKit calendar capability
- location/city permission UI
- image/media selection
- native notification and privacy settings
- TestFlight release quality

The iOS app does not own:

- character prompt compilation
- AI model calls
- attention decisions
- memory extraction
- relationship simulation
- hidden AI conversations
- world-event generation
- proactive scheduling
- hosted search/weather provider credentials

Do not port the Web `AIPipeline` into Swift. The cloud runtime is the only hosted behavior source.

## 2. Target iOS architecture

```text
SwiftUI views
    |
Feature @Observable stores
    |
Repositories
    |-------------------------|
Cloud API / WebSocket     SwiftData cache
    |                         |
Shared domain DTOs       Offline outbox/sync cursor
```

Suggested layout:

```text
Chat_Buddy_iOS/
├── App/
│   ├── AppState.swift
│   ├── AppEnvironment.swift
│   └── DeepLinkRouter.swift
├── Models/
│   ├── API/                    generated/reviewed DTOs
│   └── Local/                  SwiftData cache models
├── Networking/
│   ├── HTTPClient.swift
│   ├── AuthSession.swift
│   ├── RealtimeClient.swift
│   ├── APIError.swift
│   └── Endpoints/
├── Persistence/
│   ├── ModelContainerFactory.swift
│   ├── SyncCursorStore.swift
│   ├── OutboxStore.swift
│   └── LegacyImporter.swift
├── Repositories/
│   ├── ActorRepository.swift
│   ├── RelationshipRepository.swift
│   ├── ConversationRepository.swift
│   ├── MomentsRepository.swift
│   └── SettingsRepository.swift
├── Sync/
│   ├── SyncCoordinator.swift
│   ├── EventApplier.swift
│   └── ConflictResolver.swift
├── Capabilities/
│   ├── CalendarCapability.swift
│   ├── LocationCapability.swift
│   ├── PushNotificationService.swift
│   └── ClientActionCoordinator.swift
└── Features/
    ├── Auth/
    ├── Chats/
    ├── Contacts/
    ├── Moments/
    ├── Onboarding/
    └── Settings/
```

## 3. Replace local authority with cache

Current `ChatStore`, `MomentsStore`, and memory services persist whole datasets in UserDefaults. That is not the target for cloud mode.

### SwiftData cache

Use SwiftData for:

- actors
- relationships
- requests
- conversations
- members
- messages
- Moments
- interactions
- sync tombstones
- outbox mutations
- device-local settings

UserDefaults remains appropriate only for small preferences such as:

- UI language
- theme
- last selected tab
- non-sensitive feature flags

Keychain stores:

- refresh/session token
- device binding secret when required

Do not store:

- full message arrays in UserDefaults
- model API keys for hosted TestFlight
- hidden AI chat content
- authoritative relationship narratives unless delivered to the human client for a valid UI need

## 4. API models and contract discipline

The server publishes OpenAPI/JSON Schema. Maintain Swift DTOs that match the versioned contract.

Requirements:

- explicit coding keys
- ISO-8601 date strategy with fractional seconds support
- unknown enum fallback where forward compatibility is required
- no force unwraps for server data
- payload version field on sync/export
- fixture tests using server-provided JSON samples

Separate:

- `RemoteActorDTO`
- `CachedActor`
- `ActorViewData`

Do not use network DTOs directly as long-lived SwiftUI state.

## 5. Authentication

### Sign in with Apple

Flow:

1. user taps Sign in with Apple
2. obtain identity token and authorization code
3. send to `/v1/auth/apple`
4. server verifies and returns session
5. store refresh/session material in Keychain
6. register device and APNs token
7. run initial sync
8. route to Mira chat or existing Chats list

Support:

- cancelled sign-in
- revoked credential
- token refresh
- account deletion
- sign out on one device
- session revoked by another device

Internal TestFlight fallback can use an invite/test account, hidden outside internal builds.

## 6. Root navigation

Replace Dashboard-first navigation with:

1. Chats
2. Contacts
3. Moments
4. Me

Use native iOS 26 navigation and glass effects without sacrificing clarity.

### Chats tab

- default app landing tab
- unread and proactive messages prominent
- private and group conversations
- pull-to-refresh triggers delta sync, not full reload
- search
- connection/offline banner only when relevant

### Contacts tab

Sections:

- Requests
- Human friends
- AI friends
- Groups

Actions:

- accept/decline
- send request
- invite human via share sheet/link/code
- block/delete
- manage unsolicited AI DM permission
- open fixed public AI profile
- set private remark

### Moments tab

- familiar-actor feed
- compose text/image
- reactions/comments
- audience indicator
- notification/deep-link support
- no public discovery

### Me tab

- account/devices
- quiet hours
- notification controls
- AI DM controls
- location/weather
- calendar
- blocked actors
- export
- delete account
- internal diagnostics in debug/TestFlight developer mode

## 7. Mira onboarding

Do not use the existing multi-page onboarding tutorial as the primary product onboarding.

After auth:

- sync creates or returns Mira direct conversation
- route into chat
- show actual unread Mira message
- conversation proceeds through server onboarding state
- UI remains ordinary chat
- permission prompts occur only when context makes them useful
- once complete, subsequent launches go to Chats

The old welcome pages may be reduced to:

- one brand/value screen
- privacy summary
- Sign in with Apple

Mira should not render as a special system bubble.

## 8. Chat UI

### Message timeline

Support:

- human text
- AI text
- image
- invitation cards
- action confirmation/result
- replies
- streaming placeholder
- failed/queued messages
- unread divider
- multi-message bursts

AI and human messages use consistent social styling. Do not render professional tool cards for weather/search unless a compact source disclosure is needed.

### Composer

- send individual messages immediately
- publish typing state
- allow rapid consecutive messages
- do not lock composer while AI is responding
- support @mentions in groups
- show quoted reply
- retry failed outbox item
- image attachment

The server decides burst closure. The client may send `typing.started/stopped` hints but must not make AI decisions locally.

### Streaming

`RealtimeClient` receives:

- started
- delta
- completed
- failed

The cache holds one placeholder message per server ID. Apply deltas on main actor with throttling. Final server message replaces the stream buffer.

### Group behavior

- pending invitations visible
- active member list excludes declined/pending members from normal presence
- each invitee can accept/decline
- AI decisions arrive asynchronously
- no UI text suggesting a fixed AI response count
- user can leave or mute

## 9. Realtime client

Use `URLSessionWebSocketTask` or the selected native transport.

Responsibilities:

- authenticate
- heartbeat
- reconnect with bounded backoff
- resume from last event ID
- detect event gap
- call delta sync
- deduplicate
- expose connection state
- pause/reconnect on app lifecycle changes

No event may be applied twice.

## 10. Sync coordinator

### Initial sync

1. load cached UI immediately
2. refresh auth
3. fetch `/v1/sync?cursor=`
4. apply ordered changes in one SwiftData transaction
5. advance cursor
6. connect realtime
7. flush outbox

### Incremental sync

- upsert by server ID
- apply tombstones
- preserve pending local mutations
- reconcile by client idempotency key
- never replace the entire local store from a stale snapshot

### Outbox

Mutation states:

- queued
- sending
- accepted
- failed
- conflict

Supported offline actions for demo:

- send message
- react/comment draft
- Moment draft/post queue when media is local
- friend/group decision queue where safe

Invitation acceptance should show pending state until server confirms.

## 11. Push notifications and deep links

Register APNs token after permission.

Push types:

- private message
- group message
- proactive message
- friend request
- group invitation
- Moment reaction/comment
- selected character Moment

Payload includes opaque route data, not sensitive hidden AI content.

Deep links:

```text
chatbuddy://chats/{conversationId}
chatbuddy://requests/{requestId}
chatbuddy://groups/invitations/{invitationId}
chatbuddy://moments/{momentId}
```

Opening push:

1. authenticate
2. sync
3. resolve route
4. mark visible content read
5. show graceful fallback if deleted or blocked

Quiet hours and per-character mute are enforced server-side; local presentation still respects iOS Focus/notification state.

## 12. Contacts and requests

### Human invite

Use share sheet for invite link/code.

### AI request

A human can send a request from an official profile or group interaction. The character decides server-side. UI shows pending and later outcome.

### AI-to-human request

Appears in Requests. Human may accept, decline, ignore, or change AI DM permissions.

### Deletion and block

- delete removes active friendship but preserves history
- block stops contact and visibility
- account deletion is separate
- UI explains the difference without technical language

## 13. Group creation and invitation confirmation

Wizard:

1. enter optional name/purpose
2. select actors
3. review invited list
4. send proposal
5. show pending decisions
6. open group when created/active

AIs and humans both confirm. Show natural status:

- Mira accepted
- Max is considering
- Alice declined

Do not expose model decision metadata.

AI-created group proposals arrive as invitation notifications. The user must confirm.

## 14. Same-template public identity

In a shared group, the server returns the canonical public actor ID. iOS renders one character.

Private chats remain distinct relationship routes as returned by server. The client must not attempt to merge message history locally.

When identity-link updates arrive:

- update actor references transactionally
- preserve conversation IDs
- update avatar/name projections
- do not duplicate chat rows
- keep private caches scoped to their server conversation

## 15. Moments

### Feed

- cursor pagination
- cache-first render
- actual view event after meaningful display
- image prefetch
- reactions/comments optimistic then reconcile
- audience indicator
- delete own post
- report/block human content

### Compose

- PhotosPicker
- image compression
- upload progress
- accessible audience selection
- draft preservation
- offline upload queue where feasible

### AI posts

Render exactly like other familiar contacts. Do not label them as generated on every card unless required by product policy. Actor profile already identifies character type where appropriate.

A later chat reference uses server memory/events, not local feed scraping.

## 16. Client capabilities

### Calendar with EventKit

Use EventKit.

Permission flow:

- explain benefit in context
- request only after user or character invokes calendar behavior
- read selected calendars according to settings
- do not upload full calendar content without clear consent
- server receives the minimum normalized context needed
- any create/update/delete shows a confirmation sheet
- after EventKit result, send `calendar action result` to server

Confirmation sheet includes:

- action
- title
- date/time
- calendar
- notes
- initiating character

AI text must not say “done” until success is confirmed.

### Weather/location

Prefer user-selected city. Approximate location is optional.

- request location only after user action
- avoid continuous location
- send minimal location/city to weather endpoint
- show permission denied fallback
- allow manual city

### Lightweight search

Server performs retrieval. iOS displays:

- natural character response
- optional compact source row
- expandable sources
- failure state

No browser automation or local deep-research workflow.

## 17. Data export and deletion

### Export

Request server export:

- messages
- Moments
- contacts/relationships
- user-visible memory-derived data where appropriate
- settings
- media manifest

Download archive and present share sheet.

### Legacy local import

One-time importer reads existing UserDefaults data:

1. detect
2. preview
3. map personas
4. upload normalized batch
5. show result
6. mark migration complete

Never upload stored API credentials.

### Delete account

- explicit destructive confirmation
- explain that unfriend and account deletion differ
- call server deletion
- clear Keychain
- destroy SwiftData store
- unregister push token
- return to auth

## 18. Internal diagnostics

Debug/TestFlight developer mode may show:

- API environment
- sync cursor
- WebSocket state
- outbox items
- last applied event IDs
- proactive notification route
- cache counts
- legacy import state

Do not show:

- hidden AI transcripts
- chain-of-thought
- raw provider keys
- private memory from unrelated actors
- relationship scores

## 19. Accessibility and native quality

Every new screen must support:

- Dynamic Type
- VoiceOver labels and reading order
- 44pt minimum interactive targets
- Reduce Motion
- sufficient contrast
- keyboard navigation where iPad hardware keyboard applies
- loading, empty, offline, error, denied, and blocked states
- English and Simplified Chinese

Use Liquid Glass for hierarchy and integration, not as decorative blur over all content.

## 20. Tests

### Unit

- DTO decoding
- sync event application
- idempotent outbox reconciliation
- identity-link projection
- deep-link routing
- permission state
- calendar action confirmation
- notification routing
- legacy import mapping

### Integration

- URLProtocol HTTP stubs
- WebSocket event fixture application
- SwiftData migration
- auth refresh
- account deletion cleanup

### UI tests

Cover scenarios from `ACCEPTANCE.md`:

- first Mira message
- onboarding through chat
- friend request
- mixed group pending/accepted
- rapid multi-message input
- group memory appears in private chat
- human invite
- AI DM denied
- Moment post/comment
- proactive push deep link
- calendar confirmation
- offline send/reconnect
- block and account deletion

### Build checks

```bash
xcodebuild -project Chat_Buddy_iOS.xcodeproj \
  -scheme Chat_Buddy_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build

xcodebuild -project Chat_Buddy_iOS.xcodeproj \
  -scheme Chat_Buddy_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test
```

## 21. Implementation sequence

### P0 — cloud client foundation

- auth
- HTTP client
- Keychain
- SwiftData cache
- sync
- realtime
- APNs/device registration

### P0 — core social UI

- Chats root
- Contacts
- requests
- direct messages
- mixed groups
- invitations

### P0 — companion experience

- Mira onboarding
- AI stream rendering
- rapid message bursts
- proactive push
- group-to-private continuity

### P0 — Moments

- feed
- compose
- interactions
- deep links

### P1 — human friend completeness

- invitation link
- human DMs
- mixed group creation
- block/report

### P1 — capabilities

- EventKit
- weather/location
- search sources

### P1 — data rights

- export
- legacy import
- delete account
- device management

## 22. iOS definition of done

An iOS change is complete when:

- no companion decision logic was duplicated from server
- server contract fixtures decode
- cache and offline behavior are correct
- UI has loading/error/offline/denied states
- privacy permissions are contextual
- external actions require confirmation
- deep links work from cold and warm launch
- English and Simplified Chinese are complete
- accessibility is reviewed
- unit/UI tests cover the changed flow
- simulator build and tests pass
- no hosted secret or user API key is embedded
