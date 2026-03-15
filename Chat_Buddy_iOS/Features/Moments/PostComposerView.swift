import SwiftUI
import PhotosUI

/// Full-height sheet for composing a new Moment post.
struct PostComposerView: View {
    @Binding var isPresented: Bool
    let onPost: (String, [Data], String?) -> Void

    @Environment(MomentsStore.self) private var store
    @Environment(LocalizationManager.self) private var localization

    @State private var text: String = ""
    @State private var location: String? = nil
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var imageDataList: [Data] = []
    @State private var showLocationPicker = false
    @State private var showDraftBanner = false
    @FocusState private var textFocused: Bool

    private var canPost: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    if showDraftBanner { draftBanner }

                    TextEditor(text: $text)
                        .focused($textFocused)
                        .frame(minHeight: 140)
                        .scrollContentBackground(.hidden)
                        .font(.system(size: 16))
                        .overlay(
                            Group {
                                if text.isEmpty {
                                    Text(localization.t("moments_whats_new"))
                                        .foregroundStyle(.tertiary)
                                        .font(.system(size: 16))
                                        .padding(.top, 8)
                                        .padding(.leading, 4)
                                        .allowsHitTesting(false)
                                }
                            },
                            alignment: .topLeading
                        )

                    if !imageDataList.isEmpty { imagePreviewGrid }

                    Divider()

                    // Location row
                    Button {
                        showLocationPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "location")
                            Text(location ?? localization.t("moments_add_location"))
                                .foregroundStyle(location != nil ? .primary : .secondary)
                            Spacer()
                            if location != nil {
                                Button {
                                    location = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .font(.system(size: 14))
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)

                    // Photo picker row
                    if imageDataList.count < 4 {
                        PhotosPicker(selection: $selectedItems, maxSelectionCount: 4, matching: .images) {
                            HStack {
                                Image(systemName: "photo.on.rectangle.angled")
                                Text("Photo")
                                    .font(.system(size: 14))
                                Spacer()
                                Text("\(imageDataList.count)/4")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .padding(DSSpacing.md)
            }
            .navigationTitle(localization.t("moments_new_post"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localization.t("cancel")) {
                        store.saveDraft(text: text, location: location)
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(localization.t("moments_post")) {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        onPost(trimmed, imageDataList, location)
                        store.clearDraft()
                        isPresented = false
                    }
                    .disabled(!canPost)
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showLocationPicker) {
                LocationPickerView(selected: $location)
            }
        }
        .onAppear {
            // Restore draft
            if !store.draftText.isEmpty {
                text = store.draftText
                location = store.draftLocation
                showDraftBanner = true
                // Auto-hide banner after 3s
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    showDraftBanner = false
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                textFocused = true
            }
        }
        .onChange(of: selectedItems) { _, items in
            Task {
                var loaded: [Data] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        loaded.append(data)
                    }
                }
                imageDataList = loaded
            }
        }
        .task(id: text) {
            // Debounce draft save
            guard !text.isEmpty else { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
            store.saveDraft(text: text, location: location)
        }
    }

    // MARK: - Draft Banner

    private var draftBanner: some View {
        HStack {
            Text(localization.t("moments_draft_restored"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(localization.t("moments_discard_draft")) {
                store.clearDraft()
                text = ""
                location = nil
                showDraftBanner = false
            }
            .font(.caption)
            .foregroundStyle(.red)
        }
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, DSSpacing.xs)
        .background(.yellow.opacity(0.1), in: RoundedRectangle(cornerRadius: DSRadius.sm))
    }

    // MARK: - Image Preview

    private var imagePreviewGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 2), spacing: 3) {
            ForEach(Array(imageDataList.enumerated()), id: \.offset) { idx, data in
                if let ui = UIImage(data: data) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: 110)
                        .clipped()
                        .overlay(alignment: .topTrailing) {
                            Button {
                                imageDataList.remove(at: idx)
                                if idx < selectedItems.count {
                                    selectedItems.remove(at: idx)
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.white)
                                    .shadow(radius: 2)
                                    .padding(4)
                            }
                        }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.sm))
    }
}

// MARK: - Location Picker

private struct LocationPickerView: View {
    @Binding var selected: String?
    @Environment(\.dismiss) private var dismiss
    @State private var customText = ""

    private let presets = [
        "Home 🏠", "Office 💼", "Café ☕", "Park 🌳", "Library 📚",
        "Gym 💪", "Restaurant 🍽️", "Shopping mall 🛍️", "Beach 🏖️", "Mountain 🏔️"
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("Custom") {
                    HStack {
                        TextField("Enter location…", text: $customText)
                        if !customText.isEmpty {
                            Button("Use") {
                                selected = customText
                                dismiss()
                            }
                            .font(.caption)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }
                Section("Popular") {
                    ForEach(presets, id: \.self) { loc in
                        Button(loc) {
                            selected = loc
                            dismiss()
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
