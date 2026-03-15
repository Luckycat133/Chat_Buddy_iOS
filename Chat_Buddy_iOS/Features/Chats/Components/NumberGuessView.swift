import SwiftUI

struct NumberGuessView: View {
    @Environment(SocialService.self) private var social
    @Environment(LocalizationManager.self) private var localization
    @Environment(\.dismiss) private var dismiss

    private let maxAttempts = 7
    private let winPoints = 30
    private let secretNumber = Int.random(in: 1...100)

    @State private var guessText = ""
    @State private var attempts: [Int] = []
    @State private var feedback: Feedback? = nil
    @State private var isWon = false
    @State private var isLost = false
    @FocusState private var isFocused: Bool

    private enum Feedback { case tooHigh, tooLow, correct }
    private var isZh: Bool { localization.uiLanguage.resolved == .zh }
    private var attemptsLeft: Int { maxAttempts - attempts.count }

    var body: some View {
        NavigationStack {
            VStack(spacing: DSSpacing.lg) {
                // Attempts indicator
                attemptsRow

                // Hint / result message
                feedbackLabel

                // Guess history
                if !attempts.isEmpty {
                    historyRow
                }

                Spacer()

                // Input
                if !isWon && !isLost {
                    inputRow
                } else {
                    endButtons
                }
            }
            .padding(DSSpacing.lg)
            .navigationTitle(isZh ? "猜数字 (1–100)" : "Number Guess (1–100)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(localization.t("done")) {
                        social.onGamePlayed()
                        dismiss()
                    }
                }
            }
            .onAppear { isFocused = true }
        }
    }

    // MARK: - Attempts Indicator

    private var attemptsRow: some View {
        HStack(spacing: DSSpacing.xs) {
            ForEach(0..<maxAttempts, id: \.self) { i in
                Circle()
                    .fill(i < attempts.count ? Color.accentColor : Color.secondary.opacity(0.15))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Group {
                            if i < attempts.count {
                                Text("\(attempts[i])")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                    )
            }
        }
        .padding(DSSpacing.md)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DSRadius.xl))
    }

    // MARK: - Feedback

    private var feedbackLabel: some View {
        VStack(spacing: DSSpacing.xs) {
            if isWon {
                Text("🎉 \(isZh ? "猜对了！+\(winPoints)积分" : "Correct! +\(winPoints) pts")")
                    .foregroundStyle(.green)
            } else if isLost {
                Text("😔 \(isZh ? "答案是\(secretNumber)" : "Answer: \(secretNumber)")")
                    .foregroundStyle(.red)
            } else if let fb = feedback {
                switch fb {
                case .tooHigh: Text("⬇️ \(isZh ? "太大了！" : "Too high!")").foregroundStyle(.orange)
                case .tooLow:  Text("⬆️ \(isZh ? "太小了！" : "Too low!")").foregroundStyle(.blue)
                case .correct: EmptyView()
                }
            } else {
                Text(isZh ? "猜一个1到100之间的数字" : "Guess a number from 1 to 100")
                    .foregroundStyle(.secondary)
            }
            if !isWon && !isLost {
                Text(isZh ? "剩余 \(attemptsLeft) 次机会" : "\(attemptsLeft) tries left")
                    .font(DSTypography.caption1)
                    .foregroundStyle(.tertiary)
            }
        }
        .font(DSTypography.headline)
        .multilineTextAlignment(.center)
    }

    // MARK: - History

    private var historyRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.xs) {
                ForEach(attempts, id: \.self) { n in
                    Text("\(n)")
                        .font(DSTypography.caption1)
                        .padding(.horizontal, DSSpacing.sm)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }
        }
    }

    // MARK: - Input

    private var inputRow: some View {
        HStack(spacing: DSSpacing.md) {
            TextField(isZh ? "输入数字" : "Enter number", text: $guessText)
                .keyboardType(.numberPad)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .focused($isFocused)
                .padding(DSSpacing.md)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DSRadius.lg))
                .frame(maxWidth: 140)

            Button {
                submitGuess()
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.accentColor)
            }
            .disabled(guessText.isEmpty)
        }
    }

    // MARK: - End Buttons

    private var endButtons: some View {
        HStack(spacing: DSSpacing.md) {
            Button(isZh ? "再玩一次" : "Play Again") {
                // Restart by dismissing — caller creates a new view
                social.onGamePlayed()
                dismiss()
            }
            .buttonStyle(.bordered)

            Button(isZh ? "结束" : "Finish") {
                social.onGamePlayed()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Logic

    private func submitGuess() {
        guard let n = Int(guessText), (1...100).contains(n) else { return }
        guessText = ""
        isFocused = true
        withAnimation {
            attempts.append(n)
            if n == secretNumber {
                feedback = .correct
                isWon = true
                social.addPoints(winPoints)
            } else if attempts.count >= maxAttempts {
                isLost = true
            } else if n > secretNumber {
                feedback = .tooHigh
            } else {
                feedback = .tooLow
            }
        }
    }
}
