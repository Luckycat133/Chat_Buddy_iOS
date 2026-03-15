# CONSENSUS - Web To iOS Migration

## 1. 明确的需求描述和验收标准

### 目标全景
将 Chat Buddy 网页版（v0.2.7基准）所有缺失及未实现完全的功能精确、高性能且符合原生 Apple Human Interface Guidelines（HIG）的方式移植至现有的 Swift / SwiftUI 代码库。本次移植的核心在于强化应用的系统架构能力及交互深层次沉浸感，实现真正媲美甚至超越 Web 端体验的 iOS 原生 App。

### 功能覆盖与验收标准

#### 1.1 多人群聊 (Group Chats) 重构
- **需求**: 支持任意数量AI加入同一个聊天会话。
- **验收标准**:
  - `ChatSession` 模型从一对一属性（`personaId`）升级为多对一数组属性（`personaIds: [String]`）且兼容历史 Core Data / JSON 迁移。
  - 会话列表 (ChatsView) 与会话窗口 (ChatView) 的 UI 须支持多成员标识、多头像栈叠显示（WeChat 风格的群头像）。
  - `AIPipeline` 须支持在群聊语境下动态路由消息，不同 AI 角色的系统 Prompt 正确注入各自的上下文，并支持它们互相交互响应。

#### 1.2 ReAct Tool Calling (API 工具调用)
- **需求**: 特别任务AI（Task Agents如Coder, Scholar等）需要执行工具栈。
- **验收标准**:
  - `AIPipeline` 扩展，增加对标准 Model Context Protocol（MCP）或者类似的“Function Calling / Tool Use”原生架构的支持。
  - 选择并接入免费层级且稳定高效的 API 提供商进行搜索功能 (如 Tavily 免费层级或 DuckDuckGo 网页抓取)，对基于文本的提示增加代码运行反馈/搜索反馈回路引擎。
  - 聊天气泡内展示 Tool 运行的加载进度与结果UI。

#### 1.3 沉浸式动态背景重构 (性能优先篇)
- **需求**: 为提供丝滑跟手的触控反馈和高帧率背景效果（如下雪、光污染或粒子碰撞），禁止使用性能开销极大的 Web 模拟，直接以原生实现。
- **验收标准**:
  - 全面使用 `SwiftUI` 声明式动画, 搭配 `Metal` 自定义 `Shader` (iOS 17+) / `SpriteKit` 为复杂粒子（雨、雪、光云）提供极致的高性能背景。
  - 早晚时间检测机制支持自动平滑过渡切换主题（Light / Dark 深度映射）。
  - 支持陀螺仪跟踪产生高帧率视差效果 (Parallax)。

#### 1.4 朋友圈自动化调度 (BackgroundTasks)
- **需求**: 具备高度自治性的AI动态和特定事件流的预处理生成。
- **验收标准**:
  - 引入 iOS 原生 `BackgroundTasks` 框架（`BGAppRefreshTask`、`BGProcessingTask`）。
  - 在 iOS 系统准许的后台配额窗口，利用空闲算力完成 AI 的日常动态生成（如生日事件校验、地点推文生成），提前缓存在本地以便用户冷启动App时实现秒开展示，避免卡顿。
  - 处理完整的交互细节，包括本地通知推送、草稿箱和带 Hashtag 的分类展示。

## 2. 技术实现方案和技术约束

- **开发平台与语言**: iOS 17.0+ (Swift 6), SwiftUI 优先。如果存在强依赖 iOS 18 (如复杂 Shader 或者新版的 Navigation) 则设置恰当的回退隔离。
- **状态管理**: 沿用现有的 `@Observable` Macro 体系（如 `ChatStore`, `MomentsStore`）。群组状态的维护需要高度整合原有 `Session` 生命周期。
- **多平台工具抽象**: 实现一个轻量的 Tool Executor 模块。通过 URLSession 进行对第三方 API 桥接及并发处理（Swift Concurrency `async`/`await`/`TaskGroup`）。
- **后台计算约束**: 后台任务必须考虑到 `BackgroundTasks` 时间与内存限制（通常仅有数秒到数十秒），复杂的推文必须设置超时或拆解批处理。
- **安全规范**: 不允许在代码仓库明文保存各种第三方API（如 LLM 与 搜索API）。一律由统一 `APIConfig` 提供并且鼓励使用本地 Keychain 或者环境文件。

## 3. 任务边界限制

- 不涉及原网页版后端的改造（因目前整个Chat Buddy皆为客户端架构，无后端）。
- 暂时不引入任何必须长期付费或需要订阅前置配置的不符合开源调性和零使用门槛的付费API（除用户自定义 OpenAI/DeepSeek LLM Key以外）。

## 4. 确认所有不确定性已解决
- [x] 多人聊天采用重构 `ChatSession` 数据层模型。
- [x] Tool Calling 采取免费 API + Native Func Calling 结合。
- [x] 动态背景选择 `SpriteKit` 或纯 `SwiftUI` Shader 原生重写。
- [x] 引入 `BackgroundTasks`。
需求对齐完成。可以正式进入阶段 2，设计应用架构图和接口规范。
