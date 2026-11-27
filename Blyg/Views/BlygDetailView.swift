import SwiftUI

/// One blyg: where it lives, and, if it's yours, connecting this phone so it can post.
struct BlygDetailView: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let origin: URL

    @State private var token = ""
    @State private var busy = false
    @State private var error: String?
    @State private var confirmingUnfollow = false
    @State private var importing: (done: Int, total: Int)?
    @State private var importResult: String?

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
                    NavigationLink(value: Route.blygPosts(origin)) {
                        LabeledContent("All posts", value: "\(blyg.postCount)")
                    }
                    .accessibilityIdentifier("allPostsRow")
                } footer: {
                    Text("The main feed shows the last \(FeedWindow.days) days. Everything saved from this blyg is here.")
                }

                Section {
                    if model.isConnected(origin) {
                        Label("This phone can post here.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Toggle(isOn: keepInStep) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Follow what this Studio follows")
                                Text("Now, and whenever it follows a new blyg. Unfollowing here never changes your Studio.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .disabled(importing != nil)
                        .accessibilityIdentifier("keepInStepToggle")
                        if let importing {
                            ProgressView(value: Double(importing.done), total: Double(max(importing.total, 1))) {
                                Text("Following \(importing.done) of \(importing.total)…").font(.footnote)
                            }
                        }
                        if let importResult {
                            Text(importResult).font(.footnote).foregroundStyle(.secondary)
                        }
                        Link("Open Studio", destination: origin.appending(path: "studio"))
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
                                let canConnect = !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                Button(action: connect) {
                                    Text("Connect").foregroundStyle(canConnect ? AnyShapeStyle(theme.onPencil) : AnyShapeStyle(.secondary))
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(!canConnect)
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

    /// On: follow the Studio's blygs now and keep adding new ones on refresh. Off: stop adding; nothing is unfollowed.
    private var keepInStep: Binding<Bool> {
        Binding {
            model.blyg(origin)?.studioFollows != nil
        } set: { on in
            if on { importSubscriptions() } else { model.stopKeepingInStep(origin); importResult = nil }
        }
    }

    private func importSubscriptions() {
        importResult = nil
        importing = (0, 0)
        Task {
            do {
                let result = try await model.importSubscriptions(from: origin) { done, total in importing = (done, total) }
                var parts: [String] = []
                parts.append(result.added == 1 ? "Followed 1 blyg." : "Followed \(result.added) blygs.")
                if result.alreadyFollowing > 0 { parts.append("\(result.alreadyFollowing) already followed.") }
                if result.skippedFeeds > 0 { parts.append("\(result.skippedFeeds) plain RSS feeds skipped.") }
                if !result.failed.isEmpty { parts.append("Couldn't add: \(result.failed.joined(separator: ", ")).") }
                importResult = parts.joined(separator: " ")
            } catch {
                importResult = (error as? StudioError).map { $0.status == 403 ? "This token can't read the Studio's subscriptions." : $0.message }
                    ?? error.localizedDescription
            }
            importing = nil
        }
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
