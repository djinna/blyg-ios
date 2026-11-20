import SwiftUI

/// One blyg: where it lives, and, if it's yours, connecting this phone so it can post.
struct BlygDetailView: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let origin: URL

    @State private var token = ""
    @State private var busy = false
    @State private var error: String?
    @State private var confirmingUnfollow = false

    var body: some View {
        if let blyg = model.blyg(origin) {
            Form {
                Section {
                    LabeledContent("Address") {
                        Text(blyg.origin.absoluteString).textSelection(.enabled)
                    }
                    if let generator = blyg.manifest.generator {
                        LabeledContent("Published with", value: generator)
                    }
                }

                Section {
                    if model.isConnected(origin) {
                        Label("This phone can post here.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Button("Disconnect", role: .destructive) { model.disconnect(origin) }
                            .accessibilityIdentifier("disconnectButton")
                    } else {
                        connectSteps
                        SecureField("Paste the token", text: $token)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("tokenField")
                        HStack {
                            PasteButton(payloadType: String.self) { strings in
                                token = strings.first ?? ""
                            }
                            .labelStyle(.titleAndIcon)
                            Spacer()
                            if busy {
                                ProgressView()
                            } else {
                                Button("Connect", action: connect)
                                    .buttonStyle(.borderedProminent)
                                    .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                    .accessibilityIdentifier("connectButton")
                            }
                        }
                        if let error {
                            Text(error).font(.footnote).foregroundStyle(.red)
                        }
                    }
                } header: {
                    Text("Is this your blyg?")
                } footer: {
                    Text("The token stays in this phone's Keychain. It's sent only to \(origin.host() ?? "this blyg").")
                }

                Section {
                    Button("Unfollow", role: .destructive) { confirmingUnfollow = true }
                }
            }
            .navigationTitle(blyg.title)
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Unfollow \(blyg.title)?", isPresented: $confirmingUnfollow, titleVisibility: .visible) {
                Button("Unfollow", role: .destructive) {
                    model.remove(origin)
                    dismiss()
                }
            } message: {
                Text("Its posts and any saved token are removed from this phone. Nothing changes on the blyg.")
            }
        } else {
            ContentUnavailableView("Not following this blyg", systemImage: "questionmark.folder")
        }
    }

    private var connectSteps: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("To post from this phone, make a token in your blyg's Studio:")
            Text("1. Open \(origin.absoluteString)studio and sign in.")
            Text("2. Go to More → Client access.")
            Text("3. Choose REST API and tick read, draft and publish.")
            Text("4. Create the token, copy it, and paste it here.")
            Text("Tokens last 30 days.").foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    private func connect() {
        busy = true
        error = nil
        Task {
            do {
                try await model.connect(origin, token: token)
                token = ""
            } catch {
                self.error = LibraryModel.describe(error)
            }
            busy = false
        }
    }
}
