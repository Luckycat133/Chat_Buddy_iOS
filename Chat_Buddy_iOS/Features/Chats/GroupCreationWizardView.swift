import SwiftUI
import SwiftData

/// Group creation wizard per skill §"Group creation and invitation
/// confirmation". Six steps:
///
///   1. optional name/purpose
///   2. select actors
///   3. review invited list
///   4. send proposal
///   5. pending decisions (each human/AI invitee confirms independently)
///   6. open group when created/active
///
/// Status copy is natural ("Mira accepted", "Max is considering") and
/// never exposes model decision metadata. The client makes no AI
/// decisions — outcomes arrive through sync/realtime.
struct GroupCreationWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: CloudAppState
    @Environment(LocalizationManager.self) private var loc

    @State private var state = GroupWizardState()
    @State private var candidates: [ActorBrief] = []
    @State private var invitations: [ConversationRepository.InvitationRow] = []
    @State private var conversation: CachedConversationSnapshot?
    @State private var loadError: String?
    @State private var isSending = false

    var body: some View {
        NavigationStack {
            Group {
                switch state.step {
                case .name: nameStep
                case .select: selectStep
                case .review: reviewStep
                case .send: sendStep
                case .pending: pendingStep
                case .open: openStep
                }
            }
            .navigationTitle(loc.t("cloud_group_wizard_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(loc.t("cloud_cancel")) { dismiss() }
                }
            }
            .task { await loadCandidates() }
        }
    }

    // MARK: Step 1 — name/purpose (optional)

    private var nameStep: some View {
        Form {
            Section(footer: Text(loc.t("cloud_group_name_footer"))) {
                TextField(loc.t("cloud_group_name_placeholder"), text: $state.name)
                TextField(loc.t("cloud_group_purpose_placeholder"), text: $state.purpose, axis: .vertical)
                    .lineLimit(2...4)
            }
        }
        .safeAreaInset(edge: .bottom) { wizardFooter(canProceed: true) }
    }

    // MARK: Step 2 — select actors

    private var selectStep: some View {
        Form {
            Section(footer: Text(loc.t("cloud_group_select_footer"))) {
                if candidates.isEmpty {
                    Text(loc.t("cloud_group_no_candidates"))
                        .foregroundStyle(.secondary)
                }
                ForEach(candidates, id: \.publicName) { candidate in
                    Button {
                        toggle(candidate)
                    } label: {
                        HStack {
                            Text(candidate.publicName)
                                .foregroundStyle(.primary)
                            if candidate.isCharacter {
                                Text(loc.t("cloud_contacts_friends_ai_short"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if state.selectedActorIds.contains(candidate.publicName) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .accessibilityAddTraits(
                        state.selectedActorIds.contains(candidate.publicName) ? [.isSelected] : [],
                    )
                }
            }
        }
        .safeAreaInset(edge: .bottom) { wizardFooter(canProceed: !state.selectedActorIds.isEmpty) }
    }

    // MARK: Step 3 — review invited list

    private var reviewStep: some View {
        Form {
            Section(loc.t("cloud_group_review_name")) {
                Text(state.name.isEmpty ? loc.t("cloud_contacts_group_unnamed") : state.name)
            }
            Section(loc.t("cloud_group_review_members")) {
                ForEach(sortedSelectedNames, id: \.self) { name in
                    Text(name)
                }
            }
            Section {
                Text(loc.t("cloud_group_review_confirm_note"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .safeAreaInset(edge: .bottom) { wizardFooter(canProceed: true) }
    }

    // MARK: Step 4 — send proposal

    private var sendStep: some View {
        Form {
            Section {
                Text(loc.t("cloud_group_send_explainer"))
                    .font(.body)
            }
            if let loadError {
                Section { Text(loadError).foregroundStyle(.red) }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if isSending { ProgressView() }
                wizardFooter(canProceed: !isSending, proceedLabel: loc.t("cloud_group_send_proposal"))
            }
        }
    }

    // MARK: Step 5 — pending decisions

    private var pendingStep: some View {
        List {
            Section(footer: Text(loc.t("cloud_group_pending_footer"))) {
                if invitations.isEmpty {
                    Text(loc.t("cloud_group_pending_none"))
                        .foregroundStyle(.secondary)
                }
                ForEach(invitations) { invite in
                    HStack {
                        Text(invite.inviteeName)
                        Spacer()
                        Text(loc.t(InvitationStatusCopy.key(forStatus: invite.status)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .refreshable { await pollInvitations() }
        .task { await pollInvitations() }
        .safeAreaInset(edge: .bottom) { wizardFooter(canProceed: conversation?.status == "active") }
    }

    // MARK: Step 6 — open group

    private var openStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text(loc.t("cloud_group_open_title"))
                .font(.headline)
            Text(loc.t("cloud_group_open_body"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(loc.t("cloud_group_open_action")) { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(loc.t("cloud_done")) { dismiss() }
            }
        }
    }

    // MARK: Helpers

    private var sortedSelectedNames: [String] {
        state.selectedActorIds.sorted()
    }

    private func toggle(_ candidate: ActorBrief) {
        let key = candidate.publicName
        if state.selectedActorIds.contains(key) {
            state.selectedActorIds.remove(key)
        } else {
            state.selectedActorIds.insert(key)
        }
    }

    private func wizardFooter(canProceed: Bool, proceedLabel: String? = nil) -> some View {
        HStack {
            if state.step != .name {
                Button(loc.t("cloud_back")) { state = state.back() }
                    .buttonStyle(.bordered)
            }
            Spacer()
            Button(proceedLabel ?? loc.t("cloud_next")) {
                Task { await proceed() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canProceed)
        }
        .padding()
        .background(.thinMaterial)
    }

    private func proceed() async {
        switch state.step {
        case .name, .select:
            state = state.next()
        case .review:
            state = state.next()
        case .send:
            await sendProposal()
        case .pending:
            if let conversation, conversation.status == "active" {
                state = state.next()
            }
        case .open:
            break
        }
    }

    private func loadCandidates() async {
        do {
            let actors = try await app.actors.listActors()
            candidates = actors
                .filter { $0.type == "character" || $0.type == "human" }
                .map { ActorBrief(publicName: $0.publicName, isCharacter: $0.type == "character") }
        } catch {
            // Cache fallback keeps the wizard usable offline.
            let context = ModelContext(app.container)
            let cached = (try? context.fetch(FetchDescriptor<CachedActor>(sortBy: [SortDescriptor(\.publicName)]))) ?? []
            candidates = cached.map {
                ActorBrief(publicName: $0.publicName, isCharacter: $0.type == "character")
            }
            if cached.isEmpty { loadError = String(describing: error) }
        }
    }

    private func sendProposal() async {
        isSending = true
        defer { isSending = false }
        do {
            let result = try await app.conversations.createGroup(
                name: state.name.isEmpty ? nil : state.name,
                purpose: state.purpose.isEmpty ? nil : state.purpose,
            )
            // Invite each selected actor; every invitee confirms.
            let selected = candidates.filter { state.selectedActorIds.contains($0.publicName) }
            // Resolve actor ids from names via the cache (candidates carry
            // display names only; the invitation API needs actor ids).
            let context = ModelContext(app.container)
            let cached = (try? context.fetch(FetchDescriptor<CachedActor>())) ?? []
            let idByName = Dictionary(uniqueKeysWithValues: cached.map { ($0.publicName, $0.id) })
            for candidate in selected {
                guard let actorId = idByName[candidate.publicName] else { continue }
                _ = try await app.conversations.invite(
                    conversationId: result.conversationId,
                    inviteeActorId: actorId,
                )
            }
            state.sentConversationId = result.conversationId
            loadError = nil
            state.step = .pending
            await pollInvitations()
        } catch {
            loadError = String(describing: error)
        }
    }

    private func pollInvitations() async {
        guard let conversationId = state.sentConversationId else { return }
        // Delta sync brings authoritative invitation decisions; the wizard
        // never invents outcomes.
        if let accountId = await app.auth.currentAccountId() {
            try? await app.sync.runSync(accountId: accountId)
        }
        invitations = await app.conversations.cachedInvitations(conversationId: conversationId)
        conversation = await app.conversations.cachedConversation(id: conversationId)
        if conversation?.status == "active" {
            state.step = .open
        }
    }
}
