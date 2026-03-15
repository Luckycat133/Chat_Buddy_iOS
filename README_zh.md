[English](README.md) | [简体中文](README_zh.md)

# Chat Buddy iOS

**Chat Buddy iOS** 是一款基于 SwiftUI 纯原生打造的高性能智能 AI 伴侣应用。该项目将广受欢迎的 Web 端“Chat Buddy”的核心功能深度迁移至 iOS 环境，提供了无缝衔接且纯粹的原生体验。

![iOS 17+](https://img.shields.io/badge/iOS-17.0+-black?style=flat&logo=apple)
![SwiftUI](https://img.shields.io/badge/SwiftUI-100%25-blue?style=flat&logo=swift)
![License MIT](https://img.shields.io/badge/License-MIT-green.svg)

## ✨ 核心特性

- 👯‍♂️ **多角色沉浸式群聊**: 允许在同一个群组内混合多个 AI 人格。底层逻辑原生支持消息路由分配，处理交错、独立的 AI 回复，并带来真实的人类级别群聊动态体验。
- ⚡️ **ReAct 工具执行引擎**: 应用内置了强大的 Reasoning and Acting (ReAct) 流水线。遇到特殊“任务型”大语言模型时，应用可赋予 AI 主动使用工具（例如无缝调用免费的 DuckDuckGo 即时搜索），完全不需要依赖后端的 Function Calling 服务器架构。
- 🌌 **沉浸式动态粒子背景**: 支持极致性能、极低功耗的流体动态壁纸。轻量级动画（如极光）使用 SwiftUI `Canvas` 绘制，复杂的粒子特效（雪、雨、火焰、星空）则由底层的 SpriteKit (`SKEmitterNode`) 提供毫不费力的 60fps 硬件加速渲染。
- ⏱️ **Moments 后台编排 (朋友圈)**: 深度集成 iOS `BackgroundTasks` 机制 (`BGAppRefreshTask` & `BGProcessingTask`)。你的 AI 伴侣们能够自主、自然地在后台发文字/图片状态、记住你的生日、甚至在特定的节假日为你送出祝福，即便你并未打开应用。
- 🎨 **顶级原生 UI/UX**: 配备严谨的 Glassmorphism 毛玻璃设计系统。支持自定义提取主题强调色、流畅的 SwiftUI 过渡动画，并在整个应用内完美支持英文和简体中文的动态双语切换。

## 🛠 技术栈

- **界面框架**: SwiftUI
- **核心引擎**: Swift 并发 (async/await)
- **后台进程调度**: BackgroundTasks Server
- **视觉特效**: SwiftUI Canvas + SpriteKit
- **数据持有**: 基于向后兼容映射的原生泛型 JSON 持久化

## 📦 如何构建与运行

1. 克隆本仓库到你的 Mac。
2. 用 Xcode 打开 `Chat_Buddy_iOS.xcodeproj` (最低要求 Xcode 15+)。
3. 本项目完全使用标准的 iOS 原生框架，不需要繁杂的第三方依赖 (No CocoaPods / No SPM)。
4. 选择 iOS 模拟器或真实设备，按下 `Cmd + R` 即可直接编译运行！

## 📄 许可协议

本项目基于 **[MIT License](LICENSE)** 开源。

你可以完全自由地使用、修改、分发这些代码，甚至将其集成到你的商业或闭源项目中。我们仅要求保留原始的版权声明即可。

---

*作为一款将本地 AI 会话架构推向设备级后台深度调度的应用，我们致力于打造一款与你形影不离的虚拟情感伴侣家园。*
