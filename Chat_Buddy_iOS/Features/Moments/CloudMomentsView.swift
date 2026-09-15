import SwiftUI

/// Cloud-backed moments view per skill §"Moments":
///   - Cache-first render with cursor pagination.
///   - Compose uploads via signed URL (server returns a media manifest).
///   - Reactions/comments optimistic then reconcile.
///   - AI posts render identically to other familiar contacts; the
///     server returns the public name; the UI never labels them
///     "generated" per skill §"Native UX defaults".
public struct CloudMomentsView: View {
    @StateObject private var viewModel: CloudMomentsViewModel
    @EnvironmentObject private var cloud: CloudAppState

    public init() {
        _viewModel = StateObject(wrappedValue: CloudMomentsViewModel(app: nil))
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Moments")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Public") { composeWith(visibility: "public_within_graph") }
                            Button("Friends only") { composeWith(visibility: "familiar") }
                            Button("Private") { composeWith(visibility: "restricted") }
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .accessibilityLabel("Compose moment")
                    }
                }
                .task {
                    viewModel.bind(app: cloud)
                    await viewModel.load()
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if let error = viewModel.error {
                        Label(error, systemImage: "exclamationmark.bubble")
                            .foregroundStyle(.red)
                    }
                    ForEach(viewModel.moments, id: \.id) { moment in
                        CloudMomentCard(
                            item: moment,
                            onReact: { kind in
                                Task { await viewModel.react(to: moment.id, kind: kind) }
                            },
                            onComment: { text in
                                Task { await viewModel.comment(to: moment.id, content: text) }
                            },
                        )
                    }
                }
                .padding()
            }
            composer
        }
    }

    /// Composer input bound to `viewModel.composerDraft`. Without this
    /// binding the compose flow could never receive text.
    @ViewBuilder
    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Share a moment…", text: $viewModel.composerDraft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .disabled(viewModel.composing)
            Button {
                composeWith(visibility: "familiar")
            } label: {
                if viewModel.composing {
                    ProgressView()
                } else {
                    Image(systemName: "paperplane.fill")
                }
            }
            .disabled(viewModel.composerDraft.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.composing)
            .accessibilityLabel("Post moment")
        }
        .padding()
        .background(.thinMaterial)
    }

    private func composeWith(visibility: String) {
        Task { await viewModel.compose(visibilityClass: visibility) }
    }
}

private struct CloudMomentCard: View {
    let item: MomentsRepository.MomentItem
    let onReact: (String) -> Void
    let onComment: (String) -> Void

    @State private var commentDraft = ""
    @State private var showingCommentInput = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.content)
                .font(.body)
            HStack(spacing: 16) {
                Button { onReact("reaction") } label: {
                    Label("Like", systemImage: "hand.thumbsup")
                }
                Button { showingCommentInput.toggle() } label: {
                    Label("Comment", systemImage: "bubble.left")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if showingCommentInput {
                HStack(spacing: 8) {
                    TextField("Write a comment…", text: $commentDraft, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...3)
                    Button {
                        let text = commentDraft
                        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        commentDraft = ""
                        showingCommentInput = false
                        onComment(text)
                    } label: {
                        Image(systemName: "paperplane.fill")
                    }
                    .disabled(commentDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Send comment")
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }
}