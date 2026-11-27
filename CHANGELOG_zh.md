[English](CHANGELOG.md) | [简体中文](CHANGELOG_zh.md)

# 更新日志 (Changelog) — Chat Buddy iOS

这里记录了针对 iOS 原生应用的所有重要修改指引。
格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/) 规范。

---

## [Unreleased]

---

## [0.11.4] - 2026-11-27

### 新增
- 支持 Web 与 iOS 通用偏好备份的导入与导出，不含账户数据或 API 凭据。

### 修复
- 初始化、离线重试和传输超时场景均保留各参与者的服务端已读游标。

---

## [0.11.3] - 2026-11-15

### 文档
- **AI 与大模型文档规范（GEO）**：新增符合 `llmstxt.org` 标准的 `llms.txt` 与 `llms-full.txt`，并在 `README.md` / `README_zh.md` 中补充入口链接（#6，`24ab6b7`）。
- **云端演示路线图与验证证据对齐**：以 `24ab6b7` 为基线核对 `chat-buddy-ios-demo-development` 技能文档（`SKILL.md`、`CURRENT_CHECKOUT.md`、`ROADMAP.md`、`VALIDATION_EVIDENCE.md`），明确区分源码实现、单测 CI 结果与待真机/云端验收项（`11b6f2a`）。

---

## [0.11.2] - 2026-10-25

### 变更
- **CI 全量单测跑通与配置维护**：将 `.github/workflows/ios-ci.yml` 从 `CODE_SIGNING_ALLOWED=NO` 切换为 ad-hoc 签名，解决模拟器上 Keychain `SecItem` 调用返回 `-34018`（`errSecMissingEntitlement`）的问题，hosted iOS 单元测试全量绿灯（**244 个测试 / 26 个套件全部通过，0 失败，0 崩溃**；`7075ab4`）。同步更新项目 Agent 配置、规则与技能引用（`9d46abf`）。
- **仓库清理**：移除误提交的本地复现调试产物 `workspace/repro_setasync*`，并在 `.gitignore` 中忽略仓库根 `workspace/`（`221e104`、`7207b5d`）。

### 修复
- **非主线程释放 double-free 崩溃**：为受 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` 影响的 30 个类型补充 `nonisolated deinit {}`（经 `swiftc -emit-sil` 复核，带 `swift_task_deinitOnExecutor` 的类型数从 30 降至 0），避免非主线程释放时重复释放（#5，`7207b5d`、`7075ab4`）。
- **JSON 编解码并发安全**：将进程级单例 `JSONEncoder.default` 改为每次访问返回新实例，消除主线程与并发 Task/Actor 共享非线程安全编解码器的竞态（`7075ab4`）。
- **RAG 长段切分兜底**：为 `RAGService.chunkText` 补充 `splitByWords` 兜底逻辑，解决无句号长段落无法切分的问题（`7075ab4`）。
- **联系人请求分类过滤**：修复 `ContactsClassifier.project` 将他人之间的 pending 请求误判为 inbound 的缺陷（`7075ab4`）。
- **单元测试断言修正**：修正 5 处与实现不符的测试断言（`7075ab4`）。

---

## [0.11.1] - 2026-09-25

### 新增
- **云端同步引擎补全**：新增 `EventApplier`、`ConflictResolver` 与 `RealtimeSequencer`，并完善 `SyncCoordinator`、`ConversationRepository`、`MomentsRepository` 的端到端同步编排（`d304fbf`）。
- **联系人、建群向导与设备设置**：新增 `ContactsView`、`ContactsRepository`、`GroupCreationWizardView`、`MeTabView`、`DeviceSettingsStore`、`AuthService`、`AccountService`、`MediaUploadService`、`FeatureLogic`、`RemoteDTOs` 与 `ViewData`（`d304fbf`）。
- **本地化与单元测试扩展**：补全云端功能对应的 `Localizable.xcstrings` 词条，并新增 9 套单元测试（`CloudFeatureTests`、`ConflictResolverTests`、`ContactsRepositoryTests`、`DeviceSettingsStoreTests`、`EventApplierTests`、`OnboardingHydrationTests`、`RealtimeSequencerTests`、`RemoteDTOFixtureTests`、`ViewDataMappingTests`）及扩展 `OutboxStoreTests`（`d304fbf`）。

---

## [0.11.0] - 2026-09-18

> 按 demo-development skill 落地的 cloud-first 运行时：HTTP/鉴权/实时/SwiftData 同步基座，包含静态审查修复与多轮 Xcode CI 类型检查修复。

### 新增 — 云端运行时
- **CloudAppState** — cloud-first 应用运行时（启动阶段、dev-signin、初始同步、realtime 接线），旧本地运行时经 `CBUseCloudRuntime` 保留作 fallback。
- **网络层** — HTTP 客户端、`APIError` 稳定错误码 + 服务端错误信封、端点表、Keychain 存储的 `AuthSession`（access/refresh）、带断流检测与处理器注入的 `RealtimeClient`。
- **持久层** — SwiftData 缓存（14 个 `@Model`）、`ModelContainerFactory`、`SyncCursorStore`、五状态幂等 `OutboxStore`、`LegacyImporter`。
- **同步** — `SyncCoordinator` 游标分页有序同步（`hasMore` 递归），初始同步后与 realtime 断流时重放 outbox。
- **仓库层** — Actor / Conversation / Moments 三个仓库，DTO↔缓存转换。
- **能力层** — EventKit 日历确认流、天气/搜索、`ClientActionCoordinator` 结构化回传、推送路由（payload 不含敏感内容）、`DeepLinkRouter`（`chatbuddy://`）。

