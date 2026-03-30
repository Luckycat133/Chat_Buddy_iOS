import SwiftUI

struct IdiomChainView: View {
    @Environment(LocalizationManager.self) private var localization
    @Environment(SocialService.self) private var social
    @Environment(\.dismiss) private var dismiss

    let onComplete: (_ result: String, _ rounds: Int) -> Void

    @State private var input = ""
    @State private var history: [(speaker: String, idiom: String)] = []
    @State private var requiredChar: String = ""
    @State private var statusText: String = ""
    @State private var isGameOver = false

    private let allIdioms: [String] = [
        "一心一意", "意气风发", "发扬光大", "大展宏图", "图文并茂", "茂林修竹", "竹报平安", "安居乐业", "业精于勤", "勤能补拙",
        "拙嘴笨舌", "舌战群儒", "儒雅随和", "和风细雨", "雨过天晴", "晴空万里", "里应外合", "合情合理", "理直气壮", "壮志凌云",
        "云开见日", "日新月异", "异曲同工", "工于心计", "计日程功", "功成名就", "就地取材", "材高八斗", "斗志昂扬", "扬眉吐气",
        "气定神闲", "闲庭信步", "步步高升", "升堂入室", "室如悬磬", "磬竹难书", "书香门第", "第次鳞比", "比翼双飞", "飞黄腾达"
    ]

    private var isZh: Bool { localization.uiLanguage.resolved == .zh }

    var body: some View {
        NavigationStack {
            VStack(spacing: DSSpacing.md) {
                Text(isZh ? "成语接龙" : "Idiom Chain")
                    .font(DSTypography.title2)

                if !isZh {
                    Text("Chinese only game")
                        .font(DSTypography.caption1)
                        .foregroundStyle(.secondary)
                }

                if !requiredChar.isEmpty {
                    Text((isZh ? "请以“\(requiredChar)”开头" : "Start with \(requiredChar)"))
                        .font(DSTypography.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !statusText.isEmpty {
                    Text(statusText)
                        .font(DSTypography.footnote)
                        .foregroundStyle(isGameOver ? .orange : .secondary)
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DSSpacing.xs) {
                        ForEach(Array(history.enumerated()), id: \.offset) { _, item in
                            HStack {
                                Text(item.speaker == "user" ? (isZh ? "你" : "You") : "AI")
                                    .font(DSTypography.caption1.weight(.semibold))
                                    .foregroundStyle(item.speaker == "user" ? Color.accentColor : Color.purple)
                                    .frame(width: 36, alignment: .leading)
                                Text(item.idiom)
                                    .font(DSTypography.body)
                            }
                            .padding(.horizontal, DSSpacing.sm)
                            .padding(.vertical, DSSpacing.xs)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: DSRadius.md))
                        }
                    }
                }
                .frame(maxHeight: 260)

                HStack(spacing: DSSpacing.sm) {
                    TextField(isZh ? "输入四字成语" : "Enter 4-char idiom", text: $input)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isGameOver)
                    Button(isZh ? "提交" : "Play") {
                        submitUserIdiom()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isGameOver)
                }

                HStack(spacing: DSSpacing.sm) {
                    Button(isZh ? "重新开始" : "Restart") {
                        resetGame()
                    }
                    .buttonStyle(.bordered)

                    Button(isZh ? "完成" : "Done") {
                        social.onGamePlayed()
                        onComplete(isGameOver ? "finished" : "manual_exit", history.count / 2)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(DSSpacing.md)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func submitUserIdiom() {
        let idiom = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !idiom.isEmpty else { return }
        guard idiom.count == 4 else {
            statusText = isZh ? "请输入四字成语" : "Please enter a 4-char idiom"
            return
        }
        if !requiredChar.isEmpty && !idiom.hasPrefix(requiredChar) {
            statusText = isZh ? "成语首字需要是“\(requiredChar)”" : "Idiom must start with \(requiredChar)"
            return
        }
        guard allIdioms.contains(idiom) else {
            statusText = isZh ? "词库中未找到该成语" : "Idiom not found in dictionary"
            return
        }
        guard !history.contains(where: { $0.idiom == idiom }) else {
            statusText = isZh ? "该成语已使用" : "This idiom has already been used"
            return
        }

        history.append((speaker: "user", idiom: idiom))
        input = ""

        let lastChar = String(idiom.suffix(1))
        if let aiIdiom = aiReply(startingWith: lastChar) {
            history.append((speaker: "ai", idiom: aiIdiom))
            requiredChar = String(aiIdiom.suffix(1))
            statusText = ""
        } else {
            finishGame(result: isZh ? "你赢了，AI 无法接龙" : "You win, AI cannot continue")
        }
    }

    private func aiReply(startingWith required: String) -> String? {
        let used = Set(history.map { $0.idiom })
        let candidates = allIdioms.filter { $0.hasPrefix(required) && !used.contains($0) }
        return candidates.randomElement()
    }

    private func finishGame(result: String) {
        isGameOver = true
        statusText = result
        social.addPoints(20)
        onComplete("win", history.count / 2)
    }

    private func resetGame() {
        history.removeAll()
        input = ""
        requiredChar = ""
        statusText = ""
        isGameOver = false
    }
}
