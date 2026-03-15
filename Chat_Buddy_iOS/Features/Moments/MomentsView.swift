import SwiftUI

/// Thin Identifiable wrapper so a String can drive `.sheet(item:)`.
private struct PostID: Identifiable {
    let id: String
}

/// Main Moments tab — WeChat-style social feed.
struct MomentsView: View {
    @Environment(MomentsStore.self) private var store
    @Environment(APIConfigStore.self) private var configStore
    @Environment(LocalizationManager.self) private var localization

    @State private var showComposer = false
    @State private var selectedPostId: PostID? = nil
    @State private var repostPostId: PostID? = nil
    @State private var activeHashtag: String? = nil
    @State private var visibleCount = 10

    private var filteredPosts: [MomentPost] {
        guard let tag = activeHashtag else { return store.posts }
        return store.posts.filter { $0.content.localizedCaseInsensitiveContains("#\(tag)") }
    }

    private var visiblePosts: [MomentPost] {
        Array(filteredPosts.prefix(visibleCount))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: DSSpacing.md) {
                    quickComposeRow

                    if let tag = activeHashtag {
                        hashtagFilter(tag)
                    }

                    if filteredPosts.isEmpty {
                        emptyState
                    } else {
                        ForEach(visiblePosts) { post in
                            MomentCardView(
                                post: post,
                                onHashtagTap: { tag in activeHashtag = tag },
                                onComment: { selectedPostId = PostID(id: post.id) },
                                onRepost: { repostPostId = PostID(id: post.id) },
                                onDelete: { store.deletePost(id: post.id) }
                            )
                        }

                        if filteredPosts.count > visibleCount {
                            Button {
                                visibleCount += 10
                            } label: {
                                Text(localization.t("moments_load_more"))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, DSSpacing.sm)
                            }
                        }
                    }
                }
                .padding(.horizontal, DSSpacing.md)
                .padding(.top, DSSpacing.sm)
                .padding(.bottom, DSSpacing.xl)
            }
            .navigationTitle("朋友圈")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showComposer = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .sheet(isPresented: $showComposer) {
                PostComposerView(isPresented: $showComposer) { text, imageData, location in
                    let postId = store.createPost(
                        content: text,
                        imageData: imageData,
                        location: location,
                        authorId: "user-me"
                    )
                    Task {
                        await MomentsOrchestrator.reactToUserPost(
                            postId: postId,
                            store: store,
                            configStore: configStore
                        )
                    }
                }
            }
            .sheet(item: $selectedPostId) { item in
                CommentsView(postId: item.id)
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $repostPostId) { item in
                RepostSheet(
                    postId: item.id,
                    isPresented: Binding(
                        get: { repostPostId != nil },
                        set: { if !$0 { repostPostId = nil } }
                    )
                )
                .presentationDetents([.medium])
            }
            .task {
                await MomentsOrchestrator.run(store: store, configStore: configStore)
            }
        }
    }

    // MARK: - Quick Compose Row

    private var quickComposeRow: some View {
        Button {
            showComposer = true
        } label: {
            HStack(spacing: DSSpacing.sm) {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.blue)
                    )
                Text(localization.t("moments_whats_new"))
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 15))
                Spacer()
                Image(systemName: "photo.badge.plus")
                    .foregroundStyle(.secondary)
            }
            .padding(DSSpacing.sm)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DSRadius.lg))
            .overlay(RoundedRectangle(cornerRadius: DSRadius.lg).strokeBorder(.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Hashtag Filter Banner

    private func hashtagFilter(_ tag: String) -> some View {
        HStack {
            Text("#\(tag)")
                .font(.subheadline.bold())
                .foregroundStyle(.blue)
            Spacer()
            Button {
                activeHashtag = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, DSSpacing.xs)
        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: DSRadius.md))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DSSpacing.md) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text(localization.t("moments_no_posts"))
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(localization.t("moments_be_first"))
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}
