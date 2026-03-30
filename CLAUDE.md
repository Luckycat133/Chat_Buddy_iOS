# CLAUDE.md — Chat Buddy iOS

This file provides guidance to Claude Code when working with this repository.

---

## Project Overview

**Chat Buddy iOS** is a native iOS port of the Chat Buddy web app. It features 19 AI personas with distinct personalities, bilingual support (English/Chinese), and a modern Liquid Glass UI. Built with **SwiftUI + iOS 26**, following **MVVM + @Observable** architecture.

### Tech Stack

| Layer | Technology |
|---|---|
| UI Framework | SwiftUI (iOS 26) |
| State Management | `@Observable` (Observation framework) |
| Concurrency | Swift Concurrency (`actor`, `async/await`) |
| Storage | `UserDefaults` via `StorageService` |
| Localization | String Catalog (`Localizable.xcstrings`) |
| AI API | OpenAI-compatible (DeepSeek, OpenAI, etc.) |
| Build System | Xcode 26.2, File System Synchronized |

---

## Build & Run

```bash
# Build for simulator (no terminal deploy; open in Xcode)
xcodebuild -project Chat_Buddy_iOS.xcodeproj \
  -scheme Chat_Buddy_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build

# Run tests
xcodebuild -project Chat_Buddy_iOS.xcodeproj \
  -scheme Chat_Buddy_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test

# Open in Xcode
open Chat_Buddy_iOS.xcodeproj
```

Available simulator: **iPhone 17 Pro** (iOS 26.2)

---

## Architecture

```
┌────────────────────────────────────────────────┐
│              Presentation Layer                │
│     SwiftUI Views, ViewModels (@Observable)    │
│     Location: Features/, Navigation/           │
├────────────────────────────────────────────────┤
│              Application Layer                 │
│     Environment Objects (injected at root)     │
│     LocalizationManager, ThemeManager, etc.    │
├────────────────────────────────────────────────┤
│               Domain Layer                     │
│     Models: Persona, ChatMessage, APIConfig    │
│     Location: Models/                          │
├────────────────────────────────────────────────┤
│             Infrastructure Layer               │
│     APIClient (actor), StorageService          │
│     Location: Services/                        │
└────────────────────────────────────────────────┘
```

### Key Design Patterns

| Pattern | Location | Purpose |
|---|---|---|
| `@Observable` | All managers | Reactive state without ObservableObject boilerplate |
| `actor` | `APIClient` | Thread-safe HTTP requests |
| Environment injection | `Chat_Buddy_iOSApp.swift` | Pass managers to all child views |
| Static data store | `PersonaStore` | Immutable persona definitions |
| String Catalog | `Localizable.xcstrings` | Compile-time i18n with runtime switching |

---

## Directory Structure

