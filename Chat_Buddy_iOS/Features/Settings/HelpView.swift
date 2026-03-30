import SwiftUI

/// Help & FAQ page with expandable accordion items and quick tips.
struct HelpView: View {
    @Environment(LocalizationManager.self) private var localization

    @State private var expandedId: String?

    private var isZh: Bool { localization.uiLanguage.resolved == .zh }

    private struct FAQItem: Identifiable {
        let id: String
        let question: String
        let questionZh: String
        let answer: String
        let answerZh: String
    }

    private let faqs: [FAQItem] = [
        FAQItem(
            id: "faq1",
            question: "How do I configure the API?",
            questionZh: "如何配置 API？",
            answer: "Go to Settings → API Configuration. Enter your API key, base URL, and select your preferred model. Chat Buddy supports OpenAI, DeepSeek, and any OpenAI-compatible endpoint.",
            answerZh: "前往 设置 → API 配置。输入你的 API Key、Base URL，并选择模型。Chat Buddy 支持 OpenAI、DeepSeek 以及任何 OpenAI 兼容的端点。"
        ),
        FAQItem(
            id: "faq2",
            question: "How do I switch languages?",
            questionZh: "如何切换语言？",
            answer: "Go to Settings → Language. You can set the UI language and AI response language independently. The app supports English and Simplified Chinese.",
            answerZh: "前往 设置 → 语言。你可以分别设置界面语言和 AI 回复语言。应用支持英文和简体中文。"
        ),
        FAQItem(
            id: "faq3",
            question: "What are personas and how do they work?",
            questionZh: "什么是角色，它们如何运作？",
            answer: "Personas are AI companions with unique personalities, speaking styles, and interests. Each persona responds differently based on their character traits, current mood, and your relationship level.",
            answerZh: "角色是具有独特个性、说话风格和兴趣的 AI 伙伴。每个角色会根据其性格特征、当前心情和你的亲密度做出不同回应。"
        ),
        FAQItem(
            id: "faq4",
            question: "How does the affinity system work?",
            questionZh: "亲密度系统如何运作？",
            answer: "Chatting with a persona increases your affinity level (1–5). Higher levels unlock warmer interactions, different speaking styles, and new features. Affinity increases naturally through conversation.",
            answerZh: "与角色聊天会提升亲密度等级（1-5）。更高等级会解锁更温暖的互动、不同的说话风格和新功能。亲密度通过日常对话自然提升。"
        ),
        FAQItem(
            id: "faq5",
            question: "How do I export/import my data?",
            questionZh: "如何导出/导入数据？",
            answer: "Go to Settings → Data → Export/Import. You can export all your chat history, settings, and persona data as a JSON file, and import it on another device.",
            answerZh: "前往 设置 → 数据 → 导出/导入。你可以将所有聊天记录、设置和角色数据导出为 JSON 文件，并在其他设备上导入。"
        ),
    ]

    private struct TipItem: Identifiable {
        let id: String
        let icon: String
        let text: String
        let textZh: String
    }

    private let tips: [TipItem] = [
        TipItem(id: "tip1", icon: "lightbulb.fill", text: "Long-press a message to bookmark, quote, or forward it.", textZh: "长按消息可以收藏、引用或转发。"),
        TipItem(id: "tip2", icon: "star.fill", text: "Star your favorite personas in the Friends tab for quick access.", textZh: "在好友页面标星你最喜欢的角色，方便快速访问。"),
        TipItem(id: "tip3", icon: "moon.fill", text: "Enable OLED dark mode in Appearance settings for true black backgrounds.", textZh: "在外观设置中启用 OLED 深色模式，获得纯黑背景体验。"),
    ]

    var body: some View {
        List {
            Section(isZh ? "常见问题" : "FAQ") {
                ForEach(faqs) { faq in
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { expandedId == faq.id },
                            set: { expandedId = $0 ? faq.id : nil }
                        )
                    ) {
                        Text(isZh ? faq.answerZh : faq.answer)
                            .font(DSTypography.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, DSSpacing.xs)
                    } label: {
                        Text(isZh ? faq.questionZh : faq.question)
                            .font(DSTypography.body.weight(.medium))
                    }
                }
            }

            Section(isZh ? "小贴士" : "Quick Tips") {
                ForEach(tips) { tip in
                    HStack(spacing: DSSpacing.sm) {
                        Image(systemName: tip.icon)
                            .foregroundStyle(.orange)
                            .frame(width: 24)
                        Text(isZh ? tip.textZh : tip.text)
                            .font(DSTypography.footnote)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section(isZh ? "版本信息" : "Version") {
                HStack {
                    Text("Chat Buddy iOS")
                        .font(DSTypography.footnote)
                    Spacer()
                    Text(AppConstants.appVersion)
                        .font(DSTypography.caption1)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(isZh ? "帮助" : "Help")
        .navigationBarTitleDisplayMode(.inline)
    }
}
