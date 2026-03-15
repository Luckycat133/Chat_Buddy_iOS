# ACCEPTANCE - Web To iOS Migration

## 执行进度记录

| 任务 | 状态 | 完成内容 |
|------|------|---------|
| Task 0: Data Layer Migration | ✅ 完成 | ChatSession/ChatMessage 扩展 + ChatStore 群聊支持 |
| Task 1: Group Chat UI | ✅ 完成 | SessionAvatarView + GroupPickerSheet + ChatsView + ChatView + MessageBubble |
| Task 2: ReAct Tool Engine | ✅ 完成 | ToolExecutorService + DuckDuckGo 免费搜索 + AIPipeline 集成 |
| Task 3: Dynamic Backgrounds | ✅ 完成 | AnimatedBackgroundView (Aurora/Snow/Rain/Fire/Stars) + BackgroundStore 扩展 |
| Task 4: BGTasks + Moments | ✅ 完成 | MomentsBackgroundScheduler (iOS BackgroundTasks 框架) |
| Task 5: Integration & QA | ✅ 完成 | 本地化字符串补充 + 环境注入 + 生命周期接入 |

## ✅ Xcode 项目自动配置完毕

以下底层配置已直接修改 `project.pbxproj` 自动完成，**无需手动操作**：

1. **后台任务标识符 (BGTaskSchedulerPermittedIdentifiers)**  
   已自动添加 `com.chatbuddy.moments.refresh` 以及 `com.chatbuddy.moments.storyevents`。
2. **后台运行权限 (UIBackgroundModes)**  
   已自动勾选/添加 `fetch`（用于应用刷新）和 `processing`（用于耗时更新）。
3. **SpriteKit 框架支持**  
   使用纯 Swift 源码中的 `import SpriteKit` 实现模块自动链接，无需额外手动在 Build Phases 添加 `.framework`。

### 💡 可选高级配置（提升动效）
当前动态背景（雪、雨、火粉、星空）系统采用的是**纯代码降级的粒子效果（Programmatic Fallback）**，不仅体积小且无崩溃风险。若追求极致画质体验，你可以在 Xcode 项目资源目录（Assets 或直接拖入根目录）新建几个 SpriteKit Particle Files (`.sks`) ，分别命名为 `Stars.sks`, `Snow.sks`, `Rain.sks`, `Fire.sks`，它们将被系统自动优先加载加载！

---

## 新增文件清单

| 文件 | 说明 |
|------|------|
| `Models/ChatSession.swift` | ✅ 重构：支持 personaIds + isGroup |
| `Models/ChatMessage.swift` | ✅ 扩展：speakingPersonaId + ToolCall/ToolResult |
| `Services/Chat/ChatStore.swift` | ✅ 新增群聊 CRUD |
| `Services/Chat/ToolExecutorService.swift` | 🆕 ReAct 工具执行引擎 + DuckDuckGo 搜索 |
| `Services/Chat/AIPipeline.swift` | ✅ 接入 toolExecutor + toolHint |
| `Services/Background/BackgroundStore.swift` | ✅ 新增 animatedBackground 存储 |
| `Services/Moments/MomentsBackgroundScheduler.swift` | 🆕 iOS BGTask 后台调度 |
| `Features/Chats/GroupPickerSheet.swift` | 🆕 群聊创建界面 |
| `Features/Chats/Components/AnimatedBackgroundView.swift` | 🆕 动态粒子背景 |
| `SharedViews/SessionAvatarView.swift` | 🆕 通用会话头像（1v1 / 群聊）|
| `Chat_Buddy_iOSApp.swift` | ✅ 接入 BGTask 注册 + ToolExecutorService 环境 |
| `Localization/Localizable.xcstrings` | ✅ 新增 13 个双语字符串 |