### 新增 — UI
- 云端会话列表/时间线/输入框、Moments 流（发布+评论）、Sign in with Apple 流程、开发登录、Mira 引导聊天、诊断页、我页。

### 新增 — 测试
- `OutboxStoreTests`、`CloudClientTests`、`SyncCursorCodecTests`。

### 修复 — 审查补丁与 Xcode 编译兼容
- **静态审查（编译级）**：`self.cloud = = state` 笔误；重复 `init(conversationId:)`；全模块重复 `AppTab` 枚举（新变体改名 `CloudAppTab`）；`??` autoclosure 中的 `await`；`APIErrorCode.init(rawValue:)` 无限递归（改显式 switch 映射）；`ConversationListItem` 补 Identifiable；`MeTab` 跨 actor 异步取值；`private(set) stage` 赋值改走 `CloudAppState.transition(to:)`。
- **静态审查（逻辑）**：outbox flush 接通（原为空闭包）；realtime 事件/断流触发增量同步（原被丢弃）；`.offline` 状态不再被 bootstrap/dev-signin 覆盖；引导会话发现实现（发消息不再死路）；Moments 发布/评论输入绑定（原按钮空转）；统一 `isFromHuman`（原两套矛盾约定）；legacy 数据先导入后清除（登出不再删导入源）；推送注册改 `UIApplication.shared`；结构化回传改真 JSON（原双层编码）；清理死代码（`AppStateBox`、`_placeholder`）；人类消息气泡靠右对齐。
- **Xcode 真编类型检查修复（`e1f3d80`–`b3612bd`）**：`OutboxStore` 中 `#Predicate` 枚举 rawValue 提升；旧请求层 `APIError` 改名 `LegacyAPIError`；修正 `MainActor.run` 闭包签名与 `RealtimeClient` `nonisolated` ISO-8601 解码辅助方法；`MemberImportVisibility` 下补齐 `import Combine`；`SignInWithAppleView` 改用原生 `SignInWithAppleButton`；重命名 `OnboardingMessageBubble`；`LegacyAppRoot` 适配 `@Observable` 存储；`AnyCodableJSON.decodeValue` 改为 static；修正 `ServerPayload.init(from:)` 解码与 `.environmentObject(cloud)` 注入。

---

## [0.10.0] — 2026-03-30

### 新增 — T12–T16 Web↔iOS 功能对齐

完整实现 Web 应用中所有缺失的 iOS 功能。

#### T12 — 聊天高级交互
- **ForwardMessageSheet** — 消息转发到其他会话，带消息预览。
- **RedPacketSheet** — 发送虚拟红包，支持自定义金额和祝福语。
- **TriviaQuizView** — 聊天内知识问答小游戏，带分数追踪。
- **IdiomChainView** — 成语接龙文字游戏。
- **PollComposerView** + **ChatPoll 模型** — 在群聊中创建和投票。
- **GroupDetailsView** — 群聊管理（公告/权限/成员/投票）。
- **MessageBubble** 新增 `[FORWARDED:]`、`[RED_PACKET:]`、`[GAME:]`、`[POLL:]` 特殊消息渲染。

#### T13 — 设置高级面板
- **GlobalMessageSearchView** — 跨会话全文消息搜索。
- **KnowledgeBaseView** — 知识库文档导入、管理和开关。
- **ModelSwitcherView** — AI 模型快速切换和 Token 估算。
- **KnowledgeGraphView** — 知识图谱节点管理与可视化。
- **LearningReportView** — 使用数据汇总分析与导出。

#### T14 — 社交页面
- **FriendsView** — 好友列表，支持搜索、星标、分组、自定义好友增删改。
- **FriendGroupsView** — 好友分组创建与管理，支持颜色标记。
- **FriendService** — 好友分组和元数据持久化服务。
- **LeaderboardView** — 多维度排行榜（积分/亲密度/签到/成就）。
- **AgentsView** — 智能体列表，支持搜索和自定义智能体管理。
- **AgentWorkspaceView** — 任务智能体多话题工作区。

