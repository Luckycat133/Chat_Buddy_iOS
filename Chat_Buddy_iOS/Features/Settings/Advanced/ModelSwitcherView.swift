import SwiftUI

private struct ModelPreset: Identifiable {
    let id: String
    let provider: String
    let inputPrice: Double?
    let outputPrice: Double?

    static let all: [ModelPreset] = [
        .init(id: "deepseek-chat", provider: "DeepSeek", inputPrice: 0.14, outputPrice: 0.28),
        .init(id: "deepseek-reasoner", provider: "DeepSeek", inputPrice: 0.55, outputPrice: 2.19),
        .init(id: "gpt-4o-mini", provider: "OpenAI", inputPrice: 0.15, outputPrice: 0.60),
        .init(id: "gpt-4o", provider: "OpenAI", inputPrice: 2.50, outputPrice: 10.00),
        .init(id: "claude-3-5-sonnet-20241022", provider: "Anthropic", inputPrice: 3.00, outputPrice: 15.00),
        .init(id: "gemini-2.0-flash", provider: "Google", inputPrice: nil, outputPrice: nil),
        .init(id: "custom", provider: "Custom", inputPrice: nil, outputPrice: nil),
    ]
}

struct ModelSwitcherView: View {
    @Environment(APIConfigStore.self) private var configStore
    @Environment(ChatStore.self) private var chatStore
    @Environment(LocalizationManager.self) private var localization

    @State private var selectedModel = ""
    @State private var customModel = ""
    @State private var saved = false

    private var isZh: Bool { localization.uiLanguage.resolved == .zh }

    private var approxInputTokens: Int {
        chatStore.sessions
            .flatMap { $0.displayMessages }
            .reduce(0) { $0 + max(1, $1.content.count / 3) }
    }

    private var approxOutputTokens: Int {
        Int(Double(approxInputTokens) * 0.7)
    }

    var body: some View {
        List {
            Section(isZh ? "模型选择" : "Model") {
                ForEach(ModelPreset.all) { preset in
                    Button {
                        selectedModel = preset.id
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.id)
                                    .font(DSTypography.footnote.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(preset.provider)
                                    .font(DSTypography.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedModel == preset.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                if selectedModel == "custom" {
                    TextField(isZh ? "输入自定义模型名" : "Enter custom model id", text: $customModel)
                }
            }

            Section(isZh ? "估算 Token 使用" : "Estimated Token Usage") {
                usageRow(label: isZh ? "输入" : "Input", value: approxInputTokens)
                usageRow(label: isZh ? "输出" : "Output", value: approxOutputTokens)

                if let selectedPreset = ModelPreset.all.first(where: { $0.id == selectedModel }),
                   let inPrice = selectedPreset.inputPrice,
                   let outPrice = selectedPreset.outputPrice {
                    let cost = (Double(approxInputTokens) / 1_000_000.0) * inPrice
                        + (Double(approxOutputTokens) / 1_000_000.0) * outPrice
                    Text((isZh ? "预估成本" : "Estimated Cost") + String(format: ": $%.4f", cost))
                        .font(DSTypography.caption1)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button(isZh ? "保存并应用" : "Save & Apply") {
                    let model = selectedModel == "custom"
                        ? customModel.trimmingCharacters(in: .whitespacesAndNewlines)
                        : selectedModel
                    guard !model.isEmpty else { return }
                    configStore.activeConfig.model = model
                    saved = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        saved = false
                    }
                }
                .disabled(selectedModel.isEmpty || (selectedModel == "custom" && customModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))

                if saved {
                    Text(isZh ? "已保存" : "Saved")
                        .font(DSTypography.caption1)
                        .foregroundStyle(.green)
                }
            }
        }
        .navigationTitle(isZh ? "模型切换" : "Model Switcher")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let current = configStore.activeConfig.model
            if ModelPreset.all.contains(where: { $0.id == current }) {
                selectedModel = current
            } else {
                selectedModel = "custom"
                customModel = current
            }
        }
    }

    private func usageRow(label: String, value: Int) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(formatNumber(value))
                .foregroundStyle(.secondary)
        }
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.2fM", Double(n) / 1_000_000)
        }
        if n >= 1_000 {
            return String(format: "%.1fK", Double(n) / 1_000)
        }
        return "\(n)"
    }
}
