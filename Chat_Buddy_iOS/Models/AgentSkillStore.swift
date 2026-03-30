import Foundation

/// Agent skill definitions for task-specialist personas.
/// Port of agentSkills.js — 20 skills across 6 categories.
enum AgentSkillStore {

    // MARK: - Data Types

    struct AgentSkill: Identifiable, Codable {
        let id: String
        let name: String
        let nameZh: String
        let description: String
        let category: String
        let promptEnhancement: String
        let tools: [String]
        let toolsEnabled: Bool
    }

    // MARK: - All Skills

    static let allSkills: [AgentSkill] = [
        // Programming
        .init(id: "code-generation", name: "Code Generation", nameZh: "代码生成",
              description: "Generate code from natural language descriptions",
              category: "programming",
              promptEnhancement: "1. 根据描述生成高质量代码\n2. 使用规范命名和注释\n3. 考虑边界条件和错误处理\n4. 遵循最佳实践和设计模式\n5. 代码需可直接运行",
              tools: ["run_code", "search_docs"], toolsEnabled: false),
        .init(id: "code-review", name: "Code Review", nameZh: "代码审查",
              description: "Review code for bugs, security issues, and improvements",
              category: "programming",
              promptEnhancement: "1. 检查逻辑错误和安全漏洞\n2. 评估性能和可维护性\n3. 提出具体改进建议\n4. 关注代码风格一致性\n5. 识别潜在的边界问题",
              tools: ["search_docs"], toolsEnabled: false),
        .init(id: "debugging", name: "Debugging", nameZh: "调试排错",
              description: "Help diagnose and fix code errors",
              category: "programming",
              promptEnhancement: "1. 分析错误信息和堆栈跟踪\n2. 提供可能的原因分析\n3. 建议具体修复方案\n4. 解释根本原因\n5. 提供预防措施",
              tools: ["run_code", "search_docs"], toolsEnabled: false),

        // Writing
        .init(id: "creative-writing", name: "Creative Writing", nameZh: "创意写作",
              description: "Generate creative content like stories, poems, and scripts",
              category: "writing",
              promptEnhancement: "1. 注重文字的韵律和美感\n2. 使用丰富的修辞手法\n3. 塑造立体的人物形象\n4. 构建引人入胜的情节\n5. 保持风格一致性",
              tools: [], toolsEnabled: false),
        .init(id: "editing", name: "Editing & Proofreading", nameZh: "编辑校对",
              description: "Polish and improve written content",
              category: "writing",
              promptEnhancement: "1. 检查语法和拼写错误\n2. 优化句式结构和流畅度\n3. 确保逻辑连贯性\n4. 保持作者的原始风格\n5. 提出结构性改进建议",
              tools: [], toolsEnabled: false),
        .init(id: "translation", name: "Translation", nameZh: "翻译",
              description: "Translate text between languages with context awareness",
              category: "writing",
              promptEnhancement: "1. 准确传达原文含义\n2. 适应目标语言的表达习惯\n3. 保留专业术语\n4. 注意文化差异和本地化\n5. 保持语气和风格一致",
              tools: [], toolsEnabled: false),
        .init(id: "immersive-translation", name: "Immersive Translation", nameZh: "沉浸式翻译",
              description: "Two-step reflective translation with domain expertise",
              category: "writing",
              promptEnhancement: "1. 使用两步翻译法：先直译再反思优化\n2. 自动识别文本领域（技术/文学/通用）\n3. 遵守术语表约束\n4. 文学文本保留韵律和意境\n5. 技术文本不翻译代码和标识符",
              tools: ["web_search"], toolsEnabled: true),

        // Research
        .init(id: "research", name: "Research", nameZh: "调研",
              description: "Conduct in-depth research on topics",
              category: "research",
              promptEnhancement: "1. 全面搜集相关资料\n2. 评估信息的可靠性\n3. 综合多方观点\n4. 提供结构化分析\n5. 标注信息来源",
              tools: ["web_search", "search_docs"], toolsEnabled: false),
        .init(id: "fact-checking", name: "Fact Checking", nameZh: "事实核查",
              description: "Verify claims and check factual accuracy",
              category: "research",
              promptEnhancement: "1. 对声明逐一进行验证\n2. 查找权威数据来源\n3. 标明已验证和待验证项\n4. 提供可信度等级\n5. 给出修正建议",
              tools: ["web_search"], toolsEnabled: false),
        .init(id: "summarization", name: "Summarization", nameZh: "摘要提炼",
              description: "Condense long texts into key points",
              category: "research",
              promptEnhancement: "1. 提取核心要点和关键信息\n2. 保持信息的完整性\n3. 使用层次化结构\n4. 控制摘要长度\n5. 标出重要细节",
              tools: [], toolsEnabled: false),

        // Education
        .init(id: "teaching", name: "Teaching", nameZh: "教学",
              description: "Explain concepts with examples and analogies",
              category: "education",
              promptEnhancement: "1. 使用通俗易懂的语言\n2. 提供恰当的类比和示例\n3. 循序渐进地展开\n4. 检查理解的掌握程度\n5. 鼓励提问和互动",
              tools: [], toolsEnabled: false),
        .init(id: "quiz-generation", name: "Quiz Generation", nameZh: "出题测试",
              description: "Create quizzes and knowledge assessments",
              category: "education",
              promptEnhancement: "1. 题目覆盖关键知识点\n2. 难度循序渐进\n3. 提供详细解析\n4. 包含干扰选项分析\n5. 给出学习建议",
              tools: [], toolsEnabled: false),

        // Emotional
        .init(id: "active-listening", name: "Active Listening", nameZh: "积极倾听",
              description: "Empathetic listening and supportive responses",
              category: "emotional",
              promptEnhancement: "1. 认真倾听并复述核心内容\n2. 表达共情和理解\n3. 避免评判性语言\n4. 适时提问引导表达\n5. 提供温暖的支持",
              tools: [], toolsEnabled: false),
        .init(id: "emotional-support", name: "Emotional Support", nameZh: "情感支持",
              description: "Provide comfort and coping strategies",
              category: "emotional",
              promptEnhancement: "1. 给予温暖的陪伴和安慰\n2. 帮助识别和命名情绪\n3. 提供实用的应对策略\n4. 鼓励积极的自我对话\n5. 必要时建议寻求专业帮助",
              tools: [], toolsEnabled: false),
        .init(id: "mindfulness", name: "Mindfulness", nameZh: "正念冥想",
              description: "Guide mindfulness and relaxation exercises",
              category: "emotional",
              promptEnhancement: "1. 引导深呼吸和放松\n2. 提供正念冥想指导\n3. 帮助关注当下感受\n4. 教授身体扫描技巧\n5. 培养觉察力和接纳心态",
              tools: [], toolsEnabled: false),

        // Creative
        .init(id: "design-thinking", name: "Design Thinking", nameZh: "设计思维",
              description: "Apply design thinking methodology to problems",
              category: "creative",
              promptEnhancement: "1. 运用共情理解用户需求\n2. 明确定义问题陈述\n3. 头脑风暴生成创意\n4. 快速原型验证\n5. 迭代优化方案",
              tools: [], toolsEnabled: false),
        .init(id: "brainstorming", name: "Brainstorming", nameZh: "头脑风暴",
              description: "Generate creative ideas and solutions",
              category: "creative",
              promptEnhancement: "1. 鼓励发散性思维\n2. 不急于评判想法\n3. 在已有想法基础上延伸\n4. 从不同角度思考\n5. 量化目标和优先排序",
              tools: [], toolsEnabled: false),
        .init(id: "visual-design", name: "Visual Design", nameZh: "视觉设计",
              description: "Design guidance for UI, graphics, and layouts",
              category: "creative",
              promptEnhancement: "1. 遵循设计原则和视觉层次\n2. 关注色彩和字体搭配\n3. 确保用户体验友好\n4. 考虑响应式适配\n5. 提供可落地的设计方案",
              tools: [], toolsEnabled: false),
    ]

