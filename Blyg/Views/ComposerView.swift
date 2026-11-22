import PhotosUI
import SwiftUI

/// Write a fragment and publish it to one of your connected blygs.
struct ComposerView: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.theme) private var theme
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

    /// Set when replying: the post this answers.
    let replyTo: ReplyTarget?

    init(text: String = "", link: String = "", linkTitle: String = "", replyTo: ReplyTarget? = nil) {
        self.replyTo = replyTo
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
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let replyTo { replyHeader(replyTo) }
                    targetRow
                    TextEditor(text: $text)
                        .font(theme.prose(.title3))
                        .lineSpacing(theme.proseLineSpacing)
                        .foregroundStyle(theme.ink)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 160)
                        .padding(.horizontal, -5) // TextEditor's own inset; align its text with the labels
                        .focused($textFocused)
                        .accessibilityLabel("Post text")
                        .accessibilityIdentifier("composerText")
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text(replyTo == nil ? "Write a fragment" : "Write your reply")
                                    .font(theme.prose(.title3))
                                    .foregroundStyle(theme.soft)
                                    .padding(.top, 8)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                        }
                    section("Link") {
                        TextField("https://…", text: $link)
                            .font(theme.apparatus)
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .frame(minHeight: 44)
                        if !link.isEmpty {
                            TextField("Link text (optional)", text: $linkTitle)
                                .font(theme.prose())
                                .frame(minHeight: 44)
                        }
                        if linkIsInvalid {
                            Text("That isn't a web address.").font(theme.apparatus).foregroundStyle(.red)
                        }
                        if LinkCheck.fragmentLooksSecret(linkURL) {
                            Label(LinkCheck.secretWarning, systemImage: "key")
                                .font(theme.apparatus).foregroundStyle(.orange)
                        }
                    }
                    section("Photo") {
                        if let photoPreview {
                            photoPreview.resizable().scaledToFit().frame(maxHeight: 220)
                                .clipShape(.rect(cornerRadius: 2))
                                .accessibilityHidden(true)
                            TextField("Describe the photo for people who can't see it", text: $alt, axis: .vertical)
                                .font(theme.prose().italic())
                                .frame(minHeight: 44)
                            Button("Remove photo", role: .destructive) { clearPhoto() }
                                .font(theme.apparatus)
                                .frame(minHeight: 44)
                        }
                        let pickLabel = photo == nil ? "Add a photo" : "Choose a different photo"
                        let pickFont = theme.apparatus
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label(pickLabel, systemImage: "photo")
                                .font(pickFont)
                                .frame(minHeight: 44)
                        }
                    }
                    Text("Markdown · leave a blank line between paragraphs · \(text.unicodeScalars.count) characters")
                        .font(theme.apparatus)
                        .foregroundStyle(theme.soft)
                        .padding(.top, 14)
                    if let error {
                        Text(error)
                            .font(theme.apparatus)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                            .padding(.top, 14)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(theme.page)
            .navigationTitle(replyTo == nil ? "New fragment" : "Reply")
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
                        let canPost = !(draft.isEmpty || linkIsInvalid || target == nil)
                        // Text on blue only when enabled; disabled, the system's own grey reads properly.
                        Button(action: post) { Text("Post").foregroundStyle(canPost ? AnyShapeStyle(theme.onPencil) : AnyShapeStyle(.secondary)) }
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.capsule)
                            .disabled(!canPost)
                            .accessibilityIdentifier("postButton")
                    }
                }
            }
            .interactiveDismissDisabled(step != nil || !draft.isEmpty)
            .onAppear {
                if target == nil {
                    target = PostTarget.choose(replyingTo: replyTo?.origin, connected: blygs.map(\.origin),
                                               lastUsed: PostTarget.lastUsed)
                }
                textFocused = true
            }
            .onChange(of: photoItem) { _, item in loadPhoto(item) }
        }
    }

    /// What this reply answers, in the apparatus voice with the editorial blue rule.
    private func replyHeader(_ target: ReplyTarget) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Replying to \(target.blygTitle)", systemImage: "arrowshape.turn.up.left")
                .font(theme.apparatus)
                .foregroundStyle(theme.soft)
            if !target.excerpt.isEmpty {
                Text(target.excerpt)
                    .font(theme.prose(.callout))
                    .foregroundStyle(theme.ink)
                    .lineLimit(3)
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) { theme.pencil.frame(width: 2) }
            }
        }
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
    }

    /// "To [blyg]": a menu when more than one blyg is connected.
    private var targetRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(replyTo == nil ? "To" : "Reply from").font(theme.apparatus).foregroundStyle(theme.soft)
            // A bordered button, not plain text: where a post goes is the one choice that's hard to undo.
            if blygs.count > 1 {
                Menu {
                    Picker("Post to", selection: $target) {
                        ForEach(blygs) { blyg in Text(blyg.title).tag(Optional(blyg.origin)) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(targetTitle ?? "Choose a blyg").font(.headline)
                        Image(systemName: "chevron.up.chevron.down").font(.footnote.weight(.semibold))
                    }
                    .frame(minHeight: 32)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .padding(.vertical, 6)
                .accessibilityLabel(replyTo == nil ? "Post to \(targetTitle ?? "")" : "Reply from \(targetTitle ?? "")")
                .accessibilityIdentifier("postToPicker")
            } else {
                Text(targetTitle ?? "")
                    .font(.headline)
                    .foregroundStyle(theme.pencil)
                    .frame(minHeight: 44)
            }
            if let target {
                Text("Publishes on \(target.host() ?? target.absoluteString), publicly.")
                    .font(theme.apparatus).foregroundStyle(theme.soft)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    /// A Studio-style section: a hairline, a small label in the editorial blue, then the fields.
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(theme.label)
                .tracking(0.6)
                .foregroundStyle(theme.pencil)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { theme.rule.frame(height: 1) }
    }

    private var targetTitle: String? {
        target.flatMap { model.blyg($0)?.title }
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
                _ = try await poster.post(draft, replyTo: replyTo) { newStep in
                    await MainActor.run { step = newStep }
                }
                step = nil
                PostTarget.lastUsed = target
                dismiss()
                await model.refresh(target)
            } catch {
                step = nil
                self.error = Poster.describe(error, blygTitle: title)
            }
        }
    }
}
