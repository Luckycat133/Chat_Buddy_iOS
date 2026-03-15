# Development Guide — Chat Buddy iOS

[English](#english) | [中文](#中文)

---

## English

### Prerequisites

- **macOS** Sequoia or later
- **Xcode** 26.2+
- **iOS Simulator**: iPhone 17 Pro (iOS 26.2) — installed via Xcode
- No external Swift package dependencies

### Setup

```bash
git clone <repo>
cd Chat_Buddy_iOS
open Chat_Buddy_iOS.xcodeproj
```

Select **iPhone 17 Pro** simulator and press **⌘R** to build and run.

### Build from Terminal

```bash
xcodebuild \
  -project Chat_Buddy_iOS.xcodeproj \
  -scheme Chat_Buddy_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build
```

### Project Structure Overview

| Directory | Purpose |
|---|---|
| `App/` | App entry, onboarding state, constants |
| `Localization/` | String Catalog + runtime language manager |
| `Services/API/` | HTTP client (actor), AI client, config store |
| `Services/Storage/` | UserDefaults wrapper, data export/import |
| `Services/Chat/` | AIPipeline, MoodService, AffinityService, BookmarkService, DraftService |
| `Services/Moments/` | MomentsStore, MomentsService, MomentsOrchestrator |
| `Services/Background/` | BackgroundStore — gradient preset persistence and resolution |
| `Services/Social/` | UserProfileStore, SocialService — points, achievements, check-ins |
| `Models/` | Domain types: Persona, ChatMessage, ChatSession, MomentPost, Bookmark, APIConfig, UserProfile, ChatBackgroundPreset, Achievement types |
| `Theme/` | Design tokens, theme/accent managers, glass effects |
| `Navigation/` | Tab enum, root TabView, onboarding |
| `Features/` | Feature modules (Dashboard, Settings, Chats, Moments) |
| `SharedViews/` | Reusable card and row components |
| `Extensions/` | Color hex init, View helpers, UserDefaults keys |

### Configuring the API

The app is a client — no server-side code needed. Configure your preferred OpenAI-compatible provider:

1. Run the app
2. Go to **Settings → API Configuration**
3. Fill in **Base URL**, **API Key**, **Model**
4. Tap **Test Connection** to verify

Supported providers: DeepSeek, OpenAI, Perplexity, any OpenAI-compatible endpoint.

The API is also required for the **Moments** tab to generate AI persona posts, comments, and reactions.

### Adding a New AI Persona

1. Open `Models/PersonaStore.swift`
2. Add a `Persona(...)` entry to `socialCompanions` or `taskAgents`
3. Add a color entry to `colorMap`
4. Add an avatar image asset to `Assets.xcassets` (name: `avatar_<id>`)
5. Optionally add a location pool for the persona in `Services/Moments/MomentsService.swift` (`aiLocations`)

### Adding Translations

1. Open `Localization/Localizable.xcstrings`
2. Add a new entry with both `en` and `zh-Hans` string units
3. Use `localization.t("your_key")` in SwiftUI views
4. For parameterized strings use `{param}` syntax: `"Hello, {name}!"`

```swift
// Usage in a view
@Environment(LocalizationManager.self) private var localization

Text(localization.t("greeting_morning"))
Text(localization.t("moments_view_all", params: ["n": "5"]))
```

### Adding a New Settings Section

1. Add rows in `Features/Settings/SettingsView.swift`
2. Create a new SwiftUI view in the appropriate `Settings/` subfolder
3. Add any new `UserDefaults.Keys` constants to `Extensions/UserDefaults+Keys.swift`
4. Persist state in the relevant manager's `didSet`

### Working with the Moments Feed

The Moments tab is fully AI-driven. Key points for development:

- **Images** are stored as JPEG files in `FileManager.documentDirectory/moments/`. Filenames (UUIDs) are stored in `MomentPost.imagePaths`.
- **AI orchestration** runs in a `Task` tied to the lifetime of `MomentsView`. It cancels automatically when the user navigates away.
- **Sheet binding**: sheets use `PostID: Identifiable` (a thin `String` wrapper) so that the sheet item is the post ID, not the post struct — avoiding stale value-type copies.
- **Seeding** only happens once (when `posts.isEmpty`). Reset by clearing `chat-buddy:moments` from UserDefaults.
- **iOS 26**: Avoid `Text + Text` concatenation in comment views — it is deprecated. Use `VStack` or `AttributedString` instead.

### Working with Chat Backgrounds

- **10 gradient presets** defined in `ChatBackgroundPreset.presets` (id: `none`, `aurora`, `sunset`, `ocean`, `rose`, `forest`, `midnight`, `sakura`, `golden`, `cosmos`).
- **Resolution**: `BackgroundStore.resolvedPreset(for: sessionId)` returns the per-chat preset if set, otherwise falls back to the global preset.
- **Picker**: `BackgroundPickerView` accepts an optional `sessionId`. Without it, it operates in global mode. Pass a sessionId from `ChatView` for per-chat mode.
- **ZStack pattern** in `ChatView`:
  ```swift
  ZStack {
      if let gradient = backgroundStore.resolvedPreset(for: sessionId).gradient() {
          gradient.ignoresSafeArea()
      }
      VStack { /* message list */ }
  }
  ```
- **Reset**: Clear `chat-buddy:backgrounds` from UserDefaults to reset all background settings.

### Working with Social Features

- **Points** are earned via check-ins, daily tasks, mini-games, and gifts. Deducted when sending gifts.
- **Achievements** are defined statically in `AchievementDefinition.all` (10 total). Call `SocialService.unlockAchievement(_:)` from any context where an unlock condition is met — the method is idempotent.
- **Daily tasks** reset at midnight based on `DailyTaskState.todayString` (format: `yyyy-MM-dd`). Progress is tracked in `SocialService.dailyTaskState`.
- **Check-in** call `SocialService.checkIn()` — returns points earned. Guard on `canCheckInToday` before showing the button.
- **Gift integration**: After sending a gift, call `AffinityService.addBoost(gift.intimacyBoost, for: personaId)` (bypasses the 5-min cooldown) and `SocialService.onGiftSent(intimacyAfter:)`.
- **Mini-games**: On game end, call `SocialService.addPoints(winPoints)` for a win and `SocialService.onGamePlayed()` regardless of result (updates `task_game` daily task).
- **SocialWidget** on the Dashboard reads `SocialService` via `@Environment` — no prop drilling needed.

### Theming

- Use `DSSpacing`, `DSRadius`, `DSTypography`, `DSShadow` constants from `DesignTokens.swift`
- Apply glass effect: `.liquidGlass(cornerRadius: DSRadius.lg)`
- Use `.tint(accentColorManager.currentColor)` at root — it propagates to all tintable elements
- Dark/OLED backgrounds: check `themeManager.oledEnabled` and conditionally apply `.background(.black)`

### File System Synchronized Project

This project uses Xcode's **File System Synchronized** mode. Any `.swift` file added to the `Chat_Buddy_iOS/` directory tree is automatically included in the build target — no `project.pbxproj` edits required.

### Common Gotchas

| Issue | Solution |
|---|---|
| `@MainActor` isolation errors | Don't use `static let default` in actor inits; actors initialize nonisolated |
| `.glassEffect(.regular.interactive())` | `interactive` requires parentheses — it's a method, not a property |
| `Text + Text` deprecation (iOS 26) | Use `VStack` layout or `AttributedString` for styled inline text |
| `NSColor` on iOS | Use `UIColor` for color conversions, not `NSColor` |
| `remove(atOffsets:)` on Array | Requires `import SwiftUI`, not just `Foundation` |
| `@State` from `@Environment` at init | Use `.onAppear` / `.task` to sync `@State` from environment objects |
| Sheet shows stale post data | Pass `postId: String` to sheets and look up from store — don't pass the struct directly |
| SourceKit "Cannot find X in scope" | False positive from single-file analysis — run full build; trust `BUILD SUCCEEDED` |
| AI posts not appearing | Ensure API config is set in Settings — `MomentsOrchestrator` needs a valid `activeConfig` |
| `.foregroundStyle(.accentColor)` compile error | iOS 26: `.accentColor` is no longer a `ShapeStyle` member — use `Color.accentColor` or `AnyShapeStyle(Color.accentColor)` in ternary expressions |
| `AnyShapeStyle` in ternary required | When both branches of a ternary are different `ShapeStyle` types (e.g. `.secondary` vs `Color.accentColor`), wrap both in `AnyShapeStyle(...)` to unify the type |

---

## 中文

### 前置要求

- **macOS** Sequoia 或更高版本
- **Xcode** 26.2+
- **iOS 模拟器**: iPhone 17 Pro (iOS 26.2) — 通过 Xcode 安装
- 无外部 Swift 包依赖

### 配置

```bash
git clone <仓库>
cd Chat_Buddy_iOS
open Chat_Buddy_iOS.xcodeproj
```

选择 **iPhone 17 Pro** 模拟器，按 **⌘R** 构建并运行。

### 终端构建

```bash
xcodebuild \
  -project Chat_Buddy_iOS.xcodeproj \
  -scheme Chat_Buddy_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build
```

### 配置 API

应用是纯客户端，无需服务端。配置你偏好的 OpenAI 兼容服务商：

1. 运行应用
2. 进入 **设置 → API 配置**
3. 填写 **Base URL**、**API 密钥**、**模型名称**
4. 点击 **测试连接** 验证

**朋友圈**标签的 AI 角色发帖、评论、表情反应也依赖此 API 配置。

### 项目目录概览

| 目录 | 用途 |
|---|---|
| `App/` | 应用入口、新手引导状态、常量 |
| `Localization/` | String Catalog + 运行时语言管理 |
| `Services/API/` | HTTP 客户端（actor）、AI 客户端、配置存储 |
| `Services/Storage/` | UserDefaults 封装、数据导出/导入 |
| `Services/Chat/` | AIPipeline、MoodService、AffinityService、BookmarkService、DraftService |
| `Services/Moments/` | MomentsStore、MomentsService、MomentsOrchestrator |
| `Services/Background/` | BackgroundStore — 渐变预设持久化与解析 |
| `Services/Social/` | UserProfileStore、SocialService — 积分、成就、签到 |
| `Models/` | 领域类型：Persona、ChatMessage、MomentPost、UserProfile、ChatBackgroundPreset、成就相关类型 |
| `Theme/` | 设计令牌、主题/强调色管理器、玻璃效果 |
| `Navigation/` | 标签枚举、根部 TabView、新手引导 |
| `Features/` | 功能模块（Dashboard、Settings、Chats、Moments、Achievements） |
| `SharedViews/` | 可复用卡片和行组件 |
| `Extensions/` | Color hex 初始化、View 辅助、UserDefaults 键 |

### 添加新 AI 角色

1. 打开 `Models/PersonaStore.swift`
2. 在 `socialCompanions` 或 `taskAgents` 中添加 `Persona(...)` 条目
3. 在 `colorMap` 中添加对应颜色
4. 在 `Assets.xcassets` 中添加头像图片（命名：`avatar_<id>`）
5. 可选：在 `Services/Moments/MomentsService.swift` 的 `aiLocations` 中为该角色添加位置池

### 添加翻译

1. 打开 `Localization/Localizable.xcstrings`
2. 添加包含 `en` 和 `zh-Hans` 字符串单元的新条目
3. 在 SwiftUI 视图中使用 `localization.t("your_key")`
4. 参数化字符串使用 `{param}` 语法：`"你好，{name}！"`

### 聊天背景开发要点

- **10 种渐变预设** 定义于 `ChatBackgroundPreset.presets`（id：`none` / `aurora` / `sunset` / `ocean` / `rose` / `forest` / `midnight` / `sakura` / `golden` / `cosmos`）。
- **解析逻辑**：`BackgroundStore.resolvedPreset(for: sessionId)` 优先返回每聊天预设，未设置时回退到全局预设。
- **选择器**：`BackgroundPickerView` 接受可选 `sessionId`。不传时为全局模式，从 `ChatView` 传入时为每聊天模式。
- **重置**：清除 UserDefaults 的 `chat-buddy:backgrounds` 键可重置所有背景设置。

### 社交功能开发要点

- **积分**通过签到、每日任务、小游戏、礼物获得；发送礼物时扣除。
- **成就**静态定义于 `AchievementDefinition.all`（共 10 个）。在满足解锁条件处调用 `SocialService.unlockAchievement(_:)`，该方法幂等安全。
- **每日任务**在午夜基于 `DailyTaskState.todayString`（格式：`yyyy-MM-dd`）自动重置。进度记录在 `SocialService.dailyTaskState` 中。
- **签到**：调用 `SocialService.checkIn()`，返回获得的积分。显示按钮前先检查 `canCheckInToday`。
- **礼物集成**：发送礼物后调用 `AffinityService.addBoost(gift.intimacyBoost, for: personaId)`（绕过5分钟冷却）及 `SocialService.onGiftSent(intimacyAfter:)`。
- **小游戏**：游戏结束时，胜利调用 `SocialService.addPoints(winPoints)`，无论胜负均调用 `SocialService.onGamePlayed()`（更新 `task_game` 每日任务）。

### 朋友圈开发要点

- **图片**以 JPEG 格式存储在 `FileManager.documentDirectory/moments/` 中，文件名（UUID）保存在 `MomentPost.imagePaths` 里。
- **AI 编排**在与 `MomentsView` 生命周期绑定的 `Task` 中运行，离开页面时自动取消。
- **Sheet 绑定**：Sheet 使用 `PostID: Identifiable`（String 的薄包装）传递 post ID，而非 post 结构体，避免值类型陈旧副本问题。
- **种子数据**仅在 `posts.isEmpty` 时生成一次，可通过清除 UserDefaults 的 `chat-buddy:moments` 键重置。
- **iOS 26**：在评论视图中避免使用已废弃的 `Text + Text` 拼接，改用 `VStack` 或 `AttributedString`。

### 文件系统同步项目

本项目使用 Xcode 的**文件系统同步**模式。在 `Chat_Buddy_iOS/` 目录树中添加的任何 `.swift` 文件都会自动包含到构建目标中，无需编辑 `project.pbxproj`。

### 常见问题排查

| 问题 | 解决方案 |
|---|---|
| 构建时 `@MainActor` 隔离报错 | 检查 actor 初始化是否引用了 `@MainActor` 属性 |
| `Text + Text` 废弃警告（iOS 26）| 使用 `VStack` 布局或 `AttributedString` 代替内联样式文本 |
| Sheet 显示陈旧数据 | 向 Sheet 传递 `postId: String` 并从 Store 查询，不要直接传递结构体 |
| 模拟器不可用 | 确认已安装 iOS 26.2 模拟器（Xcode → Settings → Platforms） |
| 翻译显示为 key | 检查 `Localizable.xcstrings` 中是否已添加对应条目 |
| AI 动态不出现 | 确认设置中已配置 API — `MomentsOrchestrator` 需要有效的 `activeConfig` |
| SourceKit "找不到类型 X" | 单文件分析误报 — 执行完整构建，以 `BUILD SUCCEEDED` 为准 |
| `.foregroundStyle(.accentColor)` 编译报错 | iOS 26：`.accentColor` 不再是 `ShapeStyle` 成员 — 改用 `Color.accentColor` 或在三元表达式中用 `AnyShapeStyle(Color.accentColor)` |
| 三元表达式中需要 `AnyShapeStyle` | 两个分支为不同 `ShapeStyle` 类型时（如 `.secondary` vs `Color.accentColor`），需用 `AnyShapeStyle(...)` 统一类型 |
