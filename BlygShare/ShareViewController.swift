import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// "Post to blyg" from any app's share sheet. It reads the shared page, text or photo,
/// and the blygs this phone is connected to from the shared Keychain, then posts with the same code as the app.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let model = ShareModel(context: extensionContext)
        let host = UIHostingController(rootView: ShareView(model: model))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        Task { await model.load() }
    }
}

@Observable
final class ShareModel {
    let connections: [Connection]
    var target: URL?
    var text = ""
    var link = ""
    var linkTitle = ""
    var photo: MediaUpload?
    var photoPreview: UIImage?
    var alt = ""
    var step: PostStep?
    var error: String?
    var loading = true

    private let context: NSExtensionContext?
    private let tokens = KeychainTokenStore()

    init(context: NSExtensionContext?) {
        self.context = context
        connections = tokens.connections()
        target = connections.first?.origin
    }

    var linkURL: URL? {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return nil }
        return url
    }

    var draft: PostDraft {
        var draft = PostDraft(text: text, link: linkURL, linkTitle: linkTitle, photo: photo)
        draft.photo?.alt = alt
        return draft
    }

    /// Reads what was shared: a page (URL plus title), text, or a photo.
    func load() async {
        defer { loading = false }
        let items = context?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        for item in items {
            let title = (item.attributedTitle ?? item.attributedContentText)?.string
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            for provider in item.attachments ?? [] {
                if link.isEmpty, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL, !url.isFileURL {
                    link = url.absoluteString
                    if !title.isEmpty, title != url.absoluteString { linkTitle = title }
                } else if text.isEmpty, provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                          let string = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                    if let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme?.hasPrefix("http") == true, link.isEmpty {
                        link = url.absoluteString
                    } else {
                        text = string
                    }
                } else if photo == nil, provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    await loadImage(provider)
                }
            }
        }
    }

    private func loadImage(_ provider: NSItemProvider) async {
        guard let item = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier) else { return }
        var data: Data?
        if let url = item as? URL { data = try? Data(contentsOf: url) }
        else if let image = item as? UIImage { data = image.jpegData(compressionQuality: 0.9) }
        else if let raw = item as? Data { data = raw }
        guard let data, let upload = try? PhotoPrep.upload(from: data, alt: "") else {
            error = "Couldn't read that photo."
            return
        }
        photo = upload
        photoPreview = UIImage(data: upload.data)
    }

    func post() {
        guard let target, let connection = connections.first(where: { $0.origin == target }),
              let token = tokens.token(for: target) else {
            error = "This phone isn't connected to that blyg any more. Open Blyg and connect it again."
            return
        }
        let poster = Poster(client: StudioClient(api: connection.api, token: token, transport: URLSessionTransport()), origin: target)
        let draft = draft
        error = nil
        step = .creating
        Task {
            do throws(PostFailure) {
                _ = try await poster.post(draft) { newStep in
                    await MainActor.run { self.step = newStep }
                }
                context?.completeRequest(returningItems: [], completionHandler: nil)
            } catch {
                step = nil
                self.error = Poster.describe(error, blygTitle: connection.title)
            }
        }
    }

    func cancel() {
        context?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }
}

struct ShareView: View {
    @Bindable var model: ShareModel

    var body: some View {
        NavigationStack {
            Group {
                if model.connections.isEmpty {
                    ContentUnavailableView {
                        Label("No blyg connected", systemImage: "square.and.pencil")
                    } description: {
                        Text("Open Blyg, go to Your blygs, choose your blyg and connect it with a token. Then share again.")
                    }
                } else {
                    form
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { model.cancel() }.disabled(model.step != nil)
                }
                if !model.connections.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        if model.step != nil {
                            ProgressView()
                        } else {
                            Button("Post") { model.post() }
                                .disabled(model.loading || model.draft.isEmpty || model.target == nil
                                          || (!model.link.isEmpty && model.linkURL == nil))
                        }
                    }
                }
            }
        }
    }

    private var title: String {
        guard model.connections.count == 1, let only = model.connections.first else { return "Post to blyg" }
        return "Post to \(only.title)"
    }

    private var form: some View {
        Form {
            if model.connections.count > 1 {
                Picker("Post to", selection: $model.target) {
                    ForEach(model.connections) { Text($0.title).tag(Optional($0.origin)) }
                }
            }
            Section {
                TextEditor(text: $model.text)
                    .frame(minHeight: 110)
                    .accessibilityLabel("Your note")
            } footer: {
                Text("Your note, in markdown. The link goes below it.")
            }
            Section("Link") {
                TextField("https://…", text: $model.link)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !model.link.isEmpty {
                    TextField("Link text (optional)", text: $model.linkTitle)
                }
            }
            if let preview = model.photoPreview {
                Section("Photo") {
                    Image(uiImage: preview).resizable().scaledToFit().frame(maxHeight: 200)
                        .accessibilityHidden(true)
                    TextField("Describe the photo for people who can't see it", text: $model.alt, axis: .vertical)
                }
            }
            if let error = model.error {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .disabled(model.step != nil)
    }
}