```
Chat_Buddy_iOS/
├── Chat_Buddy_iOSApp.swift       # Entry: injects all environment objects
├── App/
│   ├── AppState.swift            # Onboarding state (@AppStorage)
│   └── AppConstants.swift        # Version, developer info
├── Localization/
│   ├── Localizable.xcstrings     # String Catalog (en + zh-Hans)
│   ├── LocalizationManager.swift # Runtime language switching + t() helper
│   └── String+Interpolation.swift
├── Services/
│   ├── API/
│   │   ├── APIClient.swift       # actor: URLSession + retry/backoff
│   │   ├── AIClient.swift        # Singleton: chat completions
│   │   ├── APIConfig.swift       # Codable config model
│   │   ├── APIConfigStore.swift  # @Observable: profiles CRUD
│   │   └── APIConfigValidator.swift
│   └── Storage/
│       ├── StorageService.swift  # UserDefaults wrapper (chat-buddy: prefix)
│       ├── DataExporter.swift    # JSON backup via fileExporter
│       └── DataImporter.swift    # JSON restore via fileImporter
├── Models/
│   ├── Persona.swift             # Persona struct + AgentType enum
│   ├── PersonaStore.swift        # 13 social companions + 6 task agents + custom personas
│   ├── APIProfile.swift          # Saved API configuration profile
│   ├── ChatMessage.swift         # OpenAI-compatible message format
│   └── ChatPoll.swift            # Poll model for group chat voting
├── Theme/
│   ├── DesignTokens.swift        # DSTypography / DSSpacing / DSRadius / DSShadow
│   ├── ThemeManager.swift        # dark/light/system + OLED + animation intensity
│   ├── AccentColorManager.swift  # 10 preset colors + custom ColorPicker
│   ├── LiquidGlassModifiers.swift # .liquidGlass() ViewModifier (iOS 26 + fallback)
│   └── Color+Extensions.swift
├── Navigation/
│   ├── AppTab.swift              # 4-tab enum (Dashboard/Chats/Moments/Settings)
│   ├── RootTabView.swift         # TabView with iOS 26 Liquid Glass tab bar
│   └── OnboardingView.swift      # 4-page welcome tutorial
├── Features/
│   ├── Dashboard/
│   │   ├── DashboardView.swift   # 2-column LazyVGrid bento layout
│   │   ├── DashboardViewModel.swift
│   │   └── Widgets/              # RecentChats, Stats, QuickActions, TodaysPick, Social
│   ├── Achievements/
│   │   ├── AchievementsView.swift
│   │   ├── DailyCheckInView.swift
│   │   └── LeaderboardView.swift # Points/intimacy/check-in/achievements ranking
│   ├── Friends/
│   │   ├── FriendsView.swift     # Search, star, group, custom friend CRUD
│   │   └── FriendGroupsView.swift # Friend group management
│   ├── Agents/
│   │   ├── AgentsView.swift      # Agent list + custom agent CRUD
│   │   └── AgentWorkspaceView.swift # Multi-topic agent workspace
│   ├── Settings/
│   │   ├── SettingsView.swift    # Main Form with sections
│   │   ├── Appearance/           # ThemeMode, OLED, AccentColor, AnimationIntensity
│   │   ├── Language/             # LanguagePicker, AILanguagePicker
│   │   ├── APIConfig/            # APIConfigView, ProfileList, ConnectivityTest
│   │   ├── Advanced/             # GlobalMessageSearch, KnowledgeBase, ModelSwitcher,
│   │   │                         #   KnowledgeGraph, LearningReport
│   │   └── Data/                 # ExportImport, About
│   ├── Chats/
│   │   ├── ChatsView.swift
│   │   ├── ChatView.swift
│   │   ├── ChatViewModel.swift
│   │   ├── Components/           # MessageInput, Bubble, Typing, Gift/Game, Background,
│   │   │                         #   RedPacket, TriviaQuiz, IdiomChain, PollComposer
│   │   ├── BookmarksSheet.swift
│   │   ├── GroupPickerSheet.swift
│   │   ├── ForwardMessageSheet.swift  # Message forwarding to other sessions
│   │   ├── GroupDetailsView.swift     # Group chat details/settings/polls
│   │   └── MemoriesView.swift
│   └── Moments/
│       ├── MomentsView.swift
│       ├── MomentCardView.swift
│       ├── PostComposerView.swift
│       ├── CommentsView.swift
│       └── RepostSheet.swift
├── SharedViews/
│   ├── GlassCard.swift
│   ├── BentoCardView.swift
│   ├── SettingRow.swift
│   └── CustomPersonaEditorSheet.swift # Create/edit custom friends & agents
└── Extensions/
    ├── Color+Extensions.swift    # Color(hex:) init
    ├── View+GlassEffect.swift    # .dsShadow(), .if()
    └── UserDefaults+Keys.swift   # Namespaced key constants

Chat_Buddy_iOSTests/              # Unit tests
Chat_Buddy_iOSUITests/            # UI + launch performance tests
```

---

## Environment Objects (Root Injection)

All managers are `@State` in `Chat_Buddy_iOSApp` and injected via `.environment()`:

```swift
@State private var appState = AppState()
@State private var localization = LocalizationManager()
@State private var themeManager = ThemeManager()
@State private var accentColorManager = AccentColorManager()
@State private var apiConfigStore = APIConfigStore()
```

