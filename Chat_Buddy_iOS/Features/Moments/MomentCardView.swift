import SwiftUI

/// Single post card in the Moments feed.
struct MomentCardView: View {
    let post: MomentPost
    let onHashtagTap: (String) -> Void
    let onComment: () -> Void
    let onRepost: () -> Void
    let onDelete: () -> Void

    @Environment(MomentsStore.self) private var store
    @Environment(LocalizationManager.self) private var localization

    private var isMe: Bool { post.authorId == "user-me" }
    private var persona: Persona? { PersonaStore.persona(byId: post.authorId) }
    private var accentColor: Color { persona?.accentColor ?? .blue }
    private var authorName: String {
        isMe ? "You" : (persona?.name ?? post.authorId)
    }
    private var myLiked: Bool { post.likes.contains("user-me") }
    private var visibleComments: [MomentComment] { Array(post.comments.suffix(3)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            contentText
            if !post.imagePaths.isEmpty { photoGrid }
            if let loc = post.location { locationBadge(loc) }
            if !post.likes.isEmpty { likesStrip }
            if !post.reactions.isEmpty { reactionRow }
            actionRow
            if !post.comments.isEmpty { commentsPreview }
        }
        .padding(DSSpacing.md)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DSRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: DSRadius.lg).strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .contextMenu {
            if isMe {
                Button(role: .destructive) { onDelete() } label: {
                    Label(localization.t("moments_delete_post"), systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: DSSpacing.sm) {
            avatarCircle
            VStack(alignment: .leading, spacing: 1) {
                Text(authorName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accentColor)
                Text(post.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }

    private var avatarCircle: some View {
        Circle()
            .fill(accentColor.opacity(0.18))
            .frame(width: 38, height: 38)
            .overlay(Circle().strokeBorder(accentColor.opacity(0.3), lineWidth: 1))
            .overlay(
                Text(String(authorName.prefix(1)))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(accentColor)
            )
    }

    // MARK: - Content

    private var contentText: some View {
        ParsedTextView(text: post.content, onHashtagTap: onHashtagTap)
            .font(.system(size: 15))
    }

    // MARK: - Photo Grid

    private var photoGrid: some View {
        let paths = Array(post.imagePaths.prefix(4))
        return Group {
            if paths.count == 1 {
                singlePhoto(paths[0])
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 3) {
                    ForEach(paths, id: \.self) { path in
                        gridPhoto(path)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.sm))
    }

    private func singlePhoto(_ filename: String) -> some View {
        let url = store.imageURL(for: filename)
        return Group {
            if let data = try? Data(contentsOf: url),
               let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: 220)
                    .clipped()
            } else {
                Color.gray.opacity(0.2).frame(height: 160)
            }
        }
    }

    private func gridPhoto(_ filename: String) -> some View {
        let url = store.imageURL(for: filename)
        return Group {
            if let data = try? Data(contentsOf: url),
               let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: 110)
                    .clipped()
            } else {
                Color.gray.opacity(0.2).frame(height: 110)
            }
        }
    }

    // MARK: - Location

    private func locationBadge(_ loc: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "location.fill")
            Text(loc)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    // MARK: - Likes

    private var likesStrip: some View {
        let names: [String] = post.likes.prefix(3).compactMap { uid in
            if uid == "user-me" { return "You" }
            return PersonaStore.persona(byId: uid)?.name
        }
        let extra = post.likes.count - min(3, post.likes.count)
        var label = "❤️ " + names.joined(separator: ", ")
        if extra > 0 { label += " +\(extra)" }
        return Text(label)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    // MARK: - Reactions

    private var reactionRow: some View {
        HStack(spacing: 6) {
            ForEach(MomentsService.reactionEmojis, id: \.self) { emoji in
                let users = post.reactions[emoji] ?? []
                if !users.isEmpty {
                    Button {
                        store.addReaction(postId: post.id, emoji: emoji)
                    } label: {
                        Text("\(emoji) \(users.count)")
                            .font(.caption)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background((users.contains("user-me") ? accentColor : Color.secondary).opacity(0.15),
                                        in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Action Row

    private var actionRow: some View {
        HStack(spacing: DSSpacing.lg) {
            // Like
            Button {
                store.toggleLike(postId: post.id)
            } label: {
                Label(myLiked ? localization.t("moments_liked") : localization.t("moments_like"),
                      systemImage: myLiked ? "heart.fill" : "heart")
                    .font(.caption)
                    .foregroundStyle(myLiked ? .pink : .secondary)
            }
            .buttonStyle(.plain)

            // Reaction picker
            reactionPickerMenu

            // Comment
            Button {
                onComment()
            } label: {
                Label(localization.t("moments_comment"), systemImage: "bubble.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            // Repost
            Button {
                onRepost()
            } label: {
                Label(localization.t("moments_share_to_chat"), systemImage: "arrowshape.turn.up.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 2)
    }

    private var reactionPickerMenu: some View {
        Menu {
            ForEach(MomentsService.reactionEmojis, id: \.self) { emoji in
                Button {
                    store.addReaction(postId: post.id, emoji: emoji)
                } label: {
                    Text(emoji)
                }
            }
        } label: {
            Label(localization.t("moments_reactions"), systemImage: "face.smiling")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Comments Preview

    private var commentsPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider().opacity(0.5)
            ForEach(visibleComments) { comment in
                commentRow(comment)
            }
            if post.comments.count > 3 {
                Button {
                    onComment()
                } label: {
                    Text(localization.t("moments_view_all", params: ["n": "\(post.comments.count)"]))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func commentRow(_ comment: MomentComment) -> some View {
        let aId = comment.authorId
        let aName = aId == "user-me" ? "You" : (PersonaStore.persona(byId: aId)?.name ?? aId)
        let aColor = aId == "user-me" ? Color.blue : (PersonaStore.persona(byId: aId)?.accentColor ?? .secondary)

        return VStack(alignment: .leading, spacing: 1) {
            if let reply = comment.replyTo {
                Text("\(aName) → \(reply.authorName):")
                    .fontWeight(.semibold)
                    .foregroundStyle(aColor)
            } else {
                Text("\(aName):")
                    .fontWeight(.semibold)
                    .foregroundStyle(aColor)
            }
            Text(comment.content)
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Parsed Text with Tappable Hashtags

/// Renders post content as plain text, with tappable hashtag pills below.
struct ParsedTextView: View {
    let text: String
    let onHashtagTap: (String) -> Void

    private var hashtags: [String] {
        text.components(separatedBy: .whitespaces)
            .filter { $0.hasPrefix("#") && $0.count > 1 }
            .map { String($0.dropFirst()).trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
            if !hashtags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(hashtags, id: \.self) { tag in
                        Button("#\(tag)") {
                            onHashtagTap(tag)
                        }
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