#### T15 — 自定义角色/智能体管理
- **CustomPersonaEditorSheet** — 创建和编辑自定义 AI 好友/智能体的共享编辑器。
- **PersonaStore** — 新增 `upsertCustomPersona()` 统一新增/编辑和持久化。
- FriendsView 和 AgentsView 支持完整的上下文菜单创建/编辑/删除自定义角色。

#### T16 — 数据导入导出扩展验证
- **StorageService** — 新增 `allowedImportKeys` 白名单覆盖所有新存储键。
- **DataImporter** — 按键类型验证、大小限制和 `reloadAllStores` 刷新链路。
- 导入白名单覆盖：`friends.groups`、`friends.meta`、`knowledgeBase`、`knowledgeGraph.custom`、`personas.custom`。

### 变更
- **ChatStore** — 新增群聊管理、投票生命周期、消息转发、话题会话和全局搜索方法。
- **ChatSession 模型** — 扩展 `announcement`、`permissions`、`polls`、`parentSessionId`、`topicTitle` 字段。
- **DashboardView** — 快捷操作新增好友导航入口。
- **SettingsView** — 新增 5 个高级面板的 NavigationLink。
- **Chat_Buddy_iOSApp** — 注入 `FriendService` 环境对象。
- **AGENTS.md / CLAUDE.md** — 更新目录结构、存储键和开发状态。

### 文档
- 新建 `docs/WebToiOSMigration/PARITY_REPORT_2026-03-30.md` — Web↔iOS 功能对齐正式报告。

## [0.9.1] — 2026-03-21

### 新增

- **测试目标与共享 Scheme**
  - 新增 `Chat_Buddy_iOSTests` 与 `Chat_Buddy_iOSUITests`。
  - 新增共享 Scheme：`Chat_Buddy_iOS.xcodeproj/xcshareddata/xcschemes/Chat_Buddy_iOS.xcscheme`。
- **背景动画选择能力**
  - `BackgroundPickerView` 现支持在全局和单聊天维度选择 `AnimatedBackground` 动画效果。

### 变更

- **备份/恢复覆盖范围升级为全量存储**
  - `DataExporter` 新增 `StorageService.exportAll()` 的原始 `storageData` 导出。
  - `DataImporter` 先恢复 `storageData`，再通过 `APIConfigStore.reloadFromStorage()` 同步内存态配置。
  - 备份设置中新增 `hasCompletedOnboarding`。
- **聊天工具执行链路增强**
  - `AIPipeline.Result` 新增 `toolOutputs`。
  - `ChatViewModel` 先追加 `.tool` 消息，再展示助手回复，工具结果可见。
  - 群聊路径已统一把 `toolExecutor` 传入 `AIPipeline.run(...)`。
- **仪表盘交互补齐**
  - 快捷操作中的新建聊天/好友入口已接入实际 Tab 跳转。
  - 今日推荐卡片支持进入聊天页。

### 修复

- **动画强度真正作用于界面**
  - 当 `AnimationIntensity == .none` 时，聊天背景动画关闭。
  - 正在输入指示器的开关与速度现在跟随 `ThemeManager.animationIntensity`。
- **Moments 与社交系统联动缺口**
  - 新点赞会触发 `onMomentLiked` 任务进度。
  - 用户发动态会触发 `onMomentsPosted`。
  - 亲密度达到 100 会触发 `onIntimacyMaxed`。
- **本地化收尾**
  - 替换 Moments/Settings 中剩余硬编码文案为 `localization.t(...)`。
  - 补充背景动画与设置相关的 `Localizable.xcstrings` 词条。
- **后台任务注册时机优化**
  - `MomentsBackgroundScheduler.register()` 移至 `App.init()` 且改为幂等。
  - 后台任务处理器内部初始化依赖 Store，避免状态引用问题。
- **代码清理**
  - 修复受影响位置的 `personaId` 废弃用法。
  - 删除废弃文件 `Features/Moments/MomentsPlaceholderView.swift`。

## [0.9.0] — 2026-02-28

### 新增 — T11 角色记忆系统 (Character Memory System)

为每个 AI 人格增加了长期记忆功能：AI 会在对话中学习有关用户的事实情况，跨会话进行持久化并回调记忆，使得角色关系具有连续性的感觉。

#### 数据层
- **`Models/CharacterMemory.swift`** — 新增两种类型：
  - `MemoryCategory` 枚举（`preference`/喜好, `fact`/事实, `event`/事件）。带有各自的颜色标记以及 1-10 级的重要程度符号（⬜ 🟨 🟧 🟥 ⭐）。
  - `CharacterMemory` 结构体：拥有唯一 ID、内容、重要度、创建时间和遗忘标记等。
  - 持久化封装 `MemoriesData` 存于 UserDefaults `chat-buddy:memories`。

