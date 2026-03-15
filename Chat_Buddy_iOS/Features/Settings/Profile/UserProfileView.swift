import SwiftUI

struct UserProfileView: View {
    @Environment(UserProfileStore.self) private var profileStore
    @Environment(LocalizationManager.self) private var localization

    @State private var nickName = ""
    @State private var signature = ""
    @State private var selectedEmoji = "😊"
    @State private var saved = false

    var body: some View {
        Form {
            // Avatar picker
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DSSpacing.sm) {
                        ForEach(UserProfile.defaultAvatars, id: \.self) { emoji in
                            Button {
                                selectedEmoji = emoji
                            } label: {
                                Text(emoji)
                                    .font(.system(size: 36))
                                    .frame(width: 56, height: 56)
                                    .background(
                                        selectedEmoji == emoji
                                            ? Color.accentColor.opacity(0.18)
                                            : Color.secondary.opacity(0.08),
                                        in: Circle()
                                    )
                                    .overlay(
                                        Circle()
                                            .strokeBorder(
                                                selectedEmoji == emoji ? Color.accentColor : Color.clear,
                                                lineWidth: 2
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, DSSpacing.xs)
                }
            } header: {
                Text(localization.t("profile_avatar"))
            }

            // Name & signature
            Section {
                HStack {
                    Text(localization.t("profile_nickname"))
                        .foregroundStyle(.secondary)
                    TextField("", text: $nickName)
                        .multilineTextAlignment(.trailing)
                }
                HStack(alignment: .top) {
                    Text(localization.t("profile_signature"))
                        .foregroundStyle(.secondary)
                    TextField("", text: $signature, axis: .vertical)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(1...3)
                }
            }

            // Save
            Section {
                Button {
                    profileStore.update(
                        nickName: nickName.trimmingCharacters(in: .whitespacesAndNewlines),
                        avatarEmoji: selectedEmoji,
                        signature: signature.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                    withAnimation { saved = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        saved = false
                    }
                } label: {
                    HStack {
                        Spacer()
                        if saved {
                            Label(localization.t("profile_saved"), systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Text(localization.t("profile_save"))
                        }
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle(localization.t("profile_title"))
        .onAppear {
            nickName     = profileStore.profile.nickName
            signature    = profileStore.profile.signature
            selectedEmoji = profileStore.profile.avatarEmoji
        }
    }
}
