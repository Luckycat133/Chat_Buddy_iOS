# Architecture — Chat Buddy iOS

[English](#english) | [中文](#中文)

---

## English

### Overview

Chat Buddy iOS follows **MVVM + Clean Architecture** adapted for SwiftUI's declarative paradigm. The goal is clear layer separation while leveraging Swift's modern concurrency and observation frameworks.

### Layers

```
┌──────────────────────────────────────────────────────┐
│                  Presentation Layer                  │
│          SwiftUI Views + @Observable ViewModels      │
│          Location: Features/, Navigation/            │
├──────────────────────────────────────────────────────┤
│                  Application Layer                   │
│      Environment Objects (injected at scene root)    │
│      LocalizationManager, ThemeManager,              │
│      AccentColorManager, APIConfigStore, AppState    │
│      ChatStore, AffinityService, BookmarkService,    │
│      DraftService, MomentsStore,                     │
│      BackgroundStore, UserProfileStore,              │
│      SocialService, MemoryService                    │
├──────────────────────────────────────────────────────┤
│                   Domain Layer                       │
│         Pure Swift structs and enums                 │
│         Persona, ChatMessage, ChatSession,           │
│         APIConfig, APIProfile, Bookmark,             │
│         MomentPost, MomentComment, MomentsData,      │
│         UserProfile, ChatBackgroundPreset,           │
│         AchievementDefinition, GiftDefinition,       │
│         DailyTaskDefinition, DailyTaskState,         │
│         CharacterMemory, MemoryCategory, MemoriesData│
│         Location: Models/                            │
├──────────────────────────────────────────────────────┤
│                Infrastructure Layer                  │
│         APIClient (actor), AIClient, StorageService  │
│         AIPipeline, MoodService, AffinityLevel       │
│         MomentsService, MomentsOrchestrator          │
│         MemoryService, MemoryInjector                │
│         DataExporter, DataImporter                   │
│         Location: Services/                          │
└──────────────────────────────────────────────────────┘
```

### Key Design Decisions

#### @Observable over ObservableObject
iOS 17+ `@Observable` macro eliminates `@Published` boilerplate and enables fine-grained dependency tracking. ViewModels and managers are marked `@Observable final class`.

#### actor for APIClient
Swift `actor` provides compile-time data race safety for the HTTP client. All network requests execute on the actor's isolated executor, preventing concurrency bugs without manual locking.

#### UserDefaults for All Persistence
All app data uses `StorageService` (a `UserDefaults` wrapper with `chat-buddy:` namespace prefix). Each store reads on init and writes on every mutation — simple, fast, no migration complexity.

#### String Catalog (not .strings files)
`Localizable.xcstrings` provides compile-time key validation and a unified source of truth for all languages. Runtime language switching is achieved by selecting the appropriate `.lproj` bundle at access time via `LocalizationManager`.

#### Environment Injection
All managers are `@State` in the root `App` struct and passed down via `.environment()`. This avoids singleton anti-patterns while ensuring a single instance per app lifecycle.

#### postId over post for Sheets
Sheet views (`CommentsView`, `RepostSheet`) accept a `postId: String` and look up the live `MomentPost` from `MomentsStore` on every render. This avoids stale struct copies — since `MomentPost` is a value type, passing it directly to a sheet would freeze its state at open time.

---

### Environment Objects (Root Injection)

| Object | Type | Role |
|---|---|---|
| `AppState` | `@Observable` | Onboarding completion; `selectedTab` for programmatic tab switching |
| `LocalizationManager` | `@Observable` | Runtime UI language, `t(_:params:)` translation helper |
| `ThemeManager` | `@Observable` | Dark/light/system mode, OLED toggle, animation intensity |
| `AccentColorManager` | `@Observable` | 10 preset colors + custom picker |
| `APIConfigStore` | `@Observable` | Active `APIConfig`, named profiles CRUD |
| `ChatStore` | `@Observable` | All `ChatSession` objects; pin, search, delete operations |
| `AffinityService` | `@Observable` | Per-persona intimacy scores (0–100), 5-min cooldown; `addBoost` for gift bypasses cooldown |
| `BookmarkService` | `@Observable` | Bookmarked messages, keyed by `messageId` |
| `DraftService` | `@Observable` | Per-session draft text + quoted message; 7-day expiry |
| `MomentsStore` | `@Observable` | All `MomentPost` objects; image files in `Documents/moments/` |
| `BackgroundStore` | `@Observable` | Global + per-chat gradient preset IDs; `resolvedPreset(for:)` merges both |
| `UserProfileStore` | `@Observable` | User nickname, emoji avatar, signature |
| `SocialService` | `@Observable` | Points economy, achievements (10), daily check-in streaks, gift/game event tracking |
| `MemoryService` | `@Observable` | Per-persona long-term memory records; Jaccard dedup, time decay, recall tracking |

---

### Data Flow

**Settings change:**
```
User taps ThemePicker
  → ThemeManager.mode updated
  → UserDefaults persisted (didSet)
  → .preferredColorScheme() re-evaluated at root
  → All views re-render with new scheme
```

**Chat message sent:**
```
User taps Send in MessageInputView
  → ChatViewModel.sendMessage()
  → AffinityService.addChatIntimacy(for: personaId)  // +1 with 5-min cooldown
  → AIPipeline.run(session:persona:config:..., memoryService:)
      → buildSystemPrompt (traits + mood + affinity hint)
          → MemoryInjector.memoryBlock(...)  // top-10 memories injected
          → MemoryInjector.memorySaveHint()  // teach AI to emit [MEMORY_SAVE:] tags
      → compressContext (>15 msgs → keep last 8)
      → AIClient.sendChatCompletion()
      → enforce minimumResponseDelay
      → parseResponse: extractMemories strips [MEMORY_SAVE:] blocks → Result.newMemories
      → parse [SILENCE] / [MULTI:] markers on cleaned text
  → for each result.newMemory → MemoryService.addMemory() (Jaccard dedup guard)
  → ChatStore.appendMessage() × N (multi-message delivery)
  → ChatView auto-scrolls to bottom
```

**Memory recalled:**
```
AIPipeline calls MemoryInjector.memoryBlock()
  → MemoryService.relevantMemories(for: personaId, limit: 10)
      → sort by importance desc, then lastRecalledAt desc
      → update lastRecalledAt = now for top-N records
      → persist to chat-buddy:memories
  → formatted as bullet list in system prompt
```

**Moments feed:**
```
MomentsView .task fires MomentsOrchestrator.run()
  → if posts.isEmpty → seedInitialPosts (4 AI posts)
  → checkStoryEvents (birthday/holiday posts once/day)
  → runPeriodicLoop every 5 min:
      → per social companion: if cooldown elapsed → generatePost → createPost
User creates post
  → MomentsOrchestrator.reactToUserPost()
      → 15–40s delay → 2–4 personas like/react
      → 30–90s delay → 1–2 personas comment (via AI)
```

**Gift sent:**
```
User taps gift in GiftPanelView
  → AffinityService.addBoost(gift.intimacyBoost, for: personaId)  // bypasses 5-min cooldown
  → SocialService.onGiftSent(intimacyAfter:)
      → deduct gift.points from points
      → updateTaskProgress("task_gift")
      → check achievement unlock (gift_giver at 5 gifts)
  → ChatStore.appendMessage()  // system gift message appended to chat
  → ChatView displays gift bubble
```

**Background change:**
```
User picks preset in BackgroundPickerView (per-chat or global)
  → BackgroundStore.setChat(sessionId:presetId:) or setGlobal(presetId:)
  → UserDefaults persisted
  → ChatView ZStack re-reads resolvedPreset(for: sessionId)
  → Gradient layer updates behind message list
```

**Language switch:**
```
User selects "简体中文" in LanguagePicker
  → LocalizationManager.uiLanguage = .zh
  → UserDefaults persisted
  → LocalizationManager.updateBundle() called
  → Correct .lproj bundle selected
  → All views reading localization.t("key") re-render
```

---

### Storage Keys

| Key | Type | Content |
|---|---|---|
| `chat-buddy:apiConfig` | `APIConfig` | Active API configuration |
| `chat-buddy:apiProfiles` | `[APIProfile]` | Saved API profiles |
| `chat-buddy:hasCompletedOnboarding` | `Bool` | Onboarding flag |
| `chat-buddy:uiLanguage` | `String` | `AppLanguage.rawValue` |
| `chat-buddy:aiLanguage` | `String` | `AILanguage.rawValue` |
| `chat-buddy:themeMode` | `String` | `ThemeMode.rawValue` |
| `chat-buddy:oledEnabled` | `Bool` | OLED pure black |
| `chat-buddy:animationIntensity` | `String` | `AnimationIntensity.rawValue` |
| `chat-buddy:accentColor` | `AccentColorState` | Preset ID + custom hex |
| `chat-buddy:bookmarks` | `[Bookmark]` | Bookmarked messages |
| `chat-buddy:drafts` | `[String: DraftEntry]` | Per-session drafts (7-day TTL) |
| `chat-buddy:intimacy` | `[String: Int]` | Per-persona affinity scores |
| `chat-buddy:moments` | `MomentsData` | Posts, AI timing, draft, events |
| `chat-buddy:backgrounds` | `BackgroundStore.StorageData` | Global preset ID + per-chat preset overrides |
| `chat-buddy:userProfile` | `UserProfile` | User nickname, emoji avatar, signature |
| `chat-buddy:social` | `SocialService.StorageData` | Points, achievement records, check-in dates, streak, daily task state |
| `chat-buddy:memories` | `MemoriesData` | Per-persona memory records (`[String: [CharacterMemory]]`) |
| `chatSessions` | `[ChatSession]` | All chat history (no prefix) |

---

### File Naming Conventions

| Category | Convention | Example |
|---|---|---|
| Views | PascalCase + View suffix | `DashboardView.swift` |
| ViewModels | PascalCase + ViewModel suffix | `DashboardViewModel.swift` |
| Managers / Stores | PascalCase + Manager/Store suffix | `ThemeManager.swift`, `ChatStore.swift` |
| Services | PascalCase + Service/Orchestrator suffix | `MomentsService.swift`, `MomentsOrchestrator.swift` |
| Extensions | `Type+Capability.swift` | `Color+Extensions.swift` |
| Shared views | PascalCase (no suffix) | `GlassCard.swift` |

---

## 中文

### 概述

Chat Buddy iOS 采用 **MVVM + 简化 Clean Architecture**，针对 SwiftUI 声明式范式进行了适配。目标是在充分利用 Swift 现代并发和观察框架的同时，保持清晰的分层。

### 分层结构

```
┌──────────────────────────────────────────────────────┐
│                     展示层                           │
│          SwiftUI 视图 + @Observable ViewModel        │
│          位置：Features/, Navigation/                │
├──────────────────────────────────────────────────────┤
│                     应用层                           │
│      环境对象（在 Scene 根部注入）                    │
│      LocalizationManager, ThemeManager,              │
│      AccentColorManager, APIConfigStore, AppState    │
│      ChatStore, AffinityService, BookmarkService,    │
│      DraftService, MomentsStore,                     │
│      BackgroundStore, UserProfileStore,              │
│      SocialService, MemoryService                    │
├──────────────────────────────────────────────────────┤
│                     领域层                           │
│         纯 Swift 结构体和枚举                        │
│         Persona, ChatMessage, ChatSession,           │
│         APIConfig, APIProfile, Bookmark,             │
│         MomentPost, MomentComment, MomentsData,      │
│         UserProfile, ChatBackgroundPreset,           │
│         AchievementDefinition, GiftDefinition,       │
│         DailyTaskDefinition, DailyTaskState,         │
│         CharacterMemory, MemoryCategory, MemoriesData│
│         位置：Models/                               │
├──────────────────────────────────────────────────────┤
│                  基础设施层                          │
│         APIClient (actor), AIClient, StorageService  │
│         AIPipeline, MoodService, AffinityLevel       │
│         MomentsService, MomentsOrchestrator          │
│         MemoryService, MemoryInjector                │
│         DataExporter, DataImporter                   │
│         位置：Services/                              │
└──────────────────────────────────────────────────────┘
```

### 关键设计决策

#### 使用 @Observable 而非 ObservableObject
iOS 17+ 的 `@Observable` 宏消除了 `@Published` 样板代码，并启用细粒度依赖追踪。所有 ViewModel 和 Manager 均标记为 `@Observable final class`。

#### 使用 actor 保障 APIClient 线程安全
Swift `actor` 在编译期提供数据竞争安全。所有网络请求在 actor 隔离的执行器上运行，无需手动加锁。

#### UserDefaults 统一持久化
所有应用数据通过 `StorageService`（带 `chat-buddy:` 前缀的 UserDefaults 封装）持久化。每个 Store 在初始化时读取，在每次变更时写入——简单、高效、无迁移复杂性。

#### 使用 String Catalog（非 .strings 文件）
`Localizable.xcstrings` 提供编译期键名验证和统一的多语言数据源。运行时语言切换通过 `LocalizationManager` 在访问时选择正确的 `.lproj` Bundle 实现。

#### 环境注入（Environment Injection）
所有 Manager 在根 `App` 结构体中声明为 `@State`，通过 `.environment()` 向下传递。避免了单例反模式，同时确保应用生命周期内只有一个实例。

#### Sheet 传 postId 而非 post
`CommentsView` 和 `RepostSheet` 等 Sheet 视图接收 `postId: String`，在每次渲染时从 `MomentsStore` 读取最新数据。这避免了值类型结构体的陈旧副本问题——直接传递 `MomentPost` 结构体到 Sheet 会在打开时冻结其状态。

---

### 环境对象（根部注入）

| 对象 | 类型 | 职责 |
|---|---|---|
| `AppState` | `@Observable` | 新手引导完成标志；`selectedTab` 实现程序化标签切换 |
| `LocalizationManager` | `@Observable` | 运行时 UI 语言，`t(_:params:)` 翻译辅助 |
| `ThemeManager` | `@Observable` | 深色/浅色/系统模式、OLED 开关、动画强度 |
| `AccentColorManager` | `@Observable` | 10 种预设颜色 + 自定义取色器 |
| `APIConfigStore` | `@Observable` | 当前 `APIConfig`、命名配置 CRUD |
| `ChatStore` | `@Observable` | 所有 `ChatSession`；置顶、搜索、删除操作 |
| `AffinityService` | `@Observable` | 每角色亲密度分数（0–100），5 分钟冷却；`addBoost` 礼物直通 |
| `BookmarkService` | `@Observable` | 已收藏消息，以 `messageId` 为键 |
| `DraftService` | `@Observable` | 每会话草稿文本 + 引用消息；7 天过期 |
| `MomentsStore` | `@Observable` | 所有 `MomentPost`；图片文件在 `Documents/moments/` |
| `BackgroundStore` | `@Observable` | 全局 + 每聊天渐变预设；`resolvedPreset(for:)` 合并两者 |
| `UserProfileStore` | `@Observable` | 用户昵称、emoji 头像、个性签名 |
| `SocialService` | `@Observable` | 积分体系、成就（10个）、每日签到连续天数、礼物/游戏事件追踪 |
| `MemoryService` | `@Observable` | 每角色长期记忆；Jaccard 去重、时间衰减、召回时间追踪 |

---

### 数据流

**发送聊天消息：**
```
用户点击发送
  → ChatViewModel.sendMessage()
  → AffinityService.addChatIntimacy(for: personaId)  // 5分钟冷却 +1
  → AIPipeline.run(..., memoryService:)
      → 构建系统提示（性格 + 心情 + 亲密度）
          → MemoryInjector.memoryBlock(...)  // 注入最多10条记忆
          → MemoryInjector.memorySaveHint()  // 教AI使用 [MEMORY_SAVE:] 标记
      → 压缩上下文（>15条 → 保留最后8条）
      → AIClient.sendChatCompletion()
      → 强制最低响应延迟
      → extractMemories 剥离 [MEMORY_SAVE:] 块 → Result.newMemories
      → 在净化文本上解析 [SILENCE] / [MULTI:] 标记
  → 对每个 newMemory → MemoryService.addMemory()（Jaccard 去重保护）
  → ChatStore.appendMessage() × N
  → ChatView 自动滚动到底部
```

**记忆召回：**
```
AIPipeline 调用 MemoryInjector.memoryBlock()
  → MemoryService.relevantMemories(for: personaId, limit: 10)
      → 按重要性降序、lastRecalledAt 降序排序
      → 更新返回记录的 lastRecalledAt = 当前时间
      → 持久化到 chat-buddy:memories
  → 格式化为系统提示中的要点列表
```

**朋友圈动态流：**
```
MomentsView .task 启动 MomentsOrchestrator.run()
  → posts 为空 → 种子4条AI动态
  → 检查每日故事事件（生日/节日）
  → 每5分钟循环：
      → 每个社交伴侣：冷却期结束 → 生成动态 → createPost
用户发布动态
  → MomentsOrchestrator.reactToUserPost()
      → 等待15~40秒 → 2~4个角色点赞/表情
      → 等待30~90秒 → 1~2个角色评论（AI生成）
```

**送礼物：**
```
用户在 GiftPanelView 点击礼物
  → AffinityService.addBoost(礼物亲密加成, for: personaId)  // 绕过5分钟冷却
  → SocialService.onGiftSent(intimacyAfter:)
      → 扣除礼物积分
      → updateTaskProgress("task_gift")
      → 检查成就解锁（送出5件礼物 → gift_giver）
  → ChatStore.appendMessage()  // 礼物系统消息追加到聊天
  → ChatView 显示礼物气泡
```

**更换聊天背景：**
```
用户在 BackgroundPickerView 选择预设（每聊天或全局）
  → BackgroundStore.setChat(sessionId:presetId:) 或 setGlobal(presetId:)
  → UserDefaults 持久化
  → ChatView ZStack 重新读取 resolvedPreset(for: sessionId)
  → 消息列表后方渐变层更新
```

---

### 存储键

| 键 | 类型 | 内容 |
|---|---|---|
| `chat-buddy:apiConfig` | `APIConfig` | 当前 API 配置 |
| `chat-buddy:apiProfiles` | `[APIProfile]` | 已保存的 API 配置列表 |
| `chat-buddy:hasCompletedOnboarding` | `Bool` | 新手引导标志 |
| `chat-buddy:uiLanguage` | `String` | `AppLanguage.rawValue` |
| `chat-buddy:aiLanguage` | `String` | `AILanguage.rawValue` |
| `chat-buddy:themeMode` | `String` | `ThemeMode.rawValue` |
| `chat-buddy:oledEnabled` | `Bool` | OLED 纯黑 |
| `chat-buddy:animationIntensity` | `String` | `AnimationIntensity.rawValue` |
| `chat-buddy:accentColor` | `AccentColorState` | 预设 ID + 自定义十六进制色值 |
| `chat-buddy:bookmarks` | `[Bookmark]` | 已收藏消息 |
| `chat-buddy:drafts` | `[String: DraftEntry]` | 每会话草稿（7天 TTL） |
| `chat-buddy:intimacy` | `[String: Int]` | 每角色亲密度分数 |
| `chat-buddy:moments` | `MomentsData` | 动态、AI 时间戳、草稿、事件 |
| `chat-buddy:backgrounds` | `BackgroundStore.StorageData` | 全局预设 ID + 每聊天预设覆盖 |
| `chat-buddy:userProfile` | `UserProfile` | 用户昵称、emoji 头像、个性签名 |
| `chat-buddy:social` | `SocialService.StorageData` | 积分、成就记录、签到日期、连续天数、每日任务状态 |
| `chatSessions` | `[ChatSession]` | 全部聊天记录（无前缀） |
