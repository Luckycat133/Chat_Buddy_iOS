[English](CHANGELOG.md) | [简体中文](CHANGELOG_zh.md)

# Changelog — Chat Buddy iOS

All notable changes to the iOS app are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [0.9.0] — 2026-02-28

### Added — T11 Character Memory System

Per-persona long-term memory: the AI learns facts about the user during conversation, persists them across sessions, and recalls them to give each relationship a sense of continuity.

#### Data Model
- **`Models/CharacterMemory.swift`** — Two new types:
  - `MemoryCategory` enum (`preference` / `fact` / `event`). Each case exposes `label` / `labelZh`, a `Color` (blue / green / purple), and `importanceLabel(_ n: Int)` which maps importance 1–10 to emoji indicators (⬜ 🟨 🟧 🟥 ⭐).
  - `CharacterMemory` struct (Identifiable, Codable): `id` (UUID), `personaId`, `fact`, `category`, `importance` (1–10), `createdAt`, `lastRecalledAt`, `isForgotten` (soft-delete flag).
  - `MemoriesData: Codable` — persistence wrapper at key `chat-buddy:memories`.

#### New Services
- **`Services/Memory/MemoryService.swift`** — `@Observable final class`:
  - `memories(for:)` — active (non-forgotten) records for a persona, newest-first.
  - `relevantMemories(for:limit:)` — top-N records sorted by importance desc then recency; updates `lastRecalledAt` on each returned record and persists.
  - `addMemory(personaId:fact:category:importance:)` — deduplication guard: computes Jaccard word-overlap between the new fact and all existing active facts; if any similarity score exceeds **0.85**, the insertion is skipped.
  - `forgetMemory(id:personaId:)` — soft-deletes a single record.
  - `forgetAll(for:)` — hard-deletes all records for a persona (used by Clear All).
  - `applyDecay()` — runs on init; soft-deletes any memory whose `(now − lastRecalledAt)` exceeds `importance × 3 days` (e.g. importance 5 → 15-day survival window).
  - Persisted as `MemoriesData` at `chat-buddy:memories` via `StorageService`.

- **`Services/Memory/MemoryInjector.swift`** — Static enum with two helpers:
  - `memoryBlock(for:service:isZh:)` — calls `relevantMemories(limit: 10)`, formats them as a `• fact` bullet list under an "WHAT YOU REMEMBER ABOUT THE USER:" / "你对用户的记忆：" header. Returns `""` when no memories exist or `memoryService` is `nil`.
  - `memorySaveHint(isZh:)` — returns a system-prompt instruction block telling the AI to emit `[MEMORY_SAVE: category=preference importance=7]fact[/MEMORY_SAVE]` tags when the user reveals important personal information.

#### Modified Services
- **`Services/Chat/AIPipeline.swift`**:
  - `run()` gains `memoryService: MemoryService? = nil` (optional, no impact when nil).
  - `Result` gains `newMemories: [ExtractedMemory]` (empty array when no tags found). `ExtractedMemory` carries `fact`, `category`, `importance`.
  - `buildSystemPrompt` injects `MemoryInjector.memoryBlock(...)` after the affinity hint and appends `MemoryInjector.memorySaveHint(isZh:)` at the end of the prompt.
  - `parseResponse(_:isZh:)` calls `extractMemories(from:)` first: scans for all `[MEMORY_SAVE: category=X importance=N]...[/MEMORY_SAVE]` blocks, strips them from the displayed message text, parses attributes via `parseMemoryAttributes(_:)`, and populates `Result.newMemories`.

- **`Features/Chats/ChatViewModel.swift`**:
  - `sendMessage()` gains `memoryService: MemoryService? = nil`.
  - `fetchResponse()` gains `memoryService: MemoryService? = nil`; passes it to `AIPipeline.run()`.
  - After successful response: iterates `result.newMemories` and calls `memoryService?.addMemory(...)` for each extracted fact.

#### New View
- **`Features/Chats/MemoriesView.swift`** — Sheet presented from the `ChatView` toolbar menu:
  - `NavigationStack` with title "Memories" / "角色记忆".
  - List of active memories sorted `lastRecalledAt` desc. Each row: category color pill badge + importance emoji, fact text (`.headline` weight), created date · relative recalled time.
  - Swipe-to-delete → `memoryService.forgetMemory(id:personaId:)`.
  - Toolbar leading **"Add Memory"** button → expands an inline form section (free-text `TextField`, `Picker` for category, `Stepper` for importance 1–10); Add commits via `addMemory`.
  - Toolbar trailing **"Clear All"** (destructive, with confirmation alert) → `forgetAll(for:)`.
  - Empty state: `brain.head.profile` SF Symbol icon + localized description.

