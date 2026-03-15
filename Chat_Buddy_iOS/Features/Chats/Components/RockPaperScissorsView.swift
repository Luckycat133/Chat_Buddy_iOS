import SwiftUI

struct RockPaperScissorsView: View {
    @Environment(SocialService.self) private var social
    @Environment(LocalizationManager.self) private var localization
    @Environment(\.dismiss) private var dismiss

    private enum Choice: String, CaseIterable {
        case rock = "✊", paper = "✋", scissors = "✌️"
        var beats: Choice { switch self { case .rock: .scissors; case .scissors: .paper; case .paper: .rock } }
    }
    private enum Outcome { case win, lose, draw }

    @State private var playerScore = 0
    @State private var aiScore = 0
    @State private var round = 0
    @State private var playerChoice: Choice? = nil
    @State private var aiChoice: Choice? = nil
    @State private var outcome: Outcome? = nil
    @State private var countdown = 0
    @State private var isCountingDown = false

    private var isZh: Bool { localization.uiLanguage.resolved == .zh }
    private let winPoints = 10

    var body: some View {
        NavigationStack {
            VStack(spacing: DSSpacing.xl) {
                // Scoreboard
                scoreBoard

                // Arena
                arena

                // Choices
                if outcome == nil && !isCountingDown {
                    choiceRow
                } else if let outcome {
                    resultView(outcome)
                } else {
                    countdownView
                }

                Spacer()
            }
            .padding(DSSpacing.lg)
            .navigationTitle(isZh ? "石头剪刀布" : "Rock Paper Scissors")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(localization.t("done")) {
                        social.onGamePlayed()
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Score Board

    private var scoreBoard: some View {
        HStack {
            scoreCell(value: playerScore, label: isZh ? "你" : "You")
            Text(":")
                .font(DSTypography.title2)
                .foregroundStyle(.secondary)
            scoreCell(value: aiScore, label: isZh ? "AI" : "AI")
        }
        .padding(DSSpacing.md)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DSRadius.xl))
    }

    private func scoreCell(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 42, weight: .bold, design: .rounded))
            Text(label).font(DSTypography.caption1).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Arena

    private var arena: some View {
        HStack(spacing: DSSpacing.xl) {
            Text(playerChoice?.rawValue ?? "❓")
                .font(.system(size: 56))
            Image(systemName: "arrow.left.arrow.right")
                .foregroundStyle(.secondary)
            Text(aiChoice?.rawValue ?? "❓")
                .font(.system(size: 56))
        }
        .frame(maxWidth: .infinity)
        .padding(DSSpacing.xl)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DSRadius.xl))
    }

    // MARK: - Choice Row

    private var choiceRow: some View {
        VStack(spacing: DSSpacing.sm) {
            Text(isZh ? "选择你的出招" : "Make your choice")
                .font(DSTypography.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: DSSpacing.lg) {
                ForEach(Choice.allCases, id: \.self) { choice in
                    Button {
                        playerChoice = choice
                        startCountdown()
                    } label: {
                        Text(choice.rawValue)
                            .font(.system(size: 44))
                            .frame(width: 70, height: 70)
                            .background(Color.secondary.opacity(0.1), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Countdown

    private var countdownView: some View {
        Text("\(countdown)")
            .font(.system(size: 64, weight: .bold, design: .rounded))
            .foregroundStyle(Color.accentColor)
            .transition(.scale.combined(with: .opacity))
            .id(countdown)
    }

    // MARK: - Result

    private func resultView(_ o: Outcome) -> some View {
        VStack(spacing: DSSpacing.md) {
            switch o {
            case .win:
                Text("🎉 \(isZh ? "你赢了！+\(winPoints)积分" : "You win! +\(winPoints) pts")")
                    .foregroundStyle(.green)
            case .lose:
                Text("😔 \(isZh ? "AI赢了！" : "AI wins!")")
                    .foregroundStyle(.red)
            case .draw:
                Text("🤝 \(isZh ? "平局！" : "Draw!")")
                    .foregroundStyle(.orange)
            }
            HStack(spacing: DSSpacing.md) {
                Button(isZh ? "再来一局" : "Play Again") {
                    withAnimation { reset() }
                }
                .buttonStyle(.bordered)

                Button(isZh ? "结束" : "Finish") {
                    social.onGamePlayed()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .font(DSTypography.headline)
    }

    // MARK: - Logic

    private func startCountdown() {
        countdown = 3
        isCountingDown = true
        countTick()
    }

    private func countTick() {
        if countdown == 0 {
            isCountingDown = false
            resolveRound()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            withAnimation { countdown -= 1 }
            countTick()
        }
    }

    private func resolveRound() {
        let ai = Choice.allCases.randomElement()!
        aiChoice = ai
        round += 1

        guard let player = playerChoice else { return }
        let result: Outcome
        if player == ai            { result = .draw }
        else if player.beats == ai { result = .win }
        else                       { result = .lose }

        withAnimation {
            if result == .win { playerScore += 1; social.addPoints(winPoints) }
            if result == .lose { aiScore += 1 }
            outcome = result
        }
    }

    private func reset() {
        playerChoice = nil
        aiChoice = nil
        outcome = nil
        countdown = 0
        isCountingDown = false
    }
}
