import SwiftUI
import SwiftData

/// Me tab per skill §"Root navigation / Me tab" + §"Data export and
/// deletion": account/devices, export, one-time legacy import, blocked
/// actors, diagnostics, sign out, and account deletion with explicit
/// destructive confirmation.
struct MeTabView: View {
    @ObservedObject var cloud: CloudAppState
    @Environment(LocalizationManager.self) private var loc

    @State private var accountId: String?
    @State private var showDeleteAccount = false

    var body: some View {
        NavigationStack {
            List {
                Section(loc.t("cloud_me_account")) {
                    if let accountId {
                        LabeledContent(
                            loc.t("cloud_me_account_id"),
                            value: String(accountId.prefix(8)) + "…",
                        )
                    }
                    NavigationLink(loc.t("cloud_me_blocked")) {
                        BlockedActorsView()
                    }
                }
                Section(loc.t("cloud_me_data")) {
                    NavigationLink(loc.t("cloud_me_export")) {
                        AccountExportView()
                    }
                    NavigationLink(loc.t("cloud_me_legacy_import")) {
                        LegacyImportView()
                    }
                    Button(role: .destructive) {
                        showDeleteAccount = true
                    } label: {
                        Text(loc.t("cloud_me_delete_account"))
                    }
                }
                Section(loc.t("cloud_me_diagnostics")) {
                    NavigationLink(loc.t("cloud_me_diagnostics_detail")) {
                        DiagnosticsView(cloud: cloud)
                    }
                    Button(loc.t("cloud_me_sign_out"), role: .destructive) {
                        Task { await cloud.signOut() }
                    }
                }
            }
            .navigationTitle(loc.t("nav_settings"))
            .task { accountId = await cloud.auth.currentAccountId() }
            .sheet(isPresented: $showDeleteAccount) {
                DeleteAccountFlow(cloud: cloud)
            }
        }
    }
}

// MARK: - Export

struct AccountExportView: View {
    @EnvironmentObject private var cloud: CloudAppState
    @Environment(LocalizationManager.self) private var loc

    @State private var isWorking = false
    @State private var exportData: Data?
    @State private var error: String?
    @State private var showShare = false

    var body: some View {
        List {
            Section(footer: Text(loc.t("cloud_export_footer"))) {
                Button {
                    Task { await run() }
                } label: {
                    if isWorking {
                        ProgressView()
                    } else {
                        Text(loc.t("cloud_export_action"))
                    }
                }
                .disabled(isWorking)
            }
            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle(loc.t("cloud_me_export"))
        .sheet(isPresented: $showShare) {
            if let exportData {
                ShareSheet(items: [exportData])
            }
        }
    }

    private func run() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let service = AccountService(http: cloud.http)
            let manifest = try await service.requestExport()
            var data = Data()
            if let url = manifest.downloadUrl {
                data = try await service.downloadExport(url: url)
            }
            exportData = data
            showShare = !data.isEmpty
            error = data.isEmpty ? loc.t("cloud_export_empty") : nil
        } catch {
            self.error = String(describing: error)
        }
    }
}

/// UIKit share sheet bridge (no SwiftUI-native file share in this base).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Legacy import

struct LegacyImportView: View {
    @EnvironmentObject private var cloud: CloudAppState
    @Environment(LocalizationManager.self) private var loc

    @State private var snapshot: LegacyImporter.LegacySnapshot?
    @State private var isImporting = false
    @State private var resultMessage: String?
    @State private var error: String?
    @State private var confirmErase = false

