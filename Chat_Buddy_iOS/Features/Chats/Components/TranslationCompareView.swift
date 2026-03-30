import SwiftUI

/// Side-by-side translation comparison view with two-step reflective translation.
struct TranslationCompareView: View {
    let sourceText: String
    let onDismiss: () -> Void

    @Environment(LocalizationManager.self) private var localization
    @Environment(APIConfigStore.self) private var apiConfigStore

    @State private var result: TranslationService.TranslationResult?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showStep1 = false

    private var isZh: Bool { localization.uiLanguage.resolved == .zh }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DSSpacing.lg) {
                    // Source
                    sectionCard(title: isZh ? "原文" : "Original", content: sourceText)

                    if isLoading {
                        ProgressView(isZh ? "翻译中…" : "Translating…")
                            .padding()
                    } else if let error = errorMessage {
                        Text(error)
                            .font(DSTypography.caption1)
                            .foregroundStyle(.red)
                            .padding()
                    } else if let result {
                        // Domain badge
                        HStack {
                            Text(isZh ? "领域" : "Domain")
                                .font(DSTypography.caption2)
                                .foregroundStyle(.secondary)
                            Text(domainLabel(result.domain))
                                .font(DSTypography.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
                        }

                        // Step 2: Refined (primary)
                        sectionCard(title: isZh ? "优化翻译" : "Refined", content: result.step2, copyable: true)

                        // Toggle for step 1
                        DisclosureGroup(isZh ? "直译参考" : "Direct Translation", isExpanded: $showStep1) {
                            Text(result.step1)
                                .font(DSTypography.body)
                                .textSelection(.enabled)
                                .padding(.top, DSSpacing.xs)
                        }
                        .font(DSTypography.footnote.weight(.medium))
                        .padding(.horizontal, DSSpacing.md)
                    }
                }
                .padding(DSSpacing.md)
            }
            .navigationTitle(isZh ? "沉浸式翻译" : "Translation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isZh ? "关闭" : "Close") { onDismiss() }
                }
            }
            .task { await translate() }
        }
    }

    private func sectionCard(title: String, content: String, copyable: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack {
                Text(title)
                    .font(DSTypography.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if copyable {
                    Button {
                        UIPasteboard.general.string = content
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(content)
                .font(DSTypography.body)
                .textSelection(.enabled)
        }
        .padding(DSSpacing.md)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DSRadius.md))
    }

    private func domainLabel(_ d: TranslationService.Domain) -> String {
        switch d {
        case .technical: return isZh ? "技术" : "Technical"
        case .literary:  return isZh ? "文学" : "Literary"
        case .general:   return isZh ? "通用" : "General"
        }
    }

    private func translate() async {
        let config = apiConfigStore.activeConfig
        guard config.isValid else {
            errorMessage = isZh ? "请先配置 API" : "Please configure API first"
            return
        }

        isLoading = true
        let domain = TranslationService.detectDomain(sourceText)
        // Detect source/target: if source looks Chinese, translate to English; else to Chinese
        let isSourceZh = sourceText.unicodeScalars.contains { $0.value >= 0x4E00 && $0.value <= 0x9FFF }
        let sourceLang = isSourceZh ? "中文" : "English"
        let targetLang = isSourceZh ? "English" : "中文"

        let prompt = TranslationService.buildTranslationPrompt(
            text: sourceText, from: sourceLang, to: targetLang, domain: domain
        )

        let messages = [
            ChatMessage(role: .system, content: "You are a professional translator."),
            ChatMessage(role: .user, content: prompt),
        ]

        do {
            let response = try await AIClient.shared.sendChatCompletion(messages: messages, config: config)
            if let content = response.choices.first?.message.content {
                result = TranslationService.parseResponse(content, domain: domain)
            } else {
                errorMessage = isZh ? "无翻译结果" : "No translation result"
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
