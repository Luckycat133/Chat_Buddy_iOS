import SwiftUI
import SwiftData

/// Contacts tab per skill §"Contacts and requests":
///
///   - Five surfaces: inbound requests, outbound requests, accepted
///     (human friends / AI friends), declined, blocked.
///   - AI request decisions arrive asynchronously through sync: pending
///     rows show a waiting state and outcomes appear on refresh — the
///     client never decides or predicts an AI's answer.
///   - Delete ≠ block ≠ account deletion, explained in plain language.
///   - Entry point for the group creation wizard.
public struct ContactsView: View {
    @EnvironmentObject private var app: CloudAppState
    @Environment(LocalizationManager.self) private var loc
    @State private var projection = ContactsProjection(
        inbound: [], outbound: [], acceptedHumans: [], acceptedCharacters: [],
        declined: [], blocked: [], groups: [],
    )
    @State private var isLoading = false
    @State private var error: String?
    @State private var showGroupWizard = false
    @State private var deletionTarget: ContactsProjection.Entry?
    @State private var showAccountDeleteHint = false

    public init() {}

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle(loc.t("nav_contacts"))
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showGroupWizard = true
                        } label: {
                            Image(systemName: "person.crop.circle.badge.plus")
                        }
                        .accessibilityLabel(loc.t("cloud_contacts_new_group_a11y"))
                    }
                }
                .refreshable { await refresh() }
                .task { await refresh() }
                .sheet(isPresented: $showGroupWizard) {
                    GroupCreationWizardView()
                }
                .sheet(item: $deletionTarget) { entry in
                    ContactActionSheet(entry: entry) { action in
                        Task {
                            await perform(action: action, for: entry)
                            await refresh()
                        }
                    } onSaveRemark: { remark in
                        Task {
                            try? await app.contacts.setPrivateRemark(
                                relationshipId: entry.id,
                                remark: remark,
                            )
                            await refresh()
                        }
                    } onExplainAccountDeletion: {
                        showAccountDeleteHint = true
                    }
                    .presentationDetents([.medium])
                }
                .alert(
                    loc.t("cloud_contacts_account_delete_hint_title"),
                    isPresented: $showAccountDeleteHint,
                ) {
                    Button(loc.t("cloud_ok"), role: .cancel) {}
                } message: {
                    Text(loc.t("cloud_contacts_account_delete_hint_body"))
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let error, projectionIsEmpty {
            errorState
        } else if projectionIsEmpty {
            emptyState
        } else {
            List {
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.bubble")
                            .foregroundStyle(.red)
                    }
                }
                if !projection.inbound.isEmpty {
                    Section(loc.t("cloud_contacts_requests_inbound")) {
                        ForEach(projection.inbound) { entry in
                            RequestRow(entry: entry, isInbound: true) { accept in
                                Task {
                                    await decide(entry: entry, accept: accept)
                                    await refresh()
                                }
                            }
                        }
                    }
                }
                if !projection.outbound.isEmpty {
                    Section(loc.t("cloud_contacts_requests_outbound")) {
                        ForEach(projection.outbound) { entry in
                            OutboundRow(entry: entry)
                        }
                    }
                }
                if !projection.acceptedHumans.isEmpty {
                    Section(loc.t("cloud_contacts_friends_human")) {
                        ForEach(projection.acceptedHumans) { entry in
                            ContactRow(entry: entry) {
                                deletionTarget = entry
                            }
                        }
                    }
                }
                if !projection.acceptedCharacters.isEmpty {
                    Section(loc.t("cloud_contacts_friends_ai")) {
                        ForEach(projection.acceptedCharacters) { entry in
                            ContactRow(entry: entry) {
                                deletionTarget = entry
                            }
                        }
                    }
                }
                if !projection.groups.isEmpty {
                    Section(loc.t("cloud_contacts_groups")) {
                        ForEach(projection.groups) { group in
                            NavigationLink(value: group.id) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.name.isEmpty ? loc.t("cloud_contacts_group_unnamed") : group.name)
                                        .font(.headline)
                                    Text(loc.t("cloud_contacts_group_members", params: [
                                        "count": "\(group.memberCount)",
                                    ]))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                    .navigationDestination(for: String.self) { conversationId in
                        CloudChatView(conversationId: conversationId)
                    }
                }
                if !projection.declined.isEmpty {
                    Section(loc.t("cloud_contacts_declined")) {
                        ForEach(projection.declined) { entry in
                            DeclinedRow(entry: entry)
                        }
                    }
                }
                if !projection.blocked.isEmpty {
                    Section(loc.t("cloud_contacts_blocked")) {
                        ForEach(projection.blocked) { entry in
                            BlockedRow(entry: entry) {
                                Task {
                                    await perform(action: .unblock, for: entry)
                                    await refresh()
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var projectionIsEmpty: Bool {
        projection.inbound.isEmpty && projection.outbound.isEmpty
            && projection.acceptedHumans.isEmpty && projection.acceptedCharacters.isEmpty
            && projection.groups.isEmpty && projection.declined.isEmpty
            && projection.blocked.isEmpty
    }

    private var errorState: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
            Text(error).multilineTextAlignment(.center)
            Button(loc.t("cloud_retry")) { Task { await refresh() } }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.circle")
                .font(.system(size: 36))
            Text(loc.t("cloud_contacts_empty"))
                .foregroundStyle(.secondary)
            Text(loc.t("cloud_contacts_empty_hint"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    // MARK: Actions

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        guard let myActorId = await app.auth.currentActorId() else {
            error = NSLocalizedString("cloud_contacts_missing_actor", comment: "")
            return
        }
        do {
            try await app.contacts.refresh(myActorId: myActorId)
            projection = await app.contacts.cachedProjection(myActorId: myActorId)
            error = nil
        } catch {
            // Keep cached contacts visible, but never report a failed
            // server pull as a successful refresh.
            projection = await app.contacts.cachedProjection(myActorId: myActorId)
            self.error = String(describing: error)
        }
    }

    private func decide(entry: ContactsProjection.Entry, accept: Bool) async {
        do {
            _ = try await app.contacts.decide(requestId: entry.id, accept: accept)
            error = nil
        } catch {
            self.error = String(describing: error)
        }
    }

    private func perform(action: ContactsRepository.RelationshipAction, for entry: ContactsProjection.Entry) async {
        do {
            try await app.contacts.mutateRelationship(relationshipId: entry.id, action: action)
            error = nil
        } catch {
            self.error = String(describing: error)
        }
    }
}

// MARK: - Rows

private struct RequestRow: View {
    let entry: ContactsProjection.Entry
    let isInbound: Bool
    let onDecide: (Bool) -> Void
    @Environment(LocalizationManager.self) private var loc

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.actorName).font(.headline)
                if let note = entry.note, !note.isEmpty {
                    Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
            if isInbound {
                Button(loc.t("cloud_contacts_accept")) { onDecide(true) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button(loc.t("cloud_contacts_decline")) { onDecide(false) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var avatar: some View {
        Circle()
            .fill(.quaternary)
            .frame(width: 40, height: 40)
            .overlay(Text(String(entry.actorName.prefix(1))).font(.headline).foregroundStyle(.secondary))
            .accessibilityHidden(true)
    }
}

private struct OutboundRow: View {
    let entry: ContactsProjection.Entry
    @Environment(LocalizationManager.self) private var loc

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.actorName).font(.headline)
                // AI decisions arrive asynchronously — waiting state only.
                Text(loc.t("cloud_contacts_waiting_response"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel(loc.t("cloud_contacts_waiting_response"))
        }
        .accessibilityElement(children: .combine)
    }

    private var avatar: some View {
        Circle()
            .fill(.quaternary)
            .frame(width: 40, height: 40)
            .overlay(Text(String(entry.actorName.prefix(1))).font(.headline).foregroundStyle(.secondary))
            .accessibilityHidden(true)
    }
}

private struct ContactRow: View {
    let entry: ContactsProjection.Entry
    let onManage: () -> Void
    @Environment(LocalizationManager.self) private var loc

    var body: some View {
        Button(action: onManage) {
            HStack(spacing: 12) {
                avatar
                Text(entry.actorName).font(.headline).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(loc.t("cloud_contacts_manage_hint"))
    }

    private var avatar: some View {
        Circle()
            .fill(.quaternary)
            .frame(width: 40, height: 40)
            .overlay(Text(String(entry.actorName.prefix(1))).font(.headline).foregroundStyle(.secondary))
            .accessibilityHidden(true)
    }
}

private struct DeclinedRow: View {
    let entry: ContactsProjection.Entry
    @Environment(LocalizationManager.self) private var loc

    var body: some View {
        HStack(spacing: 12) {
            avatar
            Text(entry.actorName).font(.headline).foregroundStyle(.secondary)
            Spacer()
            Text(loc.t("cloud_contacts_declined_badge"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var avatar: some View {
        Circle()
            .fill(.quaternary)
            .frame(width: 40, height: 40)
            .overlay(Text(String(entry.actorName.prefix(1))).font(.headline).foregroundStyle(.secondary))
            .accessibilityHidden(true)
    }
}

private struct BlockedRow: View {
    let entry: ContactsProjection.Entry
    let onUnblock: () -> Void
    @Environment(LocalizationManager.self) private var loc

    var body: some View {
        HStack(spacing: 12) {
            avatar
            Text(entry.actorName).font(.headline).foregroundStyle(.secondary)
            Spacer()
            Button(loc.t("cloud_contacts_unblock"), action: onUnblock)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .accessibilityElement(children: .combine)
    }

    private var avatar: some View {
        Circle()
            .fill(.quaternary)
            .frame(width: 40, height: 40)
            .overlay(Text(String(entry.actorName.prefix(1))).font(.headline).foregroundStyle(.secondary))
            .accessibilityHidden(true)
    }
}

/// Delete vs block vs account deletion explainer, per skill §12:
/// plain language, no technical jargon.
struct ContactActionSheet: View {
    let entry: ContactsProjection.Entry
    let onAction: (ContactsRepository.RelationshipAction) -> Void
    let onSaveRemark: (String) -> Void
    let onExplainAccountDeletion: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(LocalizationManager.self) private var loc
    @State private var showDeleteConfirm = false
    @State private var remarkDraft = ""
    @State private var remarkSaved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(loc.t("cloud_contacts_manage_title", params: ["name": entry.actorName]))
                .font(.headline)
            Button {
                showDeleteConfirm = true
            } label: {
                actionRow(
                    icon: "person.badge.minus",
                    title: loc.t("cloud_contacts_action_delete"),
                    detail: loc.t("cloud_contacts_action_delete_detail"),
                    role: nil,
                )
            }
            Button {
                onAction(.block)
                dismiss()
            } label: {
                actionRow(
                    icon: "hand.raised",
                    title: loc.t("cloud_contacts_action_block"),
                    detail: loc.t("cloud_contacts_action_block_detail"),
                    role: .destructive,
                )
            }
            Button {
                onExplainAccountDeletion()
                dismiss()
            } label: {
                actionRow(
                    icon: "questionmark.circle",
                    title: loc.t("cloud_contacts_action_account_hint"),
                    detail: loc.t("cloud_contacts_action_account_hint_detail"),
                    role: nil,
                )
            }
            // Private remark: visible only to me; the public identity
            // is fixed per settled product decision 12.
            HStack(spacing: 8) {
                TextField(loc.t("cloud_contacts_remark_placeholder"), text: $remarkDraft)
                    .textFieldStyle(.roundedBorder)
                Button {
                    onSaveRemark(remarkDraft)
                    remarkSaved = true
                } label: {
                    Image(systemName: remarkSaved ? "checkmark" : "square.and.pencil")
                }
                .disabled(remarkDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel(loc.t("cloud_contacts_remark_save_a11y"))
            }
            Spacer()
            Button(loc.t("cloud_cancel")) { dismiss() }
                .frame(maxWidth: .infinity)
        }
        .padding()
        .confirmationDialog(
            loc.t("cloud_contacts_delete_confirm_title"),
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible,
        ) {
            Button(loc.t("cloud_contacts_delete_confirm_action"), role: .destructive) {
                onAction(.delete)
                dismiss()
            }
            Button(loc.t("cloud_cancel"), role: .cancel) {}
        } message: {
            Text(loc.t("cloud_contacts_delete_confirm_body"))
        }
    }

    private func actionRow(icon: String, title: String, detail: String, role: ButtonRole?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(role == .destructive ? Color.red : Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(role == .destructive ? Color.red : Color.primary)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