#### 服务层
- **`Services/Memory/MemoryService.swift`** — 单例提供读取和写入用户记忆的方法 `addMemory` 和 `relevantMemories`。
- **关联查重机制** — 使用 Jaccard 相似度算法，相似度超过 **0.85** 的重复记忆会被丢弃。
- **记忆衰减** `applyDecay()` — 长时间未回调的无关记忆，系统会在对应的存活窗口自动进行软删除。
- **`Services/Memory/MemoryInjector.swift`** — `memoryBlock` 助手向大语言模型注入最新的相关记忆块。

#### 集成修改
- **`Services/Chat/AIPipeline.swift`**: 解析 AI 的 `[MEMORY_SAVE]` 并抽取记忆项保存。
- **`Features/Chats/MemoriesView.swift`** — 在 ChatView 页面内的全新的 Toolbar 面板，用来审查该模型为你保留的长期记忆。支持手动新建记忆和清空记录。
- **本地化** — 新增了 11 个对应中文词条 (`memories_*`) 供全局调换。

---

## [0.8.0] — 2026-02-28

### 新增 — T09 沉浸式背景系统 (Immersive Background System)

为聊天视图添加了支持覆盖的渐变背景层以及全局设置选项。

#### 数据与服务
- **`Models/ChatBackground.swift`** — `ChatBackgroundPreset` 支持 10 个预设，如 默认、极光、日落、海洋、玫瑰等。
- **`Services/Background/BackgroundStore.swift`** — 以字典的形式持有每场私聊的特定设定。

#### 视图层
- **`Features/Settings/Appearance/BackgroundPickerView.swift`** — 面板提供 90pt 大小的即时预览。
- **`ChatView`** 改写底层视图树渲染。

---

## [0.7.0] — 2026-02-28

### 新增 — T10 社交与互动系统 (Social & Interaction Features)

全新的用户信息、积分经济体系、成就中心、每日签到、送礼及迷你游戏机制。

#### 模型
- **`Models/UserProfile.swift`** — `UserProfile` 包含昵称、Emoji头像及个性签名。
- **`Models/Achievement.swift`** — 包含成就字典与每日任务状态逻辑。

#### 服务
- **`Services/Social/SocialService.swift`** — 处理所有的积分逻辑 `addPoints`, `spendPoints`, 并勾稽所有的自动签到与状态任务回调。
- 联动 `AffinityService` 进行亲密度自动增加机制。

#### 界面
- 用户个人信息编辑单页。
- **成就视图** 带有未解锁锁定的置灰机制与七日交互记录条。
- **礼品赠送面板**, **猜拳对战游戏**, 以及 **猜数字界面**。

---

## [0.6.0] — 2026-02-25

### 新增 — T08 Moments (朋友圈)

实现了类似微信朋友圈的图文与瀑布流架构。

#### 核心修改
- `MomentsStore.swift` 提供 `createPost`、图片压缩加载等文件 CRUD。
- `MomentsService.swift` 提供了时间回调和每日自动分发的 Holiday AI 祝福。
- 引入 `BGAppRefreshTask` + `MomentsBackgroundScheduler`，保证脱离系统在前台依旧能够模拟 AI 生态规律独立发送贴文。
- 构建了带有图片缩放以及即时预览的 `PostComposerView.swift`。

---

## [0.5.0] — 2026-02-25

### 新增 — T07 进阶聊天功能 (Advanced Chat Features)

#### 修改
- `ChatMessage` 增加底层 Unix Timestamp 的双向绑定以及 `quotedMessageId` 串联跟帖回复支持。
- 全新 `BookmarkService` 与 `DraftService` 草稿存储过期逻辑。
- 添加置顶回话 `pinSession` 以及搜索消息功能 `searchMessages`。
- 新增点击长按后的 `MessageBubble` 回复组件支持。

---

## [0.2.0 - 0.4.1] — 2026-02-24

### 核心引擎
- T06 系统级 **亲密度分级提示符 (Affinity & Mood System)** 影响大模型的词法输出。
- T05 `AIPipeline` — 加入 Context 动态窗口压缩（只传入末尾 8 条）以及回复延时函数。
- T04 ChatStore 引擎 — ViewModel 中正式连入核心上下文传输接口 `/chat/completions`。
- 界面补全：`TypingIndicator` 动画，主屏首页 Widget 各看板的统计值绑定等。

---

## [0.1.0] — 2026-02-23

### 初始化搭建
- **T01 — 语言本地化** 部署了 `.xcstrings` 中英文全套字典。
- **T02 — 核心架构** 创建 `APIConfig` 引擎及 `APIClient`。
- **T03 — UI 系统** 集成 Glassmorphism 样式组、主题引擎 (黑暗/系统)、配色方案拾取回调。
- iOS 26 `.glassEffect` SDK 代码与降级代码集成处理。
