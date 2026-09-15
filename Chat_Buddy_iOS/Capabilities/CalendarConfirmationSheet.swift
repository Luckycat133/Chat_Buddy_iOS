import SwiftUI

/// Calendar confirmation sheet per skill §"Calendar with EventKit":
///   - show what will happen
///   - require confirmation for writes
///   - perform through the capability service
///   - return structured success/failure to server
///   - let the character speak only after authoritative result
public struct CalendarConfirmationSheet: View {
    public let proposal: ProposedAction
    public let onConfirm: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    public init(proposal: ProposedAction, onConfirm: @escaping (Bool) -> Void) {
        self.proposal = proposal
        self.onConfirm = onConfirm
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Action") {
                    LabeledContent("Operation", value: proposal.operation.capitalized)
                }
                Section("Details") {
                    LabeledContent("Title", value: proposal.title)
                    LabeledContent("Start", value: proposal.start.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("End", value: proposal.end.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Calendar", value: proposal.calendarId)
                    if let notes = proposal.notes, !notes.isEmpty {
                        LabeledContent("Notes", value: notes)
                    }
                }
                Section {
                    Text("The character will not say this is done until the calendar confirms it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Confirm calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onConfirm(false)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onConfirm(true)
                        dismiss()
                    }
                }
            }
        }
    }
}