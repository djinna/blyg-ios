import SwiftUI

struct AddBlygView: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("blyg.example.com", text: $address)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .focused($focused)
                        .onSubmit(add)
                        .accessibilityIdentifier("blygAddressField")
                } header: {
                    Text("Address")
                } footer: {
                    Text("A blyg's address, a link to one of its posts, or its feed.")
                }
                if let error {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Add a blyg")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if busy {
                        ProgressView()
                    } else {
                        Button("Add", action: add)
                            .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
                            .accessibilityIdentifier("confirmAddButton")
                    }
                }
            }
            .onAppear { focused = true }
            .interactiveDismissDisabled(busy)
        }
    }

    private func add() {
        guard !busy, !address.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        busy = true
        error = nil
        Task {
            do {
                try await model.add(address)
                dismiss()
            } catch {
                self.error = LibraryModel.describe(error)
            }
            busy = false
        }
    }
}