#### Integration
- **`ChatView`** — `@Environment(MemoryService.self)`, `@State private var showMemories = false`. Toolbar `···` menu gains a **"Memories"** item (`brain.head.profile` icon). `.sheet(isPresented: $showMemories)` → `MemoriesView(personaId:).presentationDetents([.medium, .large])`. `send()` passes `memoryService: memoryService` to `ChatViewModel.sendMessage`.
- **`Chat_Buddy_iOSApp`** — `@State private var memoryService = MemoryService()` added; injected via `.environment(memoryService)`.
- **`Localizable.xcstrings`** — 11 new keys (en + zh-Hans): `memories_title`, `memories_empty`, `memories_empty_desc`, `memories_add`, `memories_delete`, `memories_clear`, `memories_clear_confirm`, `memories_clear_message`, `memories_category_preference`, `memories_category_fact`, `memories_category_event`.

### Build
`** BUILD SUCCEEDED **` — 0 errors, 0 warnings on iPhone 17 Pro simulator.

---

## [0.8.0] — 2026-02-28

### Added — T09 Immersive Background System

Gradient wallpaper layer for the chat view, with per-chat overrides and a global default picker.

#### Data & Services
- **`Models/ChatBackground.swift`** — `ChatBackgroundPreset` Codable struct with `id`, `name`, `nameZh`, `startHex`, `endHex`. Ten presets: Default, Aurora, Sunset, Ocean, Rose, Forest, Midnight, Sakura, Golden, Cosmos. `preset.gradient(opacity:)` returns a `LinearGradient?` (nil for Default).
- **`Services/Background/BackgroundStore.swift`** — `@Observable final class`. `globalPresetId: String` (default `"none"`), `chatPresets: [String: String]` (sessionId → presetId). `resolvedPreset(for:)` applies chat override → global fallback. Persisted at `chat-buddy:backgrounds`.

#### Views
- **`Features/Settings/Appearance/BackgroundPickerView.swift`** — Grid of 90-pt gradient preview cards with checkmark overlay. Accepts optional `sessionId` parameter: if provided, sets per-chat override and shows a "Reset to Default" row; otherwise sets global theme.

#### Integration
- `ChatView` wraps its body in a `ZStack`. The bottom layer renders `preset.gradient()` full-bleed behind the message list and input bar. The glass materials on bubbles and the input tray let the gradient show through.
- Chat toolbar `···` menu gains a **"Chat Background"** `NavigationLink` → `BackgroundPickerView(sessionId:)`.
- **Settings → Appearance** gains a **"Chat Background"** row → global `BackgroundPickerView()`.

---

### Added — T10 Social & Interaction Features

User profile, points economy, achievements, daily check-in, gifts, and mini-games.

#### Models
- **`Models/UserProfile.swift`** — `UserProfile` Codable struct: `nickName`, `avatarEmoji` (one of 12 predefined emojis), `signature`.
- **`Models/Achievement.swift`** — Four types:
  - `AchievementDefinition` (10 static entries): id, bilingual name/description, SF Symbol icon, points, category (social / streak / gifts).
  - `AchievementRecord` Codable: id + `unlockedAt: Date`.
  - `GiftDefinition` (6 static entries): emoji, bilingual name, `cost` (points), `intimacyBoost`.
  - `DailyTaskDefinition` (6 static entries) + `DailyTaskState` Codable: date string, `completed: [String]`, `progress: [String: Int]`, `chatPersonasToday: [String]`.

#### Services
- **`Services/Social/UserProfileStore.swift`** — `@Observable`. `update(nickName:avatarEmoji:signature:)`. Persisted at `chat-buddy:userProfile`.
- **`Services/Social/SocialService.swift`** — `@Observable final class`. Core social state machine:
  - **Points**: `addPoints(_:)`, `spendPoints(_:) → Bool`.
  - **Check-in**: `checkIn() → Int` (base 10 pts + 2×streak bonus capped at 20, streak auto-calculated from date history).
  - **Achievements**: `unlockAchievement(_:) → Bool` (idempotent, auto-awards points).
  - **Daily tasks**: `updateTaskProgress(_:increment:)` (auto-completes + awards on hitting target); special handling for `task_chat3` via `chatPersonasToday`.
  - **Hooks**: `onMessageSent(personaId:chatStore:)`, `onGiftSent(intimacyAfter:)`, `onGamePlayed()`, `onMomentLiked()`, `onMomentsPosted(total:)`, `onIntimacyMaxed()`. Persisted at `chat-buddy:social`.
- **`Services/Chat/AffinityService`** — Added `addBoost(_ amount: Int, for personaId: String)` for direct intimacy boosts from gifts (bypasses 5-minute cooldown).

