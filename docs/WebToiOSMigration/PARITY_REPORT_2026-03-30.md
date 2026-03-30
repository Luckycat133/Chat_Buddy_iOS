# Web ↔ iOS 功能对齐报告（2026-03-30）

## 1. 对比范围与方法

- Web 基线：`Chat_Buddy_副本/src/`（路由、页面、聊天协议、设置高级工具）。
- iOS 目标：`Chat_Buddy_iOS/`（SwiftUI + @Observable 架构）。
- 方法：页面级功能盘点 + 交互协议检索 + 数据模型/存储链路核对 + 代码实现 + 定向静态检查。

## 2. 功能对齐矩阵（截至本次提交）

| 功能域 | Web 状态 | iOS 状态 | 结论 |
|---|---|---|---|
| Dashboard / Chats / Moments / Settings / Achievements | 完整 | 完整 | 已对齐 |
| Friends 页面（搜索/星标/分组） | 完整 | 已实现 | 已对齐 |
| Friend Groups 管理 | 完整 | 已实现 | 已对齐 |
| Leaderboard（积分/亲密度/签到/成就） | 完整 | 已实现 | 已对齐 |
| Agents 列表 + Agent Workspace（多话题会话） | 完整 | 已实现 | 已对齐 |
| 聊天消息转发 | 完整 | 已实现 | 已对齐 |
| 红包消息 | 完整 | 已实现 | 已对齐 |
| Trivia / 成语接龙小游戏 | 完整 | 已实现 | 已对齐 |
| 群详情（公告/权限/成员/投票） | 完整 | 已实现 | 已对齐 |
| Global Message Search | 完整 | 已实现 | 已对齐 |
| Knowledge Base 面板 | 完整 | 已实现（文档导入/开关/存储） | 部分对齐 |
| Model Switcher + Token 估算 | 完整 | 已实现 | 已对齐 |
| Knowledge Graph 面板 | 完整 | 已实现（节点管理） | 部分对齐 |
| Learning Report | 完整 | 已实现（汇总+导出） | 已对齐 |
| 自定义角色/智能体 | 完整 | 已实现（新增/编辑/删除 + 持久化） | 已对齐 |
| 导入导出兼容新功能数据 | 完整 | 已实现（key 白名单 + 解码校验） | 已对齐 |

## 3. 本次新增/完善实现

### 3.1 自定义角色链路（新增）

- `SharedViews/CustomPersonaEditorSheet.swift`
  - 自定义好友/智能体编辑器（中英名称、人设、风格、分类）。
- `Models/PersonaStore.swift`
  - 新增 `upsertCustomPersona`，支持新增与编辑统一落盘。
- `Features/Friends/FriendsView.swift`
  - 新增自定义好友创建入口；支持编辑与删除自定义好友。
  - 好友列表过滤为“社交角色 + 自定义社交角色”。
- `Features/Agents/AgentsView.swift`
  - 新增自定义智能体创建入口；支持编辑与删除自定义智能体。
  - 智能体列表合并“预设任务智能体 + 自定义任务智能体”。

### 3.2 数据层兼容（已完成）

- `StorageService`/`DataImporter` 已支持 `personas.custom` 导入校验。
- 导入白名单已覆盖 Friends/Knowledge/Graph/Custom Persona 等新增 key。

## 4. 尚未完全对齐的点（剩余差异）

1. Knowledge Base 目前完成“数据管理层”，但尚未把 KB 检索上下文注入到聊天推理链路（RAG 推理闭环仍可继续增强）。
2. Knowledge Graph 目前为节点管理视图，未实现关系边可视化与路径推理交互（Web 复杂图谱体验仍有差距）。
3. 端到端 iOS 自动化测试覆盖仍不足（目前以静态检查和局部逻辑验证为主）。

## 5. 开发优先级与后续计划

### P0（建议立即）

1. 把 Knowledge Base 接入 `AIPipeline`，实现最小可用 RAG（top-k 片段注入 + prompt 约束）。
2. 增加自定义角色创建/编辑的关键流程单测（ID 保留、category 保留、导入后恢复）。

### P1（短期）

1. Knowledge Graph 增加关系边模型与简单可视化（节点关联/过滤）。
2. 补充 Friends/Agents/GroupDetails UI 回归测试脚本（手工测试清单 + UI Test 起步用例）。

### P2（中期）

1. 统一高级工具页的数据协议，与 Web 完全共模（便于后续双端配置互通）。
2. 对大列表页（搜索/排行榜/消息）做性能采样和缓存优化。

## 6. 测试与验证结果

### 已完成

- 对新增与修改的 Swift 文件进行定向错误检查：无语法/类型错误。
- 自定义角色相关新增文件及改动文件检查通过。

### 未完成（环境限制）

- `xcodebuild` 构建与 iOS 模拟器测试未能执行。
- 当前环境仅 `CommandLineTools`，缺少完整 Xcode.app：
  - 报错：`xcodebuild requires Xcode, but active developer directory is CommandLineTools`。

## 7. 结论

- 本轮已完成大部分 Web→iOS 缺口落地，尤其是聊天高级交互、社交页面、高级设置工具、自定义角色管理链路。
- 当前对齐状态可认为“核心功能已对齐，知识增强（RAG/图谱高级能力）仍有增强空间”。
- 需在完整 Xcode 环境完成最终构建、UI 兼容和性能回归，才能给出最终发布级验收结论。