    var body: some View {
        List {
            Section(footer: Text(loc.t("cloud_import_footer"))) {
                if let snapshot {
                    LabeledContent(loc.t("cloud_import_conversations"), value: "\(snapshot.conversations)")
                    LabeledContent(loc.t("cloud_import_moments"), value: "\(snapshot.moments)")
                    LabeledContent(loc.t("cloud_import_memories"), value: "\(snapshot.memories)")
                    LabeledContent(loc.t("cloud_import_contacts"), value: "\(snapshot.contacts)")
                } else {
                    Text(loc.t("cloud_import_nothing"))
                        .foregroundStyle(.secondary)
                }
            }
            Section(footer: Text(loc.t("cloud_import_credentials_note"))) {
                Button {
                    Task { await importNow() }
                } label: {
                    if isImporting {
                        ProgressView()
                    } else {
                        Text(loc.t("cloud_import_action"))
                    }
                }
                .disabled(isImporting || snapshot == nil || !(cloud.legacyImporter.hasLegacyData))
                Button(role: .destructive) {
                    confirmErase = true
                } label: {
                    Text(loc.t("cloud_import_skip_erase"))
                }
                .disabled(!(cloud.legacyImporter.hasLegacyData))
            }
            if let resultMessage {
                Section { Text(resultMessage).foregroundStyle(.green) }
            }
            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle(loc.t("cloud_me_legacy_import"))
        .onAppear { snapshot = cloud.legacyImporter.snapshot() }
        .confirmationDialog(
            loc.t("cloud_import_erase_confirm_title"),
            isPresented: $confirmErase,
            titleVisibility: .visible,
        ) {
            Button(loc.t("cloud_import_erase_confirm_action"), role: .destructive) {
                cloud.legacyImporter.eraseLegacyKeys()
                snapshot = cloud.legacyImporter.snapshot()
                resultMessage = loc.t("cloud_import_erased")
            }
            Button(loc.t("cloud_cancel"), role: .cancel) {}
        } message: {
            Text(loc.t("cloud_import_erase_confirm_body"))
        }
    }

    private func importNow() async {
        isImporting = true
        defer { isImporting = false }
        let batch = cloud.legacyImporter.buildImportBatch()
        guard !batch.isEmpty else {
            error = loc.t("cloud_import_empty_batch")
            return
        }
        do {
            let service = AccountService(http: cloud.http)
            let result = try await service.importLegacyBatch(batch)
            if result.accepted {
                // One-time contract: mark complete only after success.
                cloud.legacyImporter.eraseLegacyKeys()
                snapshot = cloud.legacyImporter.snapshot()
                resultMessage = loc.t("cloud_import_success")
                error = nil
            } else {
                error = result.summary ?? loc.t("cloud_import_rejected")
            }
        } catch {
            self.error = String(describing: error)
        }
    }
}

// MARK: - Blocked actors

struct BlockedActorsView: View {
    @EnvironmentObject private var cloud: CloudAppState
    @Environment(LocalizationManager.self) private var loc
    @State private var blocked: [ContactsProjection.Entry] = []

    var body: some View {
        List {
            if blocked.isEmpty {
                Text(loc.t("cloud_blocked_empty"))
                    .foregroundStyle(.secondary)
            }
            ForEach(blocked) { entry in
                HStack {
                    Text(entry.actorName)
                    Spacer()
                    Button(loc.t("cloud_contacts_unblock")) {
                        Task {
                            try? await cloud.contacts.mutateRelationship(
                                relationshipId: entry.id,
                                action: .unblock,
                            )
                            await reload()
                        }
                    }
                    .controlSize(.small)
                }
            }
        }
        .navigationTitle(loc.t("cloud_me_blocked"))
        .task { await reload() }
    }

    private func reload() async {
        guard let myActorId = await cloud.auth.currentActorId() else { return }
        let projection = await cloud.contacts.cachedProjection(myActorId: myActorId)
        blocked = projection.blocked
    }
}

// MARK: - Delete account

/// Two-step destructive confirmation per skill §17, then server delete +
/// Keychain clear + SwiftData destroy + push unregister (in
/// `CloudAppState.deleteAccount`).
struct DeleteAccountFlow: View {
    @ObservedObject var cloud: CloudAppState
    @Environment(\.dismiss) private var dismiss
    @Environment(LocalizationManager.self) private var loc

    @State private var confirmationText = ""
    @State private var isDeleting = false
    @State private var error: String?

    private let requiredPhrase = "DELETE"

    var body: some View {
        NavigationStack {
            Form {
                Section(loc.t("cloud_delete_what_happens")) {
                    Text(loc.t("cloud_delete_body_history"))
                    Text(loc.t("cloud_delete_body_block"))
                    Text(loc.t("cloud_delete_body_account"))
                }
                Section(footer: Text(loc.t("cloud_delete_typing_footer"))) {
                    TextField(loc.t("cloud_delete_typing_placeholder"), text: $confirmationText)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                Section {
                    Button(role: .destructive) {
                        Task { await deleteNow() }
                    } label: {
                        if isDeleting {
                            ProgressView()
                        } else {
                            Text(loc.t("cloud_delete_confirm_action"))
                        }
                    }
                    .disabled(confirmationText != requiredPhrase || isDeleting)
                }
            }
            .navigationTitle(loc.t("cloud_me_delete_account"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(loc.t("cloud_cancel")) { dismiss() }
                }
            }
        }
    }

    private func deleteNow() async {
        isDeleting = true
        defer { isDeleting = false }
        await cloud.deleteAccount()
        dismiss()
    }
}
