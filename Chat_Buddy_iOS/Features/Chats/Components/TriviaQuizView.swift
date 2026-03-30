import SwiftUI

private struct TriviaQuestion {
    let id: Int
    let questionEn: String
    let questionZh: String
    let optionsEn: [String]
    let optionsZh: [String]
    let correctIndex: Int

    func question(isZh: Bool) -> String {
        isZh ? questionZh : questionEn
    }

    func options(isZh: Bool) -> [String] {
        isZh ? optionsZh : optionsEn
    }
}

struct TriviaQuizView: View {
    @Environment(LocalizationManager.self) private var localization
    @Environment(SocialService.self) private var social
    @Environment(\.dismiss) private var dismiss

    let onComplete: (_ score: Int, _ total: Int) -> Void

    @State private var index = 0
    @State private var score = 0
    @State private var answered = false
    @State private var selectedIndex: Int? = nil

    private var isZh: Bool { localization.uiLanguage.resolved == .zh }

    private static let questions: [TriviaQuestion] = [
        .init(
            id: 1,
            questionEn: "Which language is primarily used for native iOS development?",
            questionZh: "原生 iOS 开发主要使用哪种语言？",
            optionsEn: ["Swift", "Kotlin", "Rust", "Go"],
            optionsZh: ["Swift", "Kotlin", "Rust", "Go"],
            correctIndex: 0
        ),
        .init(
            id: 2,
            questionEn: "What does MVVM stand for?",
            questionZh: "MVVM 的全称是什么？",
            optionsEn: ["Model View Value Module", "Model View ViewModel", "Main View ViewModel", "Model Virtual View Module"],
            optionsZh: ["Model View Value Module", "Model View ViewModel", "Main View ViewModel", "Model Virtual View Module"],
            correctIndex: 1
        ),
        .init(
            id: 3,
            questionEn: "In SwiftUI, which container is used for stacked vertical layout?",
            questionZh: "在 SwiftUI 中，哪个容器用于垂直排列布局？",
            optionsEn: ["HStack", "VStack", "ZStack", "List"],
            optionsZh: ["HStack", "VStack", "ZStack", "List"],
            correctIndex: 1
        ),
        .init(
            id: 4,
            questionEn: "Which service stores key-value app settings in this project?",
            questionZh: "本项目中用于保存键值设置的是哪个服务？",
            optionsEn: ["CoreDataService", "StorageService", "CloudSyncService", "CacheEngine"],
            optionsZh: ["CoreDataService", "StorageService", "CloudSyncService", "CacheEngine"],
            correctIndex: 1
        ),
        .init(
            id: 5,
            questionEn: "What is the role of an actor in Swift Concurrency?",
            questionZh: "Swift 并发中的 actor 主要作用是什么？",
            optionsEn: ["UI rendering", "Thread-safe state isolation", "JSON parsing", "Network encryption"],
            optionsZh: ["UI 渲染", "线程安全的状态隔离", "JSON 解析", "网络加密"],
            correctIndex: 1
        ),
    ]

    private var current: TriviaQuestion {
        Self.questions[index]
    }

    private var completed: Bool {
        index >= Self.questions.count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: DSSpacing.lg) {
                if completed {
                    completionView
                } else {
                    questionView
                }
                Spacer(minLength: 0)
            }
            .padding(DSSpacing.md)
            .navigationTitle(isZh ? "问答挑战" : "Trivia Quiz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(localization.uiLanguage.resolved == .zh ? "关闭" : "Close") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var questionView: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            HStack {
                Text(isZh ? "第 \(index + 1)/\(Self.questions.count) 题" : "Q \(index + 1)/\(Self.questions.count)")
                    .font(DSTypography.caption1)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(isZh ? "得分：\(score)" : "Score: \(score)")
                    .font(DSTypography.caption1.weight(.semibold))
            }

            Text(current.question(isZh: isZh))
                .font(DSTypography.title3)

            VStack(spacing: DSSpacing.xs) {
                ForEach(Array(current.options(isZh: isZh).enumerated()), id: \.offset) { offset, option in
                    Button {
                        guard !answered else { return }
                        selectedIndex = offset
                        answered = true
                        if offset == current.correctIndex {
                            score += 1
                        }
                    } label: {
                        HStack(spacing: DSSpacing.sm) {
                            Text(option)
                                .font(DSTypography.body)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            if answered {
                                if offset == current.correctIndex {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                } else if selectedIndex == offset {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                        .padding(DSSpacing.sm)
                        .background(backgroundColor(for: offset), in: RoundedRectangle(cornerRadius: DSRadius.md))
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                guard answered else { return }
                moveNext()
            } label: {
                Text(index == Self.questions.count - 1
                     ? (isZh ? "查看结果" : "Show Result")
                     : (isZh ? "下一题" : "Next"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!answered)
        }
    }

    private var completionView: some View {
        VStack(spacing: DSSpacing.md) {
            let total = Self.questions.count
            let pointsEarned = score * 6
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundStyle(.purple)
            Text(isZh ? "挑战完成" : "Quiz Complete")
                .font(DSTypography.title2)
            Text(isZh ? "得分：\(score)/\(total)" : "Score: \(score)/\(total)")
                .font(DSTypography.headline)
                .foregroundStyle(.secondary)
            Text(isZh ? "奖励积分：+\(pointsEarned)" : "Points earned: +\(pointsEarned)")
                .font(DSTypography.subheadline)
                .foregroundStyle(.green)

            Button {
                social.addPoints(pointsEarned)
                social.onGamePlayed()
                onComplete(score, total)
                dismiss()
            } label: {
                Text(isZh ? "完成" : "Done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.top, DSSpacing.xl)
    }

    private func moveNext() {
        if index + 1 < Self.questions.count {
            index += 1
            answered = false
            selectedIndex = nil
        } else {
            index = Self.questions.count
        }
    }

    private func backgroundColor(for optionIndex: Int) -> Color {
        guard answered else { return Color.secondary.opacity(0.08) }
        if optionIndex == current.correctIndex {
            return Color.green.opacity(0.16)
        }
        if selectedIndex == optionIndex {
            return Color.red.opacity(0.14)
        }
        return Color.secondary.opacity(0.06)
    }
}
