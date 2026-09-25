import PhotosUI
import SwiftUI

/// Cloud-backed moments view per skill §"Moments":
///   - Cache-first render with cursor pagination (`loadMore` on scroll).
///   - Real view events after meaningful card display.
///   - Optimistic reactions/comments reconciled against the server.
///   - PhotosPicker compose with compression + upload progress.
///   - Audience indicator on every card (visible audience, no discovery).
///   - AI posts render identically to other familiar contacts; the UI
///     never labels them "generated".
public struct CloudMomentsView: View {
    @StateObject private var viewModel: CloudMomentsViewModel
    @EnvironmentObject private var cloud: CloudAppState
    @Environment(LocalizationManager.self) private var loc

    @State private var pickedItem: PhotosPickerItem?
    @State private var commentTargets: [String: Bool] = [:]
    @State private var commentDrafts: [String: String] = [:]

    public init() {
        _viewModel = StateObject(wrappedValue: CloudMomentsViewModel(app: nil))
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle(loc.t("nav_moments"))
                .refreshable { await viewModel.load() }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        audienceMenu
                    }
                }
                .task {
                    viewModel.bind(app: cloud)
                    await viewModel.load()
                }
        }
    }

    private var audienceMenu: some View {
        Menu {
            Button(loc.t("cloud_moments_audience_public")) {
                viewModel.audienceClass = "public_within_graph"
            }
            Button(loc.t("cloud_moments_audience_familiar")) {
                viewModel.audienceClass = "familiar"
            }
            Button(loc.t("cloud_moments_audience_private")) {
                viewModel.audienceClass = "restricted"
            }
        } label: {
            Image(systemName: AudienceBadge.symbol(forClass: viewModel.audienceClass))
        }
        .accessibilityLabel(loc.t("cloud_moments_compose"))
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            if let error = viewModel.error {
                Label(error, systemImage: "exclamationmark.bubble")
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
            feed
            composer
        }
    }

    private var feed: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if viewModel.moments.isEmpty {
                    emptyState
                }
                ForEach(viewModel.moments) { moment in
                    CloudMomentCard(
                        item: moment,
                        failedPending: viewModel.failedPending(for: moment.id),
                        commentDraft: binding(for: moment.id),
                        onAppearCard: { Task { await viewModel.reportVisible(moment.id) } },
                        onReact: { Task { await viewModel.react(to: moment.id) } },
                        onComment: { text in
                            Task { await viewModel.comment(to: moment.id, content: text) }
                        },
                        onRetryPending: { pending in
                            Task { await viewModel.retryPending(pending) }
                        },
                    )
                }
                if viewModel.canLoadMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .task { await viewModel.loadMore() }
                        .accessibilityLabel(loc.t("cloud_moments_loading_more"))
                }
            }
            .padding()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 36))
            Text(loc.t("cloud_moments_empty"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if let progress = viewModel.uploadProgress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .padding(.horizontal)
                    .accessibilityLabel(loc.t("cloud_moments_uploading"))
            }
            HStack(spacing: 8) {
                PhotosPicker(
                    selection: $pickedItem,
                    matching: .images,
                ) {
                    Image(systemName: "photo")
                }
                .accessibilityLabel(loc.t("cloud_moments_attach_photo"))
                .onChange(of: pickedItem) { _, item in
                    guard let item else { return }
                    Task {
                        if let data = await MediaAttachmentLoader.load(item) {
                            await viewModel.attachMedia(data)
                        }
                        pickedItem = nil
                    }
                }
                TextField(loc.t("cloud_moments_share_hint"), text: $viewModel.composerDraft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                Button {
                    Task { await viewModel.compose() }
                } label: {
                    if viewModel.composing || viewModel.isUploading {
                        ProgressView()
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                }
                .disabled(viewModel.composerDraft.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.composing)
                .accessibilityLabel(loc.t("cloud_moments_post"))
            }
            .padding()
            .background(.thinMaterial)
        }
    }

    private func binding(for momentId: String) -> Binding<String> {
        Binding(
            get: { commentDrafts[momentId] ?? "" },
            set: { commentDrafts[momentId] = $0 },
        )
    }
}

private struct CloudMomentCard: View {
    let item: MomentsRepository.MomentItem
    let failedPending: [MomentPendingInteraction]
    @Binding var commentDraft: String
    let onAppearCard: () -> Void
    let onReact: () -> Void
    let onComment: (String) -> Void
    let onRetryPending: (MomentPendingInteraction) -> Void

    @State private var showingCommentInput = false
    @Environment(LocalizationManager.self) private var loc

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(item.actorName)
                    .font(.headline)
                if !item.isCharacter {
                    Image(systemName: "person.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Spacer()
                // Audience indicator: who can see this post.
                Label(loc.t(AudienceBadge.key(forClass: item.audiencePolicy)),
                      systemImage: AudienceBadge.symbol(forClass: item.audiencePolicy))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(loc.t(AudienceBadge.key(forClass: item.audiencePolicy)))
            }
            Text(item.content)
                .font(.body)
            if !item.comments.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(item.comments) { comment in
                        Text("\(comment.actorName): \(comment.content)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(failedPending) { pending in
                HStack {
                    Label(
                        loc.t("cloud_moments_failed_pending"),
                        systemImage: "exclamationmark.arrow.circlepath",
                    )
                    .font(.caption)
                    .foregroundStyle(.red)
                    Spacer()
                    Button(loc.t("cloud_retry")) { onRetryPending(pending) }
                        .font(.caption.bold())
                }
            }
            HStack(spacing: 16) {
                Button(action: onReact) {
                    Label(loc.t("cloud_moments_like"), systemImage: "hand.thumbsup")
                }
                Button { showingCommentInput.toggle() } label: {
                    Label(loc.t("cloud_moments_comment"), systemImage: "bubble.left")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if showingCommentInput {
                HStack(spacing: 8) {
                    TextField(loc.t("cloud_moments_comment_hint"), text: $commentDraft, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...3)
                        .onSubmit { submitComment() }
                    Button(action: submitComment) {
                        Image(systemName: "paperplane.fill")
                    }
                    .disabled(commentDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel(loc.t("cloud_moments_send_comment"))
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .onAppear(perform: onAppearCard)
    }

    private func submitComment() {
        let text = commentDraft
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        commentDraft = ""
        showingCommentInput = false
        onComment(text)
    }
}

/// Decodes a PhotosPicker item into compressed JPEG bytes. Isolated to a
/// struct so the view stays lean.
private enum MediaAttachmentLoader {
    static func load(_ item: PhotosPickerItem) async -> Data? {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        return await MainActor.run { MediaUploadService.compress(image) }
        #else
        return data
        #endif
    }
}
