[English](CHANGELOG.md) | [简体中文](CHANGELOG_zh.md)

# 更新日志 (Changelog) — Chat Buddy iOS

这里记录了针对 iOS 原生应用的所有重要修改指引。
格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/) 规范。

---

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
