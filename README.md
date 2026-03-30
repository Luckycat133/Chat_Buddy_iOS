[English](README.md) | [简体中文](README_zh.md)

# Chat Buddy iOS

![iOS 26+](https://img.shields.io/badge/iOS-26.0+-black?style=flat&logo=apple)
![SwiftUI](https://img.shields.io/badge/SwiftUI-100%25-blue?style=flat&logo=swift)
![License MIT](https://img.shields.io/badge/License-MIT-green.svg)

## ✨ Key Features

- 👯‍♂️ **Multi-Persona Group Chats**: Mix and match multiple AI personas in a single conversation. The engine natively routes messages and handles staggered, independent AI responses to simulate real human group dynamics.
- ⚡️ **ReAct Tool Execution Engine**: A built-in reasoning and acting pipeline allows specialized "Task Agent" personas to fetch real-time data seamlessly through tools (e.g., integrating the free DuckDuckGo Instant Answer API) without requiring complex backend server function calling.
- 🌌 **Immersive Dynamic Backgrounds**: High-performance, battery-efficient animated wallpapers. It leverages SwiftUI `Canvas` for lightweight fluid effects (like drifting Auroras) and falls back to SpriteKit-powered particle systems (`SKEmitterNode`) for complex elements like Snow, Rain, Fire, and Starfields.
- ⏱️ **Moments Background Orchestration**: Deep integration with the iOS `BackgroundTasks` framework (`BGAppRefreshTask` & `BGProcessingTask`). Your AI companions will naturally and autonomously generate updates, celebrate birthdays, and post holiday greetings to their "Moments" feed even while the app is completely backgrounded.
- 🎨 **Premium Native UI/UX**: Built with a rigorous design system featuring glassmorphism elements, dynamic accent colors, smooth SwiftUI transitions, and robust bilingual (English/Chinese) localization support.

## 🛠 Tech Stack

- **UI Framework**: SwiftUI
- **State Model**: `@Observable` + Environment injection
- **Core Engine**: Swift Concurrency (`actor`, `async/await`)
- **Background Processes**: iOS `BackgroundTasks` (`BGAppRefreshTask`, `BGProcessingTask`)
- **Visual Effects**: SwiftUI Canvas + SpriteKit
- **Data Persistence**: `StorageService` (`UserDefaults`) + JSON export/import backup

## 📦 How to Build

1. Clone the repository.
2. Open `Chat_Buddy_iOS.xcodeproj` in Xcode (requires Xcode 26.2+).
3. The project uses standard iOS frameworks and requires no complex third-party setup.
4. Set your run destination and hit `Cmd + R`.

### Terminal Build & Test

```bash
# Build
xcodebuild -project Chat_Buddy_iOS.xcodeproj \
  -scheme Chat_Buddy_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build

# Test
xcodebuild -project Chat_Buddy_iOS.xcodeproj \
  -scheme Chat_Buddy_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test
```

## 📄 License

This project is licensed under the **[MIT License](LICENSE)**. 

You are completely free to use, modify, distribute, or incorporate this code into your own commercial or open-source projects. We only ask that you retain the original copyright notice.

---

*This application pushes the boundaries of localized AI chat architectures into full native device orchestration, delivering a deeply personal virtual companionship platform.*
