import SwiftUI

/// Half-height sheet showing all comments on a moment post with reply & delete support.
/// Reads live data from MomentsStore by postId so comments update in real time.
struct CommentsView: View {
    let postId: String
    @Environment(MomentsStore.self) private var store
    @Environment(LocalizationManager.self) private var localization

    @State private var replyToComment: MomentComment? = nil
    @State private var inputText: String = ""
    @FocusState private var inputFocused: Bool

    private var post: MomentPost? { store.posts.first { $0.id == postId } }
    private var comments: [MomentComment] { post?.comments ?? [] }

    private func authorName(for id: String) -> String {
        if id == "user-me" { return "You" }
        return PersonaStore.persona(byId: id)?.name ?? id
    }

    private func authorColor(for id: String) -> Color {
        if id == "user-me" { return .blue }
        return PersonaStore.persona(byId: id)?.accentColor ?? .secondary
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if comments.isEmpty {
                    Spacer()
                    Text(localization.t("moments_no_comments"))
                        .foregroundStyle(.tertiary)
                        .font(.subheadline)
                    Spacer()
                } else {
                    List(comments) { comment in
                        commentRow(comment)
                            .swipeActions(edge: .trailing) {
                                if comment.authorId == "user-me" {
                                    Button(role: .destructive) {
                                        store.deleteComment(postId: postId, commentId: comment.id)
                                    } label: {
                                        Label(localization.t("moments_delete_comment"), systemImage: "trash")
                                    }
                                }
                            }
                    }
                    .listStyle(.plain)
                }

                Divider()

                // Reply indicator
                if let reply = replyToComment {
                    HStack {
                        Text(localization.t("moments_reply_to", params: ["name": authorName(for: reply.authorId)]))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            replyToComment = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, DSSpacing.md)
                    .padding(.vertical, DSSpacing.xs)
                    .background(.ultraThinMaterial)
                }

                // Input bar
                HStack(spacing: DSSpacing.sm) {
                    TextField(localization.t("moments_add_comment"), text: $inputText, axis: .vertical)
                        .focused($inputFocused)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .padding(.horizontal, DSSpacing.sm)
                        .padding(.vertical, DSSpacing.xs)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DSRadius.lg))

                    Button {
                        submitComment()
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 17))
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.sm)
                .background(.ultraThinMaterial)
            }
            .navigationTitle(localization.t("moments_comments") + " (\(comments.count))")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Comment Row

    private func commentRow(_ comment: MomentComment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                commentText(comment)
                    .font(.system(size: 14))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(comment.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            replyToComment = comment
            inputFocused = true
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func commentText(_ comment: MomentComment) -> some View {
        let aId = comment.authorId
        let name = authorName(for: aId)
        let color = authorColor(for: aId)

        VStack(alignment: .leading, spacing: 1) {
            if let reply = comment.replyTo {
                Text("\(name) → \(reply.authorName):")
                    .fontWeight(.semibold)
                    .foregroundStyle(color)
            } else {
                Text("\(name):")
                    .fontWeight(.semibold)
                    .foregroundStyle(color)
            }
            Text(comment.content)
        }
    }

    // MARK: - Submit

    private func submitComment() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let ref = replyToComment.map { r in
            MomentComment.ReplyReference(
                commentId: r.id,
                authorId: r.authorId,
                authorName: authorName(for: r.authorId)
            )
        }

        store.addComment(postId: postId, content: trimmed, authorId: "user-me", replyTo: ref)
        inputText = ""
        replyToComment = nil
    }
}
