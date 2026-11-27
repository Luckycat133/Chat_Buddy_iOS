# AGENTS.md — Chat Buddy iOS

## 当前产品边界与技能入口

涉及产品行为、云同步、离线变更、备份/导入或 TestFlight 时，先读 [.agents/skills/chat-buddy-ios-demo-development/SKILL.md](.agents/skills/chat-buddy-ios-demo-development/SKILL.md) 及其当前检出参考；平台辅助技能通过 [.agents/SKILLS.md](.agents/SKILLS.md) 按需选择。

- **托管 Demo 权威边界**：历史本地端口/直连 Provider 架构与旧 `UserDefaults` 示例仅作遗留参考，**不是当前云端 Demo 契约**。必须保持旧数据可读，但严禁为托管 Demo 擅自恢复本地 AI 权威或删除兼容数据去迎合旧文档。
- **验证真实性**：模拟器可用性须现场核查；`xcodebuild` 编译通过只证明可编译，不证明用户可见界面、后端或 APNs 行为正常。

## 构建与测试命令

```bash
xcodebuild -project Chat_Buddy_iOS.xcodeproj -scheme Chat_Buddy_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

xcodebuild -project Chat_Buddy_iOS.xcodeproj -scheme Chat_Buddy_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## iOS 26 / SwiftUI 高危踩坑警告（附原因）

- **Xcode File System Synchronized**：在目录新增 Swift 文件会被自动纳入编译目标，**不要手改 `.xcodeproj/project.pbxproj`**，否则极易引入工程文件损坏。
- **SourceKit 误报**：SourceKit 隔离分析单文件时常误报跨文件类型缺失；以完整 `xcodebuild` 输出 `BUILD SUCCEEDED` 为唯一真源。
- **iOS 26 `@MainActor` 与 Actor**：不要在 `actor` 上写 `static let default`（actor 默认 nonisolated 初始化）；不要在 `@State` 初始化阶段读 `@Environment`（改用 `.onAppear` / `.task` 同步）；在 `body` 内用 `@Bindable var foo = foo` 从 `@Environment` 的 `@Observable` 取绑定。
- **Liquid Glass & API 细节**：`.glassEffect(.regular.interactive())` 必须带括号作方法调用；颜色转换用 `UIColor`（iOS 无 `NSColor`）；数组 `remove(atOffsets:)` 需 `import SwiftUI`；`DateFormatter`/`NumberFormatter` 须用 `private static let` 缓存，勿放在计算属性里反复创建。
- **OLED 深色模式漏判**：仅判断 `themeManager.mode == .dark` 会漏掉“跟随系统深色”，必须结合 `@Environment(\.colorScheme)` 联合判定。
- **存储 Key 命名例外**：多数 `UserDefaults` Key 带 `chat-buddy:` 前缀，但 `chatSessions` 和 `personas.custom` **无前缀**——修改读写逻辑时切勿擅自加前缀，否则存量会话与自定义角色会全部“消失”。

## 深入参考（1 跳指针）

- 完整目录树、Root `@Environment` 注入清单、`UserDefaults` 全量 Key 表、Web 对照映射与历史迭代记录：[docs/agent-reference.md](docs/agent-reference.md)
