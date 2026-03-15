import SwiftUI

struct GiftPanelView: View {
    @Environment(SocialService.self) private var social
    @Environment(AffinityService.self) private var affinity
    @Environment(ChatStore.self) private var chatStore
    @Environment(LocalizationManager.self) private var localization
    @Environment(\.dismiss) private var dismiss

    let sessionId: String
    let persona: Persona

    @State private var selectedGift: GiftDefinition? = nil
    @State private var result: GiftResult? = nil

    private enum GiftResult { case sent(GiftDefinition), noPoints }
    private var isZh: Bool { localization.uiLanguage.resolved == .zh }
    private var currentScore: Int { affinity.score(for: persona.id) }

    var body: some View {
        NavigationStack {
            VStack(spacing: DSSpacing.lg) {
                // Points balance
                HStack {
                    Image(systemName: "star.fill").foregroundStyle(.yellow)
                    Text(isZh ? "我的积分：\(social.points)" : "My Points: \(social.points)")
                        .font(DSTypography.subheadline)
                    Spacer()
                }
                .padding(.horizontal, DSSpacing.md)

                // Intimacy bar
                intimacyBar

                // Gift grid
                giftGrid

                // Result feedback
                if let result {
                    resultBanner(result)
                }

                Spacer()
            }
            .padding(.top, DSSpacing.md)
            .navigationTitle(localization.t("gift_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(localization.t("done")) { dismiss() }
                }
            }
        }
    }

    // MARK: - Intimacy Bar

    private var intimacyBar: some View {
        let level = affinity.level(for: persona.id)
        return HStack(spacing: DSSpacing.sm) {
            Image(systemName: "heart.fill")
                .foregroundStyle(level.color)
            Text(level.localizedLabel(isZh: isZh))
                .font(DSTypography.caption1)
                .foregroundStyle(level.color)
            ProgressView(value: Double(currentScore), total: 100)
                .tint(level.color)
            Text("\(currentScore)/100")
                .font(DSTypography.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, DSSpacing.md)
    }

    // MARK: - Gift Grid

    private var giftGrid: some View {
        let columns = [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
        ]
        return LazyVGrid(columns: columns, spacing: DSSpacing.md) {
            ForEach(GiftDefinition.all) { gift in
                giftCard(gift)
            }
        }
        .padding(.horizontal, DSSpacing.md)
    }

    private func giftCard(_ gift: GiftDefinition) -> some View {
        let canAfford = social.points >= gift.cost
        let isSelected = selectedGift?.id == gift.id

        return Button {
            withAnimation(.spring(response: 0.3)) {
                selectedGift = isSelected ? nil : gift
                result = nil
            }
        } label: {
            VStack(spacing: DSSpacing.xs) {
                Text(gift.emoji)
                    .font(.system(size: 36))
                Text(isZh ? gift.nameZh : gift.name)
                    .font(DSTypography.caption1.weight(.medium))
                HStack(spacing: 2) {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                    Text("\(gift.cost)")
                        .font(DSTypography.caption2)
                }
                .foregroundStyle(canAfford ? .primary : .secondary)
                Text("+\(gift.intimacyBoost) ❤️")
                    .font(DSTypography.caption2)
                    .foregroundStyle(.pink)
            }
            .frame(maxWidth: .infinity)
            .padding(DSSpacing.sm)
            .background(
                isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: DSRadius.lg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.lg)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
            .opacity(canAfford ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!canAfford)
    }

    // MARK: - Send Action

    private func sendGift(_ gift: GiftDefinition) {
        guard social.spendPoints(gift.cost) else {
            withAnimation { result = .noPoints }
            return
        }
        // Boost intimacy
        affinity.addBoost(gift.intimacyBoost, for: persona.id)
        let newScore = affinity.score(for: persona.id)

        // Update social stats
        social.onGiftSent(intimacyAfter: newScore)

        // Send gift message to chat
        let msg = ChatMessage(
            role: .user,
            content: "\(gift.emoji) [\(isZh ? "礼物" : "Gift"): \(isZh ? gift.nameZh : gift.name)] — \(isZh ? "送给你一份小礼物！" : "A little something for you!")"
        )
        chatStore.appendMessage(msg, to: sessionId)

        selectedGift = nil
        withAnimation { result = .sent(gift) }
    }

    // MARK: - Result Banner

    @ViewBuilder
    private func resultBanner(_ r: GiftResult) -> some View {
        switch r {
        case .sent(let gift):
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(isZh ? "已赠送 \(gift.emoji) \(gift.nameZh)！" : "Gift sent! \(gift.emoji)")
                    .font(DSTypography.footnote)
                Spacer()
                Button(isZh ? "关闭" : "Done") { dismiss() }
                    .font(DSTypography.footnote)
            }
            .padding(DSSpacing.md)
            .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: DSRadius.lg))
            .padding(.horizontal, DSSpacing.md)

        case .noPoints:
            HStack {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                Text(localization.t("gift_no_points"))
                    .font(DSTypography.footnote)
            }
            .padding(DSSpacing.md)
            .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: DSRadius.lg))
            .padding(.horizontal, DSSpacing.md)
        }
    }
}
