import SwiftUI

/// Sticker picker overlay — tabs for Recent, Favorites, AI persona-specific, and packs.
struct StickerPickerView: View {
    let personaId: String
    let onSelect: (String) -> Void
    let onDismiss: () -> Void

    @Environment(LocalizationManager.self) private var localization

    @State private var selectedTab = 0
    @State private var stickerService = StickerService()

    private var isZh: Bool { localization.uiLanguage.resolved == .zh }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 6)

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DSSpacing.sm) {
                    tabButton(isZh ? "最近" : "Recent", index: 0)
                    tabButton(isZh ? "收藏" : "Favorites", index: 1)
                    if !stickerService.aiStickers(for: personaId).isEmpty {
                        tabButton("AI", index: 2)
                    }
                    ForEach(Array(StickerService.packs.enumerated()), id: \.element.id) { offset, pack in
                        tabButton(isZh ? pack.nameZh : pack.name, index: 3 + offset)
                    }
                }
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.xs)
            }

            Divider()

            // Content grid
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(currentStickers, id: \.self) { sticker in
                        Button {
                            stickerService.addRecent(sticker)
                            onSelect(sticker)
                        } label: {
                            Text(sticker)
                                .font(.system(size: 28))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                stickerService.toggleFavorite(sticker)
                            } label: {
                                Label(
                                    stickerService.isFavorite(sticker)
                                        ? (isZh ? "取消收藏" : "Unfavorite")
                                        : (isZh ? "收藏" : "Favorite"),
                                    systemImage: stickerService.isFavorite(sticker) ? "star.fill" : "star"
                                )
                            }
                        }
                    }
                }
                .padding(DSSpacing.md)
            }
            .frame(height: 200)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg))
    }

    private var currentStickers: [String] {
        switch selectedTab {
        case 0: return stickerService.recents
        case 1: return stickerService.favorites
        case 2: return stickerService.aiStickers(for: personaId)
        default:
            let packIndex = selectedTab - 3
            guard packIndex >= 0, packIndex < StickerService.packs.count else { return [] }
            return StickerService.packs[packIndex].stickers
        }
    }

    private func tabButton(_ title: String, index: Int) -> some View {
        Button {
            selectedTab = index
        } label: {
            Text(title)
                .font(DSTypography.caption1.weight(selectedTab == index ? .bold : .regular))
                .foregroundStyle(selectedTab == index ? Color.accentColor : .secondary)
                .padding(.horizontal, DSSpacing.sm)
                .padding(.vertical, 4)
                .background(selectedTab == index ? Color.accentColor.opacity(0.12) : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
