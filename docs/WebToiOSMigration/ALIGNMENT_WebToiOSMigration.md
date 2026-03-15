# ALIGNMENT - Web To iOS Migration

## 1. 项目与任务特性规范
**项目名称**: Chat Buddy iOS 移植版 (Chat Buddy Remake)
**原始需求**: “查看网页版已经实现了哪些功能，与iOS版进行对照，已网页版为基准，将其功能全部合理地移植到iOS版本上”
**边界确认 (任务范围)**: 
- 对比起点：`/Users/lobster/Documents/Chat_Buddy_iOS/Chat_Buddy_Web` 的最新版功能 (v0.2.7)。
- 移植终点：`/Users/lobster/Documents/Chat_Buddy_iOS/Chat_Buddy_iOS` 的现有 Swift/SwiftUI 代码库。
- 目标是将 Web 版未实现、未完全实现的功能逻辑、交互细节和架构完整且合理地移植至原生 iOS App 中，并遵守 Apple Human Interface Guidelines (HIG) 进行原生体验优化。

## 2. 需求理解 (现有项目对照分析)

通过对 Web 版源码 (`README.md`, `src` 结构等) 以及现有的 iOS `Features`, `Models`, `Services` 代码库对照分析，目前 iOS 相比于 Web 差距主要体现在以下方面：

### 1) 核心对话系统 (Chat System)
- **多人群聊 (Group Chat)**:
  - **Web 版**: 允许创建一个无限制 AI 角色的群组，AI之间可互动。
  - **iOS 现状**: `ChatSession.swift` 中严格定义为 1v1 (`let personaId: String`)。**完全缺失群聊模型及UI逻辑**。
- **智能对话特性 (Smart AI Features)**:
  - **Web 版**: 包含 动态在线状态(Dynamic Online Status, 基于时间的上下线逻辑)、可视打字指示器(Typing Indicators)、主动问候(Proactive Greetings)、心情/亲密度系统。具有 ReAct Tool Calling (执行代码，搜索，生成图片等任务Agent专用)。
  - **iOS 现状**: 已解析 `[MULTI:]`, `[SILENCE]`, 及基本的延时返回(Minimum delay mimicking typing)，已具备 MoodService 和 AffinityService，但 **缺失在线状态变化机制、主动问候触发器及基于 ReAct 模式的 Tool Calling 架构**。

### 2) 个性化与沉浸感 (Visuals & Customization)
- **沉浸式背景系统 (Immersive Backgrounds, v0.2.5)**:
  - **Web 版**: 100+ 预设，视频背景，CSS 原生动态粒子/下雨特效，视差效果(Parallax)，IndexedDB 海量存储，按照全局/单聊独立配置，早晚自动切换，JSON 配置导进导出。
  - **iOS 现状**: 已有 `BackgroundPickerView` 且持久化了 `ChatBackground` 模型，但 **缺少原生视频渲染、动态粒子的原生 SwiftUI 实现(或 SceneKit)、视差跟踪 (加速度传感器)、基于时间的早晚自动切换机制配置导入导出**。

### 3) 朋友圈 (Moments Enhancements, v0.2.7)
- **Web 版**: 包含了AI的动态贴文(Dynamic Posts)，智能互评(Smart Interactions)，地点标签与隐私，表情回应 (Emoji Reactions)，**草稿箱 (Draft Box)**，**话题标签(Hashtags)及过滤**，**加载更多(Pagination)**，**故事事件(Story Events 如生日/节假日)**，**转发至聊天 (Repost to Chat)**。
- **iOS 现状**: 已经有了 MomentsView, Composer, Comments，且包含 Hashtags 的粗略 Filter 和基本的 Pagination。也包含 `RepostSheet`。**缺失 AI的“Story Events” 自动生成调度逻辑，草稿箱数据持久化，以及丰富的 Emoji Reactions 模型交互**。

### 4) 社交互动微游戏 (Social & Interaction, v0.2.6)
- **Web 版**: 6个日常轮替任务(Daily Task System)、猜数字(Number Guess)及得点，剪刀石头布(PRS)及赢点，打赏礼物和红包，积分系统及成就。
- **iOS 现状**: `SharedViews` / `Chats/Components` 中已有 `NumberGuessView` 和 `RockPaperScissorsView`。Dashboard 中包含积分。**可能需要补全完整的游戏逻辑链条（奖励闭环）和节假日红包（UI）逻辑**。

### 5) 双语与多语言 (Bilingual Support)
- **Web 版**: UI 上的无缝切换。
- **iOS 现状**: 依靠 `LocalizationManager` 和 `LanguagePickerView`。完成度较高。

## 3. 疑问澄清与关键决策点 (优先解答清单)

基于自动化对比，目前我们有一些在向原生 iOS 迁移时需要用户干预与抉择的关键设计点。

### Q1: 群组聊天 (Group Chats) 架构改造的优先级与难度？
- **背景**: 当前 iOS `ChatSession` 模型为 1v1 强绑定。引入群聊意味着需要重构 Core Data / JSON Schema，使 `ChatSession` 支持多 `personaIds`，并调整 `AIPipeline` 发送的多系统 Prompt 机制。
- **待定**: 我们是否要在本版本立即重构 `ChatSession` 以支持多人群聊？

### Q2: iOS 上的 ReAct Tool Calling 实现？
- **背景**: Web 版可以让 Task Agent（Coder, Scholar）执行搜索或生成图片。这需要 API 提供端或专门的 Agent Loop 解析 Tool calling 并请求真正的工具 API。
- **待定**: iOS端是仅利用语言模型的 System Prompt 模拟效果，还是真正需要接入网络搜索与图片生成的第三方工具链(如 Exa, Dalle/Flux)？

### Q3: 沉浸式背景的 3D 及粒子特效
- **背景**: Web 的背景涉及 CSS 动画及一些 Video 渲染。在 iOS 上这可以利用 `SpriteKit`, `AVPlayer`, 甚至 iOS 26 Liquid Glass 特性进行重构。
- **待定**: 针对原生特效，我们将采用何种技术栈？轻量级的 SwiftUI 动画实现，还是直接移植 Web 视频资源使用 `VideoPlayer`？

### Q4: 朋友圈事件与日常任务调度的持久化
- **背景**: 每日登录打卡、任务刷新，以及特定人物在特定日期的生日发推（Story Events），Web 利用 LocalStorage 记录状态。iOS中我们是在 `DashboardViewModel` 或全局 `MomentsOrchestrator` 处理。
- **待定**: 对于 Story Events (如人物生日发朋友圈)，我们是否引入类似 `BackgroundTasks` / `Notification` 唤醒时的被动离线计算，还是仅仅在打开APP前台时结算？

## 4. 后续执行建议

我会把这些整理为您需要审核的事项。请针对上述 **4个未决问题 (Q1~Q4)** 给出您的偏好和决策。基于您的回答，我将生成 `CONSENSUS_WebToiOSMigration.md` 和接下来的架构设计与原子化任务清单。
