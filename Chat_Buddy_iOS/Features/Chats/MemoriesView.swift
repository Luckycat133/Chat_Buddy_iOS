import SwiftUI

/// Sheet displaying the AI's remembered facts about the user for a given persona.
struct MemoriesView: View {
    @Environment(MemoryService.self) private var memoryService
    @Environment(LocalizationManager.self) private var localization

    let personaId: String

    @State private var showAddForm = false
    @State private var showClearAlert = false

    // Add form fields
    @State private var newFact = ""
    @State private var newCategory: MemoryCategory = .fact
    @State private var newImportance: Int = 5

    private var isZh: Bool { localization.uiLanguage.resolved == .zh }
    private var memories: [CharacterMemory] { memoryService.memories(for: personaId) }

    var body: some View {
        NavigationStack {
            Group {
                if memories.isEmpty && !showAddForm {
                    emptyState
                } else {
                    memoriesList
                }
            }
            .navigationTitle(localization.t("memories_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(localization.t("memories_add")) {
                        withAnimation { showAddForm.toggle() }
                    }
                }
                if !memories.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) {
                            showClearAlert = true
                        } label: {
                            Text(localization.t("memories_clear"))
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .alert(localization.t("memories_clear_confirm"), isPresented: $showClearAlert) {
                Button(role: .destructive) {
                    memoryService.forgetAll(for: personaId)
                } label: {
                    Text(localization.t("memories_clear"))
                }
                Button(role: .cancel) {} label: {
                    Text(localization.t("cancel"))
                }
            } message: {
                Text(localization.t("memories_clear_message"))
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DSSpacing.md) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(localization.t("memories_empty"))
                .font(DSTypography.headline)
            Text(localization.t("memories_empty_desc"))
                .font(DSTypography.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DSSpacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Memories List

    private var memoriesList: some View {
        List {
            if showAddForm {
                addFormSection
            }
            ForEach(memories) { memory in
                memoryRow(memory)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            memoryService.forgetMemory(id: memory.id, personaId: personaId)
                        } label: {
                            Label(localization.t("memories_delete"), systemImage: "brain.head.profile")
                        }
                    }
            }
        }
        .listStyle(.insetGrouped)
        .animation(.default, value: memories.count)
    }

    // MARK: - Add Form

    private var addFormSection: some View {
        Section {
            TextField(localization.t("memories_add"), text: $newFact, axis: .vertical)
                .font(DSTypography.body)
                .lineLimit(3...6)

            Picker(isZh ? "分类" : "Category", selection: $newCategory) {
                ForEach(MemoryCategory.allCases, id: \.self) { cat in
                    Text(isZh ? cat.labelZh : cat.label).tag(cat)
                }
            }

            Stepper(
                value: $newImportance,
                in: 1...10,
                step: 1
            ) {
                HStack {
                    Text(isZh ? "重要性" : "Importance")
                    Spacer()
                    Text("\(newCategory.importanceLabel(newImportance)) \(newImportance)/10")
                        .foregroundStyle(.secondary)
                }
            }

            Button(localization.t("memories_add")) {
                let fact = newFact.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !fact.isEmpty else { return }
                memoryService.addMemory(
                    personaId: personaId,
                    fact: fact,
                    category: newCategory,
                    importance: newImportance
                )
                newFact = ""
                newCategory = .fact
                newImportance = 5
                withAnimation { showAddForm = false }
            }
            .disabled(newFact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } header: {
            Text(localization.t("memories_add"))
        }
    }

    // MARK: - Memory Row

    private func memoryRow(_ memory: CharacterMemory) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            HStack(spacing: DSSpacing.xs) {
                // Category badge
                Text(isZh ? memory.category.labelZh : memory.category.label)
                    .font(DSTypography.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, DSSpacing.xs)
                    .padding(.vertical, 2)
                    .background(memory.category.color, in: Capsule())

                // Importance emoji
                Text(memory.category.importanceLabel(memory.importance))
                    .font(DSTypography.caption2)

                Spacer()
            }

            Text(memory.fact)
                .font(DSTypography.body.weight(.medium))

            HStack(spacing: 4) {
                Text(memory.createdAt, style: .date)
                Text("·")
                Text(isZh ? "上次回忆" : "Recalled")
                Text(memory.lastRecalledAt, style: .relative)
            }
            .font(DSTypography.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, DSSpacing.xxs)
    }
}
