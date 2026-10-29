import SwiftUI

struct InstructionNameEditor: View {
    let edit: InstructionNameEdit
    let onSave: @MainActor (String) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var saving = false
    @State private var failed = false

    init(edit: InstructionNameEdit, onSave: @escaping @MainActor (String) async -> Bool) {
        self.edit = edit
        self.onSave = onSave
        _name = State(initialValue: edit.instruction.name ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Step name", text: Binding(get: { name }, set: { name = String($0.prefix(200)) }),
                          prompt: Text("Optional"))
                    .disabled(saving)
                Text("Leave the name empty to use the numbered part label.")
                    .foregroundStyle(.secondary)
                if failed {
                    Text("Could not save the step name. Review the latest question and try again.")
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Rename Instruction Step")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard !saving else { return }

                        saving = true
                        Task {
                            let saved = await onSave(name)
                            saving = false
                            failed = !saved
                            if saved {
                                dismiss()
                            }
                        }
                    }
                    .disabled(saving)
                }
            }
        }
        #if os(macOS)
        .frame(width: 420, height: 260)
        #endif
        .interactiveDismissDisabled(saving)
    }
}