Access in views:
```swift
@Environment(LocalizationManager.self) private var localization
@Environment(ThemeManager.self) private var themeManager
```

---

## Localization

- **String Catalog** (`Localizable.xcstrings`) for compile-time safety
- Runtime language switching via `LocalizationManager.uiLanguage`
- Translation helper: `localization.t("key", params: ["name": "Luna"])`
- Parameter syntax: `{param}` in strings (same as web `{name}`)
- Languages: `system` (auto-detect), `en` (English), `zh-Hans` (简体中文)

### Adding Translations

1. Add key to `Localizable.xcstrings` with both `en` and `zh-Hans` values
2. Use `localization.t("your_key")` in views

---

## Theming

- `ThemeManager.mode`: `.system` / `.light` / `.dark`
- `ThemeManager.oledEnabled`: Pure black background in dark mode
- `ThemeManager.animationIntensity`: Controls animation enablement and speed
- `AccentColorManager.currentColor`: Applied via `.tint()` at root
- `ThemeManager.resolvedColorScheme`: Applied via `.preferredColorScheme()` at root
- **Liquid Glass**: `.liquidGlass(cornerRadius:)` modifier (iOS 26 `.glassEffect`, fallback `.ultraThinMaterial`)

---

## API Configuration

Storage key: `chat-buddy:apiConfig` / `chat-buddy:apiProfiles`

```swift
// Access active config
@Environment(APIConfigStore.self) private var configStore
let config = configStore.activeConfig  // APIConfig

// Send a completion
try await AIClient.shared.sendChatCompletion(messages: messages, config: config)
```

Compatible providers: DeepSeek, OpenAI, Perplexity, any OpenAI-compatible endpoint.

---

## Data Storage

All data stored in `UserDefaults.standard` with `chat-buddy:` prefix via `StorageService`:

| Key | Content |
|---|---|
| `chat-buddy:apiConfig` | Active `APIConfig` |
| `chat-buddy:apiProfiles` | `[APIProfile]` array |
| `chat-buddy:hasCompletedOnboarding` | Bool |
| `chat-buddy:uiLanguage` | `AppLanguage.rawValue` |
| `chat-buddy:aiLanguage` | `AILanguage.rawValue` |
| `chat-buddy:themeMode` | `ThemeMode.rawValue` |
| `chat-buddy:oledEnabled` | Bool |
| `chat-buddy:animationIntensity` | `AnimationIntensity.rawValue` |
| `chat-buddy:accentColor` | `AccentColorState` (Codable JSON) |
| `chat-buddy:bookmarks` | `[Bookmark]` |
| `chat-buddy:drafts` | `[String: DraftEntry]` |
| `chatSessions` | `[ChatSession]` array (no prefix — direct key) |
| `chat-buddy:intimacy` | `[String: Int]` JSON (personaId → affinity score 0–100) |
| `chat-buddy:moments` | `MomentsData` |
| `chat-buddy:backgrounds` | `BackgroundStore.StorageData` |
| `chat-buddy:userProfile` | `UserProfile` |
| `chat-buddy:social` | `SocialService.StorageData` |
| `chat-buddy:memories` | `MemoriesData` |
| `chat-buddy:friends.groups` | `[FriendGroup]` friend group definitions |
| `chat-buddy:friends.meta` | `[String: FriendMeta]` star/group membership |
| `chat-buddy:knowledgeBase` | Knowledge base documents |
| `chat-buddy:knowledgeGraph.custom` | Custom knowledge graph nodes |
| `personas.custom` | `[Persona]` user-created custom personas |

---

## Adding a New Persona

1. Add to `PersonaStore.socialCompanions` or `PersonaStore.taskAgents` in `Models/PersonaStore.swift`
2. Add color to `PersonaStore.colorMap`
3. Add avatar asset to `Assets.xcassets` (name: `avatar_<id>` or `default_<style>`)

---

## Adding Translations

1. Open `Localization/Localizable.xcstrings`
2. Add entry with `en` and `zh-Hans` localizations
3. Use `localization.t("your_key")` in views