#### Views
- **`Features/Settings/Profile/UserProfileView.swift`** — Horizontal avatar emoji grid (scrollable), nickname and signature text fields, save button with animated "Saved! ✓" confirmation.
- **`Features/Achievements/AchievementsView.swift`** — Stats header (unlocked/points/streak), category filter pills (All / Social / Streak / Gifts), achievement grid (locked = grayscale 0.7), daily tasks section with `ProgressView` bars.
- **`Features/Achievements/DailyCheckInView.swift`** — Stat cards (streak / points / achievements), 7-day calendar with filled circles + weekday labels, daily task list with per-task progress, animated check-in button (shows "Checked in! +N pts 🎉" on success).
- **`Features/Chats/Components/GiftPanelView.swift`** — Points balance header, intimacy progress bar, 3-column gift grid (grayed-out if unaffordable), sends a gift chat message on confirm, calls `socialService.onGiftSent`, `affinityService.addBoost`.
- **`Features/Chats/Components/RockPaperScissorsView.swift`** — Score board, 3-second countdown, result display (+10 pts per win), Play Again / Finish buttons.
- **`Features/Chats/Components/NumberGuessView.swift`** — 7-attempt pill indicator, number pad input, Too High / Too Low / Correct feedback, +30 pts on win.
- **`Features/Dashboard/Widgets/SocialWidget.swift`** — Full-width `GlassCard` showing points / streak / achievements stats + Quick Check-in button + Achievements sheet button.

#### Integration
- `Chat_Buddy_iOSApp` — injects `backgroundStore`, `userProfileStore`, `socialService`.
- `ChatView` toolbar menu — **Send a Gift** → `GiftPanelView` sheet; **Play a Game** submenu → RPS or Number Guess.
- `ChatViewModel.sendMessage` — gains optional `socialService: SocialService?` parameter; calls `onMessageSent(personaId:chatStore:)` after each user message.
- `DashboardView` — `SocialWidget` placed below `TodaysPickWidget`.
- `SettingsView` — **Profile** section (UserProfileView) + **Social & Achievements** section (DailyCheckInView, AchievementsView) + **Chat Background** row under Appearance.
- **21 new xcstrings keys** (en + zh-Hans): `achievements_title`, `achievements_points`, `background_title`, `background_reset`, `checkin_title`, `checkin_button`, `checkin_done`, `done`, `game_title`, `game_rps`, `game_number`, `gift_title`, `gift_no_points`, `profile_title`, `profile_avatar`, `profile_nickname`, `profile_signature`, `profile_save`, `profile_saved`, `settings_profile`, `settings_social`.

---

## [0.6.0] — 2026-02-25

### Added — T08 Moments / Social Feed

A full WeChat-style 朋友圈 social feed powering the Moments tab, replacing the former placeholder.

#### Data Layer
- **`Models/MomentPost.swift`** — Three Codable types:
  - `MomentComment` — comment with `authorId`, `content`, `createdAt`, and an optional `ReplyReference` (commentId + authorId + authorName) for threaded replies.
  - `MomentPost` — post with `authorId`, `content`, `imagePaths` (filenames), optional `location`, `createdAt`, `likes: [String]`, `reactions: [String: [String]]` (emoji → user IDs), and `comments: [MomentComment]`.
  - `MomentsData` — top-level persisted blob: `posts`, `lastAIPostTime`, `draftText`, `draftLocation`, `lastStoryEventDate`.

- **`Services/Moments/MomentsStore.swift`** — `@Observable final class MomentsStore`:
  - CRUD: `createPost(content:imageData:location:authorId:)`, `deletePost(id:)`, `toggleLike(postId:userId:)`, `addReaction(postId:emoji:userId:)`, `addComment(postId:content:authorId:replyTo:)`, `deleteComment(postId:commentId:)`.
  - Draft: `saveDraft(text:location:)`, `clearDraft()`.
  - Orchestrator support: `recordAIPost(personaId:)`, `recordStoryEvent(date:)`, `addHistoricalPost(_:)` (inserts + re-sorts newest-first for seeding).
  - Image helpers: `saveImage(_:)` — compresses to max 600 px JPEG 0.7, saves to `Documents/moments/<UUID>.jpg`; `deleteImage(_:)` removes the file; `imageURL(for:)` returns the full URL.
  - Persists a single `MomentsData` blob at `chat-buddy:moments` via `StorageService`.