    // MARK: - Query Functions

    static func getSkillsByCategory(_ category: String) -> [AgentSkill] {
        allSkills.filter { $0.category == category }
    }

    static func getSkillById(_ id: String) -> AgentSkill? {
        allSkills.first { $0.id == id }
    }

    static let categories = ["programming", "writing", "research", "education", "emotional", "creative"]

    static func categoryLabel(_ cat: String, isZh: Bool) -> String {
        switch cat {
        case "programming": return isZh ? "编程" : "Programming"
        case "writing":     return isZh ? "写作" : "Writing"
        case "research":    return isZh ? "调研" : "Research"
        case "education":   return isZh ? "教育" : "Education"
        case "emotional":   return isZh ? "情感" : "Emotional"
        case "creative":    return isZh ? "创意" : "Creative"
        default:            return cat
        }
    }

    /// Combine prompt enhancements from multiple skill IDs into one block.
    static func combineSkillPrompts(_ skillIds: [String]) -> String {
        skillIds.compactMap { getSkillById($0)?.promptEnhancement }
            .joined(separator: "\n\n")
    }

    /// Get unique tool names required by the given skills.
    static func getRequiredTools(_ skillIds: [String]) -> [String] {
        Array(Set(skillIds.flatMap { getSkillById($0)?.tools ?? [] }))
    }

    /// Map an agent persona to its relevant skills based on agent type / id keywords.
    static func getSkillsForAgent(agentId: String) -> [AgentSkill] {
        let id = agentId.lowercased()
        var matched: [String] = []
        if id.contains("code") || id.contains("dev") || id.contains("程序") { matched += ["code-generation", "code-review", "debugging"] }
        if id.contains("write") || id.contains("writer") || id.contains("写作") { matched += ["creative-writing", "editing"] }
        if id.contains("research") || id.contains("scholar") || id.contains("学术") { matched += ["fact-checking", "research-synthesis"] }
        if id.contains("tutor") || id.contains("teach") || id.contains("教") { matched += ["tutoring", "quiz-generation"] }
        if id.contains("counsel") || id.contains("心理") { matched += ["counseling", "conflict-resolution"] }
        if id.contains("design") || id.contains("art") || id.contains("设计") { matched += ["brainstorming", "design-feedback"] }
        if id.contains("translate") || id.contains("翻译") { matched += ["editing", "summarization"] }
        return matched.compactMap { getSkillById($0) }
    }
}
