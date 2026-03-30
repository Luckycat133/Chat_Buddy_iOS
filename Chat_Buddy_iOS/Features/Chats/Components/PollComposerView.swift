import SwiftUI

struct PollComposerView: View {
    @Environment(LocalizationManager.self) private var localization
    @Environment(\.dismiss) private var dismiss

    let onCreate: (
        _ question: String,
        _ options: [String],
        _ multiple: Bool,
        _ anonymous: Bool,
        _ hours: Int?
    ) -> Void

    @State private var question = ""
    @State private var options = ["", "", "", ""]
    @State private var allowMultiple = false
    @State private var anonymous = false
    @State private var expiryHours = 24
    @State private var enableExpiry = true

    private var isZh: Bool { localization.uiLanguage.resolved == .zh }

    private var validOptions: [String] {
        options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private var canCreate: Bool {
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && validOptions.count >= 2
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(isZh ? "问题" : "Question") {
                    TextField(isZh ? "输入投票问题" : "Enter question", text: $question, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section(isZh ? "选项" : "Options") {
                    ForEach(options.indices, id: \.self) { idx in
                        TextField((isZh ? "选项 " : "Option ") + "\(idx + 1)", text: Binding(
                            get: { options[idx] },
                            set: { options[idx] = $0 }
                        ))
                    }
                }

                Section(isZh ? "设置" : "Settings") {
                    Toggle(isZh ? "允许多选" : "Allow multiple choice", isOn: $allowMultiple)
                    Toggle(isZh ? "匿名投票" : "Anonymous poll", isOn: $anonymous)
                    Toggle(isZh ? "设置过期时间" : "Set expiration", isOn: $enableExpiry)
                    if enableExpiry {
                        Stepper(value: $expiryHours, in: 1...168) {
                            Text((isZh ? "\(expiryHours) 小时后过期" : "Expires in \(expiryHours)h"))
                        }
                    }
                }
            }
            .navigationTitle(isZh ? "创建投票" : "Create Poll")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(isZh ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isZh ? "创建" : "Create") {
                        onCreate(
                            question.trimmingCharacters(in: .whitespacesAndNewlines),
                            validOptions,
                            allowMultiple,
                            anonymous,
                            enableExpiry ? expiryHours : nil
                        )
                        dismiss()
                    }
                    .disabled(!canCreate)
                }
            }
        }
    }
}