- **`Services/Moments/MomentsService.swift`** — Static helpers:
  - `reactionEmojis: [String]` — 6 supported reactions: 😂 ❤️ 👍 🔥 😮 😢.
  - `aiLocations: [String: [String]]` — per-persona location pools matching each character's personality.
  - `SeasonalEvent` — 13 holidays/events (New Year, Valentine's, Halloween, Christmas, Miku Day, etc.).
  - `personaBirthdays: [String: String]` — compiled from `PersonaStore` (`id → "MM-dd"`).
  - `timeContext() → String` — maps current hour to morning/afternoon/evening/night.
  - `todayEvents() → TodayEvents` — returns which persona birthdays fall today + any matching seasonal event.
  - AI prompt builders: `generatePostPrompt`, `generateCommentPrompt`, `generateBirthdayPrompt`, `generateHolidayPrompt`.

- **`Services/Moments/MomentsOrchestrator.swift`** — Static enum driving all AI activity:
  - `run(store:configStore:)` — called from `.task` in `MomentsView`: seeds 4 posts when feed is empty, checks story events for today (birthday + holiday posts), then enters a 5-minute periodic loop where each social companion posts after a random 30–120 min cooldown.
  - `reactToUserPost(postId:store:configStore:)` — after user posts: waits 15–40 s then has 2–4 personas like/react; waits 30–90 s then has 1–2 personas comment.

#### Views
- **`Features/Moments/MomentsView.swift`** — Main feed replacing `MomentsPlaceholderView`:
  - Quick-compose tap row (avatar + placeholder text → opens composer).
  - Hashtag filter banner (shown when a tag is active; `✕` to clear).
  - `LazyVStack` of `MomentCardView` items, paginated at 10 per page with a "Load More" button.
  - Sheets for composer, comments, and repost driven by `PostID: Identifiable` wrapper (avoids stale struct copies).
  - `.task` launches `MomentsOrchestrator.run`.

- **`Features/Moments/MomentCardView.swift`** — Single post card:
  - Header: persona avatar circle (initial + accent color), name, relative timestamp, optional location badge.
  - Content: `ParsedTextView` renders plain text with tappable `#hashtag` pills below.
  - Photo grid: 1 photo = full-width; 2+ photos = 2-column grid (up to 4 shown).
  - Likes strip: `❤️ Name1, Name2 +N` (up to 3 names).
  - Reaction pills: toggleable per-emoji counts; hidden when count is zero.
  - Action row: Like toggle ❤️ | Reaction picker `Menu` | Comment 💬 | Share ↗.
  - Last 3 comments inline; "View all N comments" button when more exist.
  - Context menu "Delete Moment" for the current user's own posts.
  - **iOS 26 note**: comment text uses `VStack` layout instead of deprecated `Text + Text` concatenation.

- **`Features/Moments/PostComposerView.swift`** — Full-height sheet:
  - Auto-focuses `TextEditor` on appear.
  - `PhotosPicker` (max 4 images); selected photos displayed in a 2-column preview grid with per-image `✕` remove buttons.
  - Location picker sub-sheet with 10 preset locations + free-text custom entry.
  - Draft restore banner (auto-hides after 3 s) with "Discard" button.
  - `.task(id: text)` 500 ms debounce → `store.saveDraft(...)`.
  - Calls `MomentsOrchestrator.reactToUserPost` asynchronously after posting.

- **`Features/Moments/CommentsView.swift`** — Half-height sheet:
  - Accepts `postId: String`; reads live from `MomentsStore` so new comments appear instantly.
  - Comment list with swipe-to-delete for own comments.
  - Reply mode: tap any comment to set `replyToComment`; a "Replying to Name ✕" strip appears above the input.
  - Bottom input bar (pill `TextField` + send button).

- **`Features/Moments/RepostSheet.swift`** — Half-height sheet:
  - Lists all `ChatStore.sessions` with persona avatar and name.
  - Tap → prepends `"[Shared Moment · Name]\nContent"` as a `.user` message via `chatStore.appendMessage`.
  - Shows `✓` check mark on the tapped row; auto-dismisses after 1.2 s.

#### Wiring & Localization
- **`Chat_Buddy_iOSApp.swift`** — `MomentsStore` added as `@State` and injected via `.environment(momentsStore)`.
- **`Navigation/RootTabView.swift`** — Moments tab now renders `MomentsView()`.
- **`Localizable.xcstrings`** — 25 new keys (`moments_*`) in both `en` and `zh-Hans`.

### Build
`** BUILD SUCCEEDED **` — 0 errors, 0 warnings on iPhone 17 Pro simulator.

---

## [0.5.0] — 2026-02-25

### Added — T07 Advanced Chat Features

#### Data Models
- **`Models/ChatMessage.swift`** — Added `timestamp: Date` (auto-assigned at init; backward-compatible custom `Codable`) and `quotedMessageId: String?` for reply threading.
- **`Models/ChatSession.swift`** — Added `isPinned: Bool` (default `false`; backward-compatible custom `Codable`).
- **`Models/Bookmark.swift`** — New `Identifiable, Codable` struct: `messageId`, `sessionId`, `content`, `personaId`, `bookmarkedAt: Date`.

#### New Services
- **`Services/Chat/BookmarkService.swift`** — `@Observable final class`. `isBookmarked(_:)`, `toggleBookmark(_:sessionId:personaId:)`, `removeBookmark(messageId:)`, `clear()`. Persisted at `chat-buddy:bookmarks`.
- **`Services/Chat/DraftService.swift`** — `@Observable final class`. Stores `[String: DraftEntry]` (text + `savedAt` + optional `quotedMessageId`) at `chat-buddy:drafts`. 7-day expiry purge on init. `save(text:quotedMessageId:for:)`, `clear(for:)`, `draft(for:)`.

#### ChatStore Enhancements
- `pinSession(_:)` / `unpinSession(_:)` — updates `isPinned` and re-sorts pinned sessions to the top (stable sort).
- `deleteMessage(id:in:)` — removes a single message by ID from a session.
- `searchMessages(query:in:)` — case-insensitive filter of visible messages.

#### New Components
- **`Features/Chats/Components/QuotedMessageView.swift`** — Compact reply-preview strip: left accent border, sender name, 1-line content preview, optional `✕` dismiss button (omitted when shown inside bubbles).
- **`Features/Chats/BookmarksSheet.swift`** — Session-scoped bookmark list. Swipe-to-delete; tap → `onSelect(Bookmark)` callback for scroll-to.

#### Chat UI Upgrades
- **`MessageBubble`** — Timestamp (`Text(msg.timestamp, style: .time)`) below bubble. Long-press context menu: Copy / Bookmark / Reply / Delete. Quoted-message preview strip inside bubble. New params: `messages:[ChatMessage]`, `sessionId:String`, `onQuote:`, `onDelete:`.
- **`MessageInputView`** — Optional `quotedMessage: ChatMessage?` shows `QuotedMessageView` strip above the input; `onClearQuote:` callback dismisses it.
- **`ChatView`** — Bookmarks toolbar button (leading nav bar). Search toggle + search bar. `ShareLink` export. Draft loaded on `.onAppear`. `.task(id: viewModel.inputText)` debounce-saves draft. `scrollToMessageId` state for bookmark-triggered scroll.
- **`ChatsView`** — Two sections (Pinned / All) with section headers. Context menu adds Pin/Unpin; pin badge (`pin.fill`) shown in session row.

### Changed
- **`Chat_Buddy_iOSApp.swift`** — `BookmarkService` and `DraftService` added as `@State` and injected via `.environment(...)`.

### Build
`** BUILD SUCCEEDED **` — 0 errors, 0 warnings on iPhone 17 Pro simulator.

---

## [0.4.1] — 2026-02-24

### Fixed — Deep Implementation Audit (T01-T06)

Performed a full implementation audit across all completed phases. The following real functionality gaps were identified and resolved:

- **`Features/Dashboard/Widgets/RecentChatsWidget.swift`** — Replaced "Coming Soon" stub with a live widget that reads `ChatStore` from environment and displays up to 3 recently updated sessions, each with persona avatar (initial + accent color), localized name, and last message preview.
- **`Features/Dashboard/Widgets/StatsWidget.swift`** — Replaced hardcoded `0` placeholders with real computed values: `totalMessages` (sum of all visible messages across sessions), `totalChats` (sessions with at least one message), and `streakDays` (consecutive calendar days with activity, computed from `session.updatedAt`). Cached `DateFormatter` as `private static let` per CLAUDE.md.
- **`Features/Dashboard/Widgets/QuickActionsWidget.swift`** — "New Chat" button now calls an `onNewChat: () -> Void` callback (passed from `DashboardView`) that sets `AppState.selectedTab = .chats`, switching the tab programmatically.
- **`Features/Dashboard/DashboardView.swift`** — Added `@Environment(ChatStore.self)` and `@Environment(AppState.self)`. Passes `onNewChat` closure to `QuickActionsWidget`. `StatsWidget` and `RecentChatsWidget` now read from environment directly (no viewModel pass-through).
- **`Features/Dashboard/DashboardViewModel.swift`** — Removed fake `totalMessages: Int { 0 }`, `totalChats: Int { 0 }`, `streakDays: Int { 0 }` properties. Kept `greetingKey`, `dateString`, `todaysPick`.
- **`App/AppState.swift`** — Added `var selectedTab: AppTab = .dashboard` for app-wide tab switching.
- **`Navigation/RootTabView.swift`** — Reads `AppState` from environment; binds `TabView(selection:)` to `$appState.selectedTab` via `@Bindable`.
- **`Services/API/AIClient.swift`** — Removed dead `configure(with:)` method and `private var client: APIClient?` property that were never used (every call always created a new `APIClient(config:)` directly).

### Build
`** BUILD SUCCEEDED **` — 0 errors, 0 warnings on iPhone 17 Pro simulator.

---

## [0.4.0] — 2026-02-24

### Added — T06 Affinity & Mood System

- **`Models/AffinityLevel.swift`** — `AffinityLevel` enum (5 tiers: `acquaintance` → `friend` → `goodFriend` → `closeFriend` → `soulmate`, score 0–100). Each tier exposes: `label` / `labelZh`, `color` (silver → sky → teal → pink → gold), `promptHint` / `promptHintZh` for system-prompt injection. `AffinityLevel.level(for score:)` maps a raw score to the correct tier. `localizedLabel(isZh:)` selects EN/ZH at runtime.
- **`Services/Chat/AffinityService.swift`** — `@Observable final class AffinityService`: stores per-persona affinity scores (`[String: Int]`, 0–100) in UserDefaults under `chat-buddy:intimacy`. `addChatIntimacy(for:)` adds +1 per persona per 5-minute cooldown window (in-memory `[String: Date]` tracker, not persisted). `score(for:)` and `level(for:)` are O(1) reads. Capped at 100.

### Changed

- **`Services/Chat/AIPipeline.swift`** — `run(session:persona:config:aiLanguageCode:intimacyLevel:)` gains an `intimacyLevel: Int` parameter (default `1`). `buildSystemPrompt` injects a `RELATIONSHIP:` hint derived from `AffinityLevel(rawValue: intimacyLevel)`, placed after the mood hint in both EN and ZH prompts. The hint tells the AI how intimately to respond (formal acquaintance → affectionate soulmate).
- **`Features/Chats/ChatViewModel.swift`** — `sendMessage(...)` gains `affinityService: AffinityService` parameter. After appending the user message, calls `affinityService.addChatIntimacy(for: persona.id)` then reads the current level and passes `intimacyLevel` into `fetchResponse → AIPipeline.run`.
- **`Features/Chats/ChatView.swift`** — Reads `AffinityService` from environment. Toolbar principal item appends `· [Level Name]` (color-coded) after the mood label when score > 0. Empty-state hint shows a `heart.fill` badge with level name + `score/100` when affinity has been earned.
- **`Chat_Buddy_iOSApp.swift`** — `AffinityService` added as `@State` and injected via `.environment(affinityService)`.

---

## [0.3.0] — 2026-02-24

### Added — T05 AI Pipeline & Persona System

- **`Services/Chat/MoodService.swift`** — `MoodService` enum: five moods (`happy`, `calm`, `excited`, `tired`, `melancholy`). `currentMood(for:)` maps the current hour to a mood candidate pool and selects deterministically using a persona ID hash, so every persona has a unique but stable mood within the same hour. Each mood exposes `emoji`, `localizedLabel(isZh:)`, `promptHint`, and `promptHintZh`.
- **`Services/Chat/AIPipeline.swift`** — `AIPipeline` enum: replaces the inline API call in `ChatViewModel`. Responsibilities: (1) **context compression** — when `displayMessages.count > 15`, only the last 8 messages are passed to the API; (2) **minimum response delay** — after the API returns, sleeps for `max(0, persona.minimumResponseDelay − elapsed)` seconds so fast responses feel natural rather than instant; (3) **enhanced system prompt** — injects persona traits + current mood hint; (4) **`[SILENCE]` parsing** — returns `wasSilent: true`, causing `ChatViewModel` to skip appending any message; (5) **`[MULTI:msg1|msg2]` parsing** — splits the response into multiple strings delivered with an 0.8 s inter-message pause.

### Changed

- **`Models/Persona.swift`** — Added `minimumResponseDelay: Double` computed property: social companions draw from `1.0–2.5 s`, task agents from `0.4–1.2 s`, using `Double.random(in:)` for natural variation per turn.
- **`Features/Chats/ChatViewModel.swift`** — `fetchResponse(...)` now delegates fully to `AIPipeline.run(session:persona:config:aiLanguageCode:)`. Removed the inline `buildSystemPrompt` method. `CancellationError` is caught separately and discarded silently. `isTyping` is set to `false` explicitly rather than via `defer`, ensuring it stays `true` during multi-message inter-message pauses.
- **`Features/Chats/ChatView.swift`** — Navigation bar now uses a `ToolbarItem(placement: .principal)` showing persona name + mood emoji and label (replaces plain `.navigationTitle`). The empty-state hint also displays the current mood below the persona name.

---

## [0.2.0] — 2026-02-24

### Added — T04 Chat Engine & Message System

- **`Models/ChatSession.swift`** — New `ChatSession` struct: persists a conversation (id, personaId, messages array, createdAt, updatedAt). `displayMessages` filters out system prompts for UI rendering; `lastMessage` drives list previews.
- **`Services/Chat/ChatStore.swift`** — `@Observable final class ChatStore`: single source of truth for all conversations. `getOrCreateSession(for:)` returns an existing session or creates one; `appendMessage(_:to:)` auto-promotes the chat to top of list; `clearMessages(in:)` wipes user/AI messages while preserving system state. Persisted via `StorageService` (`chatSessions` key).
- **`Features/Chats/ChatViewModel.swift`** — `@Observable` ViewModel: owns `inputText`, `isTyping`, and `errorMessage` state. `sendMessage(...)` appends the user message, sets `isTyping`, and fires an async task that calls `AIClient.shared.sendChatCompletion`. Builds a per-persona system prompt (bilingual: respects `resolvedAILanguage`). Keeps a rolling 20-message context window.
- **`Features/Chats/ChatView.swift`** — Full chat screen: `ScrollViewReader` auto-scrolls to newest message on send and on typing state change. Shows persona avatar + personality hint when conversation is empty. Error banner slides in from bottom. "Clear Messages" alert via toolbar `Menu`.
- **`Features/Chats/ChatsView.swift`** — Replaces `ChatsPlaceholderView`. `NavigationStack` with path-based navigation to `ChatView`. Session rows are `GlassCard`-styled with persona avatar, last message preview, and relative timestamp. Context-menu swipe-to-delete. Empty state with CTA to `PersonaPickerSheet`.
- **`PersonaPickerSheet`** — Bottom sheet with 3-column grid of all 19 personas grouped into Social Friends / Task Agents. Tapping a cell calls `getOrCreateSession` then navigates into `ChatView` after sheet dismissal.
- **`Features/Chats/Components/MessageBubble.swift`** — User messages: trailing accent-color bubble. AI messages: leading glass-card bubble with 30 pt persona initial avatar. Both support `.textSelection(.enabled)`.
- **`Features/Chats/Components/MessageInputView.swift`** — Multiline `TextField` (1–5 lines) + send button. Send disabled when text is empty or AI is typing. Top divider overlay separates input from message list.
- **`Features/Chats/Components/TypingIndicator.swift`** — Three-dot bouncing animation shown while `isTyping`. Each dot staggers by 130 ms using `repeatForever` easing.
- **`Localizable.xcstrings`** — 12 new keys: `chat_clear`, `chat_clear_confirm`, `chat_clear_message`, `chat_input_placeholder`, `chats_delete`, `chats_empty_desc`, `chats_empty_title`, `chats_new_chat`, `chats_no_messages`, `chats_yesterday`, `personas_social`, `personas_task`.

### Changed

- **`Chat_Buddy_iOSApp.swift`** — `ChatStore` added as `@State` and injected via `.environment(chatStore)`.
- **`RootTabView.swift`** — Chats tab now renders `ChatsView()` instead of the former placeholder.

### Removed

- **`ChatsPlaceholderView.swift`** — Deleted; superseded by `ChatsView`.

---

## [0.1.1] — 2026-02-23

### Fixed

- **`DashboardView`** — OLED black background now correctly activates when mode is `.system` and the system appearance is dark; previously only triggered for explicit `.dark` mode. Added `@Environment(\.colorScheme)` + `isEffectivelyDark` computed property.
- **`AccentColorManager`** — `emerald` and `amber` presets referenced the wrong localization key (`"accent_default"`); corrected to `"accent_emerald"` / `"accent_amber"`.
- **`AccentColorPickerView`** — Custom `ColorPicker` now initializes its `@State` from the saved hex value on `.onAppear`; was always defaulting to `.blue` regardless of saved state.
- **`ThemeModePickerView`** — Removed redundant Section footer that re-displayed the view title as body text.
- **`AnimationIntensityView`** — Same redundant footer pattern removed.
- **`DashboardViewModel`** — `dateString` computed property was creating a new `DateFormatter` instance on every read; replaced with a `private static let` cached instance.

### Added

- **`Localizable.xcstrings`** — `accent_emerald` (Emerald / 翡翠) and `accent_amber` (Amber / 琥珀) translation keys added for both `en` and `zh-Hans`.

### Changed

- **`DashboardView`** — Restructured layout: `TodaysPickWidget` moved out of the `LazyVGrid` into a standalone full-width hero card below the 2×2 bento grid. Greeting header gains a tinted profile icon (`.person.crop.circle.fill`).
- **`TodaysPickWidget`** — Redesigned as a horizontal hero card: layered avatar circle with `strokeBorder` accent ring, persona name in `title3` weight, prominent CTA chevron (`chevron.right.circle.fill`).
- **`FriendsWidget`** — Stacked avatars now carry `systemBackground` separation rings (standard iOS overlap treatment); trimmed to 4 visible avatars + overflow counter; persona total displayed below.
- **`BentoCardView`** — Added `.frame(minHeight: 120)` to ensure visual consistency across paired grid rows regardless of content height.
- **`GlassCard`** — Added subtle `0.12` opacity white `strokeBorder` overlay for card edge definition in light and dark modes.
- **`OnboardingView`** — Feature icons now rendered on layered concentric circle backdrops for visual depth. Page indicator upgraded from plain `Circle` dots to animated pill-shaped `Capsule` indicators with `spring` animation (active pip expands to 24 pt wide).

---

## [0.1.0] — 2026-02-23

### Added

#### T01 — Internationalization
- `Localizable.xcstrings` — String Catalog with ~80 core keys in English and 简体中文
- `LocalizationManager` — `@Observable` manager for runtime language switching without app restart
- `AppLanguage` enum: `system` (auto-detect from `Locale.preferredLanguages`), `en`, `zh-Hans`
- `AILanguage` enum: `auto` (follows UI language), `en`, `zh`
- `LocalizationManager.t(_:params:)` — translation helper with `{param}` interpolation
- `String+Interpolation.swift` — `String.interpolating(_:)` extension

#### T02 — Core Architecture & API Layer
- `APIConfig` — Codable model: `baseURL`, `apiKey`, `model`, `temperature`, `timeout`, `maxRetries`
- `APIClient` — `actor` with URLSession async/await, exponential backoff retry (429 + 5xx)
- `AIClient.shared` — singleton for OpenAI-compatible `/chat/completions`
- `APIConfigStore` — `@Observable` store with profile CRUD, persisted to UserDefaults
- `APIConfigValidator` — measures connection latency, returns `Result<Int, Error>`
- `ChatMessage` / `ChatCompletionRequest` / `ChatCompletionResponse` — OpenAI-compatible Codable types
- `APIProfile` — named, saveable API configuration snapshot
- `StorageService` — `UserDefaults` wrapper with `chat-buddy:` namespace prefix
- `DataExporter` / `DataImporter` — JSON backup/restore via SwiftUI `fileExporter` / `fileImporter`

#### T03 — UI Design System & Navigation
- `DesignTokens` — `DSTypography`, `DSSpacing`, `DSRadius`, `DSShadow`, `DSIconSize` constants
- `ThemeManager` — `@Observable`: `ThemeMode` (system/light/dark), OLED pure black, `AnimationIntensity`
- `AccentColorManager` — `@Observable`: 10 preset colors + custom `ColorPicker`, persisted
- `LiquidGlassModifiers` — `.liquidGlass()` ViewModifier (iOS 26 `.glassEffect`, fallback `.ultraThinMaterial`)
- `Color(hex:)` — hex string initializer (3/6/8 digit)
- `AppTab` — 4-tab enum: Dashboard, Chats, Moments, Settings
- `RootTabView` — iOS 26 Liquid Glass tab bar
- `OnboardingView` — 4-page `.page` style TabView tutorial with skip/back/next
- `AppState` — `@Observable` onboarding completion state
- `GlassCard`, `BentoCardView`, `SettingRow` — shared reusable card components
- `DashboardView` — 2-column `LazyVGrid` bento layout with time-based greeting
- Dashboard widgets: RecentChats, Stats, QuickActions, TodaysPick, Friends
- `DashboardViewModel` — time-based greeting, today's pick persona selection
- `PersonaStore` — static data: 13 social companions + 6 task agents (ported from web)
- `SettingsView` — grouped Form (Appearance, Language, API, Data, About)
- `ThemeModePickerView`, `OLEDToggleView`, `AccentColorPickerView`, `AnimationIntensityView`
- `LanguagePickerView`, `AILanguagePickerView`
- `APIConfigView` — Form with URL/key/model/temperature + test button
- `APIProfileListView` — list with swipe-to-delete + load
- `ConnectivityTestView` — live latency test result display
- `ExportImportView` — fileExporter/fileImporter integration
- `AboutView` — version info, app tagline
- `ChatsPlaceholderView`, `MomentsPlaceholderView` — coming-soon tabs

### Technical Notes
- Targets iOS 26.2, compiled with Xcode 26.2
- Build passes with 0 errors, 0 warnings
- File System Synchronized project — new Swift files auto-included
- Default global actor isolation (`@MainActor`) enabled via Xcode 26 project settings
