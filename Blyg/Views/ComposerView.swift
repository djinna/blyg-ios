import PhotosUI
import SwiftUI

/// Write a fragment and publish it to one of your connected blygs.
struct ComposerView: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var target: URL?
    @State private var text: String
    @State private var link: String
    @State private var linkTitle: String
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: MediaUpload?
    @State private var photoPreview: Image?
    @State private var alt = ""
    @State private var step: PostStep?
    @State private var error: String?
    @FocusState private var textFocused: Bool

    init(text: String = "", link: String = "", linkTitle: String = "") {
        _text = State(initialValue: text)
        _link = State(initialValue: link)
        _linkTitle = State(initialValue: linkTitle)
    }

    private var blygs: [SavedBlyg] { model.postingBlygs }
    private var linkURL: URL? {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), url.host() != nil else { return nil }
        return url
    }
    private var draft: PostDraft {
        var draft = PostDraft(text: text, link: linkURL, linkTitle: linkTitle, photo: photo)
        draft.photo?.alt = alt
        return draft
    }
    private var linkIsInvalid: Bool { !link.trimmingCharacters(in: .whitespaces).isEmpty && linkURL == nil }

    var body: some View {
        NavigationStack {
            Form {
                if blygs.count > 1 {
                    Picker("Post to", selection: $target) {
                        ForEach(blygs) { blyg in Text(blyg.title).tag(Optional(blyg.origin)) }
                    }
                }
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 140)
                        .focused($textFocused)
                        .accessibilityLabel("Post text")
                        .accessibilityIdentifier("composerText")
                } footer: {
                    Text("Markdown. Leave a blank line between paragraphs. \(text.unicodeScalars.count) characters; blygs keep fragments short.")
                }
                Section("Link") {
                    TextField("https://…", text: $link)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !link.isEmpty {
                        TextField("Link text (optional)", text: $linkTitle)
                    }
                    if linkIsInvalid {
                        Text("That isn't a web address.").font(.footnote).foregroundStyle(.red)
                    }
                }
                Section("Photo") {
                    if let photoPreview {
                        photoPreview.resizable().scaledToFit().frame(maxHeight: 220)
                            .clipShape(.rect(cornerRadius: 8))
                            .accessibilityHidden(true)
                        TextField("Describe the photo for people who can't see it", text: $alt, axis: .vertical)
                        Button("Remove photo", role: .destructive) { clearPhoto() }
                    }
                    let pickLabel = photo == nil ? "Add a photo" : "Choose a different photo"
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(pickLabel, systemImage: "photo")
                    }
                }
                if let error {
                    Section {
                        Text(error).foregroundStyle(.red).textSelection(.enabled)
                    }
                }
            }
            .navigationTitle(targetTitle.map { "Post to \($0)" } ?? "New post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(step != nil)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if let step {
                        HStack(spacing: 6) {
                            ProgressView()
                            Text(label(for: step)).font(.footnote)
                        }
                    } else {
                        Button("Post", action: post)
                            .disabled(draft.isEmpty || linkIsInvalid || target == nil)
                            .accessibilityIdentifier("postButton")
                    }
                }
            }
            .interactiveDismissDisabled(step != nil || !draft.isEmpty)
            .onAppear {
                if target == nil { target = blygs.first?.origin }
                textFocused = true
            }
            .onChange(of: photoItem) { _, item in loadPhoto(item) }
        }
    }

    private var targetTitle: String? {
        guard blygs.count == 1, let target else { return nil }
        return model.blyg(target)?.title
    }

    private func label(for step: PostStep) -> String {
        switch step {
        case .creating: "Sending…"
        case .uploadingPhoto: "Uploading photo…"
        case .publishing: "Publishing…"
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        error = nil
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw PhotoPrep.Failure.unreadable }
                let upload = try PhotoPrep.upload(from: data, alt: alt)
                photo = upload
                photoPreview = UIImage(data: upload.data).map(Image.init(uiImage:))
            } catch {
                clearPhoto()
                self.error = "Couldn't use that photo."
            }
        }
    }

    private func clearPhoto() {
        photo = nil
        photoPreview = nil
        photoItem = nil
    }

    private func post() {
        guard let target, let poster = model.poster(for: target) else {
            error = "This phone isn't connected to that blyg any more. Connect it again in Your blygs."
            return
        }
        let title = model.blyg(target)?.title ?? "the blyg"
        let draft = draft
        error = nil
        step = .creating
        Task {
            do throws(PostFailure) {
                _ = try await poster.post(draft) { newStep in
                    await MainActor.run { step = newStep }
                }
                step = nil
                dismiss()
                await model.refresh(target)
            } catch {
                step = nil
                self.error = Poster.describe(error, blygTitle: title)
            }
        }
    }
}
