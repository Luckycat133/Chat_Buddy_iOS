import Foundation

/// Two-step reflective translation service with domain detection and glossary support.
/// Port of ImmersiveTranslation.js from web version.
enum TranslationService {

    // MARK: - Domain Detection

    enum Domain: String {
        case technical
        case literary
        case general
    }

    private static let techPatterns: [String] = [
        "function", "class ", "import ", "export ", "const ", "let ", "var ",
        "return ", "async ", "await ", "\\{", "\\}", "=>", "API", "HTTP",
        "component", "props", "state", "render", "hook", "npm", "git",
    ]

    private static let literaryPatterns: [String] = [
        "poem", "诗", "metaphor", "隐喻", "stanza", "verse", "rhyme",
        "novel", "小说", "prose", "散文", "haiku", "sonnet",
    ]

    static func detectDomain(_ text: String) -> Domain {
        let lower = text.lowercased()
        var techScore = 0
        var litScore  = 0

        for p in techPatterns where lower.contains(p.lowercased()) { techScore += 1 }
        for p in literaryPatterns where lower.contains(p.lowercased()) { litScore += 1 }

        if techScore >= 3 { return .technical }
        if litScore >= 3  { return .literary }
        return .general
    }

    // MARK: - Glossary

    struct GlossaryEntry {
        let source: String
        let target: String
        let note: String
    }

    static let techGlossary: [GlossaryEntry] = [
        .init(source: "component", target: "组件", note: "UI组件"),
        .init(source: "props", target: "props", note: "不翻译"),
        .init(source: "state", target: "状态", note: ""),
        .init(source: "hook", target: "Hook", note: "不翻译"),
        .init(source: "render", target: "渲染", note: ""),
        .init(source: "lifecycle", target: "生命周期", note: ""),
        .init(source: "callback", target: "回调", note: ""),
        .init(source: "middleware", target: "中间件", note: ""),
        .init(source: "dependency", target: "依赖", note: ""),
        .init(source: "repository", target: "仓库", note: "代码仓库"),
        .init(source: "commit", target: "提交", note: "Git"),
        .init(source: "pull request", target: "合并请求", note: "PR"),
        .init(source: "merge", target: "合并", note: ""),
        .init(source: "branch", target: "分支", note: ""),
        .init(source: "deploy", target: "部署", note: ""),
        .init(source: "endpoint", target: "端点", note: "API"),
        .init(source: "token", target: "token", note: "不翻译"),
        .init(source: "prompt", target: "提示词", note: "AI"),
        .init(source: "embedding", target: "嵌入/向量", note: "AI"),
        .init(source: "fine-tune", target: "微调", note: "AI"),
        .init(source: "API", target: "API", note: "不翻译"),
        .init(source: "SDK", target: "SDK", note: "不翻译"),
        .init(source: "CLI", target: "CLI", note: "不翻译"),
        .init(source: "Promise", target: "Promise", note: "不翻译"),
        .init(source: "async/await", target: "async/await", note: "不翻译"),
        .init(source: "framework", target: "框架", note: ""),
        .init(source: "library", target: "库", note: ""),
        .init(source: "runtime", target: "运行时", note: ""),
        .init(source: "compiler", target: "编译器", note: ""),
        .init(source: "interpreter", target: "解释器", note: ""),
        .init(source: "garbage collection", target: "垃圾回收", note: ""),
        .init(source: "thread", target: "线程", note: ""),
        .init(source: "concurrency", target: "并发", note: ""),
        .init(source: "mutex", target: "互斥锁", note: ""),
        .init(source: "deadlock", target: "死锁", note: ""),
        .init(source: "race condition", target: "竞态条件", note: ""),
    ]

    static let literaryGlossary: [GlossaryEntry] = [
        .init(source: "metaphor", target: "隐喻", note: "修辞"),
        .init(source: "simile", target: "明喻", note: "修辞"),
        .init(source: "alliteration", target: "头韵", note: "修辞"),
        .init(source: "personification", target: "拟人", note: "修辞"),
        .init(source: "irony", target: "反讽", note: "修辞"),
        .init(source: "allegory", target: "寓言", note: "文体"),
    ]

    // MARK: - Expert Prompts

    private static func expertPrompt(for domain: Domain, isZh: Bool) -> String {
        switch domain {
        case .technical:
            return isZh
                ? "你是一名资深技术翻译专家。保留代码标识符和变量名不翻译。使用规范术语表翻译技术名词。"
                : "You are a senior technical translator. Keep code identifiers and variable names untranslated. Use the provided glossary for technical terms."
        case .literary:
            return isZh
                ? "你是一名文学翻译大师。注重保留原文的韵律美感、意境和修辞手法。使句式符合中文美感。"
                : "You are a master literary translator. Preserve the rhythm, imagery, and rhetorical devices of the original. Match target language aesthetics."
        case .general:
            return isZh
                ? "你是一名专业翻译。准确传达原文含义，使用自然流畅的目标语言表达。"
                : "You are a professional translator. Convey the original meaning accurately using natural target language expressions."
        }
    }

    // MARK: - Translation Request Builder

    /// Builds the two-step reflective translation prompt.
    /// The AI is expected to respond with `step1:` (direct translation) and `step2:` (refined).
    static func buildTranslationPrompt(
        text: String,
        from sourceLang: String,
        to targetLang: String,
        domain: Domain? = nil
    ) -> String {
        let detectedDomain = domain ?? detectDomain(text)
        let isToZh = targetLang.hasPrefix("zh")
        let expertHint = expertPrompt(for: detectedDomain, isZh: isToZh)

        let glossary: [GlossaryEntry]
        switch detectedDomain {
        case .technical: glossary = techGlossary
        case .literary:  glossary = literaryGlossary
        case .general:   glossary = []
        }

        var glossaryBlock = ""
        if !glossary.isEmpty {
            let entries = glossary.prefix(20).map { "\($0.source) → \($0.target)" + ($0.note.isEmpty ? "" : " (\($0.note))") }
            glossaryBlock = "\n术语表:\n" + entries.joined(separator: "\n")
        }

        return """
        \(expertHint)\(glossaryBlock)

        请将以下\(sourceLang)文本翻译为\(targetLang)。
        使用两步翻译法：
        step1: 先进行直译，忠实原文
        step2: 在直译基础上反思优化，使之更自然流畅

        原文:
        \(text)
        """
    }

    // MARK: - Response Parsing

    struct TranslationResult {
        let step1: String   // Direct translation
        let step2: String   // Refined translation
        let domain: Domain
    }

    /// Parses the AI response into step1 and step2 translations.
    static func parseResponse(_ response: String, domain: Domain) -> TranslationResult {
        var step1 = ""
        var step2 = ""

        let lines = response.components(separatedBy: "\n")
        var currentStep = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("step1:") {
                step1 = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                currentStep = 1
            } else if trimmed.lowercased().hasPrefix("step2:") {
                step2 = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                currentStep = 2
            } else if !trimmed.isEmpty {
                switch currentStep {
                case 1: step1 += (step1.isEmpty ? "" : "\n") + trimmed
                case 2: step2 += (step2.isEmpty ? "" : "\n") + trimmed
                default: break
                }
            }
        }

        // Fallback: if no step markers found, the whole response is the translation
        if step1.isEmpty && step2.isEmpty {
            step2 = response.trimmingCharacters(in: .whitespacesAndNewlines)
            step1 = step2
        } else if step2.isEmpty {
            step2 = step1
        }

        return TranslationResult(step1: step1, step2: step2, domain: domain)
    }
}
