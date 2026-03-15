import SwiftUI

/// Sheet presenting all bookmarks for the current chat session
struct BookmarksSheet: View {
    @Environment(BookmarkService.self) private var bookmarkService
    @Environment(LocalizationManager.self) private var localization

    let sessionId: String
    let onSelect: (Bookmark) -> Void

    private var sessionBookmarks: [Bookmark] {
        bookmarkService.bookmarks
            .filter { $0.sessionId == sessionId }
            .sorted { $0.bookmarkedAt > $1.bookmarkedAt }
    }

    var body: some View {
        NavigationStack {
            Group {
                if sessionBookmarks.isEmpty {
                    emptyState
                } else {
                    bookmarkList
                }
            }
            .navigationTitle(localization.t("bookmarks"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Bookmark List

    private var bookmarkList: some View {
        List {
            ForEach(sessionBookmarks) { bookmark in
                Button {
                    onSelect(bookmark)
                } label: {
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        Text(bookmark.content)
                            .font(DSTypography.body)
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                        Text(bookmark.bookmarkedAt, style: .relative)
                            .font(DSTypography.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        bookmarkService.removeBookmark(messageId: bookmark.messageId)
                    } label: {
                        Label(localization.t("bookmark_remove"), systemImage: "bookmark.slash")
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DSSpacing.md) {
            Image(systemName: "bookmark")
                .font(.system(size: 44))
                .foregroundStyle(.secondary.opacity(0.5))
            Text(localization.t("bookmarks_empty"))
                .font(DSTypography.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxHeight: .infinity)
    }
}
