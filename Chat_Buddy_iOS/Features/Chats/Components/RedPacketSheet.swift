import SwiftUI

struct RedPacketSheet: View {
    @Environment(SocialService.self) private var social
    @Environment(LocalizationManager.self) private var localization
    @Environment(\.dismiss) private var dismiss

    let onSend: (_ amount: Int, _ message: String) -> Void

    @State private var amountText = "20"
    @State private var blessingText = ""
    @State private var showInsufficient = false

    private var isZh: Bool { localization.uiLanguage.resolved == .zh }

    private var amount: Int {
        Int(amountText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    private var isValidAmount: Bool {
        amount >= 1 && amount <= 9999
    }

    private var canSend: Bool {
        isValidAmount && amount <= social.points
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(isZh ? "当前积分" : "Current Points")
                        Spacer()
                        Label("\(social.points)", systemImage: "star.fill")
                            .foregroundStyle(.yellow)
                    }
                }

                Section(isZh ? "红包金额" : "Amount") {
                    TextField(isZh ? "输入金额" : "Enter amount", text: $amountText)
#if os(iOS)
                        .keyboardType(.numberPad)
#endif
                    if !isValidAmount {
                        Text(isZh ? "请输入 1-9999 之间的整数" : "Enter an integer between 1 and 9999")
                            .font(DSTypography.caption2)
                            .foregroundStyle(.red)
                    }
                }

                Section(isZh ? "祝福语" : "Blessing") {
                    TextField(
                        isZh ? "恭喜发财，万事如意" : "Best wishes and good luck",
                        text: $blessingText,
                        axis: .vertical
                    )
                    .lineLimit(1...3)
                }

                if showInsufficient {
                    Section {
                        Text(isZh ? "积分不足，无法发送红包" : "Not enough points to send this packet")
                            .font(DSTypography.caption1)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(isZh ? "发红包" : "Red Packet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(isZh ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isZh ? "发送" : "Send") {
                        guard canSend else {
                            showInsufficient = true
                            return
                        }
                        onSend(amount, blessingText.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .disabled(!isValidAmount)
                }
            }
        }
    }
}