---

## Common Gotchas

| Issue | Solution |
|---|---|
| `@MainActor` isolation (iOS 26 default) | Don't use `static let default` on actors — actors initialize nonisolated |
| `.glassEffect(.regular.interactive)` | Must call as method: `.interactive()` |
| `NSColor` on iOS | Use `UIColor` instead for color conversions |
| `remove(atOffsets:)` on Array | Requires `import SwiftUI` (not just Foundation) |
| File System Synchronized | Adding new Swift files in Finder/Terminal auto-includes them — no pbxproj edits needed |
| OLED dark mode + system theme | `themeManager.mode == .dark` misses system-dark — add `@Environment(\.colorScheme)` and check both |
| Heavy computed properties | Avoid creating `DateFormatter` / `NumberFormatter` in computed vars — use `private static let` cache |
| SourceKit false positives | SourceKit analyzes files in isolation and reports missing types from other files — these clear on full build (`xcodebuild`). Treat `BUILD SUCCEEDED` as ground truth. |
| `@State` init from `@Environment` | `@State` can't read `@Environment` at init time — use `.onAppear` or `.task` to sync state from environment objects |
| Binding from `@Observable` in `@Environment` | Use `@Bindable var foo = foo` inside `body` to get `$foo.property` binding from an env-read `@Observable` class |
| Tab switching from deep views | Add `selectedTab: AppTab` to `AppState` — all views can set `appState.selectedTab = .chats` to switch tabs |
| Widget reads real data | Dashboard widgets read `ChatStore` via `@Environment(ChatStore.self)` — don't pass data via viewModel to keep widgets self-contained |

---

## Web Reference Files

The iOS app is ported from the web app located at `Chat_Buddy_Web/src/`. Key references:

| iOS File | Web Reference |
|---|---|
| `LocalizationManager.swift` | `src/context/LanguageContext.jsx` + `src/data/locales.js` |
| `ThemeManager.swift` | `src/context/ThemeContext.jsx` |
| `PersonaStore.swift` | `src/data/personas.js` + `src/data/taskAgents.js` |
| `APIClient.swift` | `src/services/api/APIClient.js` |
| `AIClient.swift` | `src/services/api/aiClient.js` |
| `StorageService.swift` | `src/services/storage/StorageService.js` |
| `DashboardView.swift` | `src/pages/Dashboard.jsx` |
| `SettingsView.swift` | `src/pages/Settings.jsx` |
| `AIPipeline.swift` | `src/core/chat/AIPipeline.js` |
| `MoodService.swift` | `src/core/presence/MoodService.js` |

---

## Development Status

| Task | Status |
|---|---|
| T01 — Internationalization (String Catalog, LocalizationManager) | ✅ Done |
| T02 — Core Architecture & API Compatibility | ✅ Done |
| T03 — Modern UI Design System (Liquid Glass, Bento Dashboard) | ✅ Done |
| T04 — Chat Engine & Message System | ✅ Done |
| T05 — AI Pipeline & Persona System | ✅ Done |
| T06 — Affinity & Mood System | ✅ Done |
| T07 — Advanced Chat Features | ✅ Done |
| T08 — Moments / Social Feed | ✅ Done |
| T09 — Immersive Background System | ✅ Done |
| T10 — Social & Interaction Features | ✅ Done |
| T11 — Character Memory System | ✅ Done |
| T12 — Chat Advanced Interactions (forward, red packet, trivia, idiom, polls, group details) | ✅ Done |
| T13 — Settings Advanced Panels (global search, knowledge base, model switcher, knowledge graph, learning report) | ✅ Done |
| T14 — Social Pages (friends, friend groups, leaderboard, agents, agent workspace) | ✅ Done |
| T15 — Custom Persona/Agent CRUD | ✅ Done |
| T16 — Data Import/Export Extended Validation | ✅ Done |
| T17 — Feature Parity (RAG, Stickers, Translation, Rich Messages, Presence, Notifications, Agent Skills) | ✅ Done |
