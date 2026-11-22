import SwiftUI
import WebKit

struct PostView: View {
    let entry: TimelineEntry
    @Environment(LibraryModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.theme) private var theme
    @State private var replying = false
    @State private var linked: [LinkedPost]?

    /// The post as a reply target: what Reply sends as `stubOf`.
    private var replyTarget: ReplyTarget {
        ReplyTarget(origin: entry.origin, id: entry.document.id, version: entry.document.version,
                    blygTitle: entry.blygTitle, excerpt: entry.excerpt, page: pageURL)
    }

    private var pageURL: URL? { BlygURL.page(for: entry.document, origin: entry.origin) }

    /// Names a quoted post from what's already saved; nothing is fetched. A blyg you don't follow is named by its host,
    /// and its post is linked by Studio's page convention, as Studio itself does.
    private func quoteSource(origin: URL, id: String) -> QuoteSources.Source {
        let blyg = model.blyg(origin)
        let title = blyg?.title ?? origin.host() ?? origin.absoluteString
        if let document = blyg?.items[id]?.document { return .init(title: title, page: BlygURL.page(for: document, origin: origin)) }
        return .init(title: title, page: BlygURL.resolve("f/\(id)/", against: origin))
    }

    var body: some View {
        PostWebView(html: PostPage.html(for: entry, pageURL: pageURL, theme: theme, quoteSource: quoteSource,
                                        linked: linked ?? model.savedLinkedPosts(for: entry.document, origin: entry.origin)),
                    baseURL: entry.origin) { url in
            openURL(url)
        }
        // Cards from blygs this phone doesn't hold arrive a moment later; the web view keeps its scroll position.
        .task(id: entry.id) { linked = await model.linkedPosts(for: entry.document, origin: entry.origin) }
        .accessibilityIdentifier("postWebView")
        .background(theme.page.ignoresSafeArea())
        .sheet(isPresented: $replying) { ComposerView(replyTo: replyTarget) }
        #if DEBUG
        .task { if LaunchFlags.has(LaunchFlags.openReply) { replying = true } }
        #endif
        .navigationTitle(entry.blygTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !model.postingBlygs.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { replying = true } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
                        .accessibilityIdentifier("replyButton")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let pageURL {
                        ShareLink(item: pageURL)
                        Button { openURL(pageURL) } label: { Label("Open in Safari", systemImage: "safari") }
                    }
                    if model.isConnected(entry.origin) {
                        // Studio's own editor does what this app doesn't: edits, threads, pins, withdrawal.
                        Button { openURL(entry.origin.appending(path: "studio")) } label: {
                            Label("Edit in Studio", systemImage: "slider.horizontal.3")
                        }
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .accessibilityIdentifier("postMoreMenu")
            }
        }
    }
}

/// Builds the post page. Item HTML is arbitrary, so it's shown in a web view with JavaScript off;
/// everything this app adds around it is escaped text. Layout follows Studio's item page: the apparatus
/// (blyg, author, dates) above the post, the version history and permalink below it.
nonisolated enum PostPage {
    static func html(for entry: TimelineEntry, pageURL: URL?, theme: Theme,
                     quoteSource: (URL, String) -> QuoteSources.Source = { origin, _ in .init(title: origin.host() ?? "") },
                     linked: [LinkedPost] = []) -> String {
        let document = entry.document
        let posted = formatted(document.created)
        let updated = formatted(document.updated)
        var byline: [String] = []
        if let name = document.author?.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            byline.append(HTMLText.escape(name))
        }
        if let posted { byline.append(posted) }
        if document.version > 1, let updated, updated != posted { byline.append("updated \(updated)") }
        let kind = document.kind == ItemKind.thread.rawValue ? "<span class=\"kind\">Thread</span> · " : ""
        var replying = ""
        if let reply = document.stubOf {
            // The citation is the replier's own label, frozen when they replied (§5.9): shown as theirs, never as verified.
            let label = HTMLText.escape(reply.label)
            let target = reply.link.map { "<a href=\"\(HTMLText.escape($0.absoluteString))\">\(label)</a>" } ?? label
            let excerpt = reply.cited?.excerpt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            replying = "<p class=\"replying\">Replying to \(target)</p>" + (excerpt.isEmpty ? "" : "<p class=\"cited\">\(HTMLText.escape(excerpt))</p>")
        }

        var history = ""
        if document.version > 1 || !document.pinnedVersions.isEmpty {
            let latestNote = document.changelog.first { $0.version == document.version }?.note?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let rows = document.changelog.sorted { $0.version > $1.version }.map { change -> String in
                var line = "v\(change.version)"
                if let at = formatted(change.at) { line += " · \(at)" }
                if let note = change.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                    line += " — <em>\(HTMLText.escape(note))</em>"
                }
                if change.pinned == true { line += " · pinned" }
                return "<li>\(line)</li>"
            }.joined()
            // Notes are text only. Older versions aren't linked: only pinned ones are ever served (§8.4).
            let note = latestNote.flatMap { $0.isEmpty ? nil : "<p class=\"note\">\(HTMLText.escape($0))</p>" } ?? ""
            history = "<section class=\"history\" aria-label=\"Versions\"><p>Version \(document.version) of \(document.version)</p>\(note)<ol>\(rows)</ol></section>"
        }

        let permalink = pageURL.map { url -> String in
            let shown = (url.host() ?? "") + url.path()
            return "<p class=\"permalink\"><a href=\"\(HTMLText.escape(url.absoluteString))\">\(HTMLText.escape(shown))</a></p>"
        } ?? ""

        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="script-src 'none'; object-src 'none'; frame-src 'none'; form-action 'none'">
        <style>\(theme.css)</style></head><body>
        <header class="apparatus"><p class="blyg">\(kind)\(HTMLText.escape(entry.blygTitle))</p><p>\(byline.joined(separator: " · "))</p>\(replying)</header>
        <article>\(QuoteSources.annotate(document.contentHTML, ownOrigin: entry.origin, describe: quoteSource))</article>
        \(cards(linked))<footer>\(history)\(permalink)</footer>
        </body></html>
        """
    }

    /// Quote cards for the blyg posts this one links to: plain, escaped text only, never the linked post's HTML or images.
    static func cards(_ posts: [LinkedPost]) -> String {
        guard !posts.isEmpty else { return "" }
        let items = posts.map { post -> String in
            var meta: [String] = []
            if post.kind == ItemKind.thread.rawValue { meta.append("<span class=\"kind\">Thread</span>") }
            meta.append(HTMLText.escape(post.blygTitle))
            if let author = post.author, author != post.blygTitle { meta.append(HTMLText.escape(author)) }
            if let date = BlygDate.parse(post.updated)?.formatted(date: .abbreviated, time: .omitted) { meta.append(date) }
            let text = post.withdrawn ? "<span class=\"card-text gone\">Withdrawn by its author.</span>"
                : "<span class=\"card-text\">\(HTMLText.escape(post.excerpt))</span>"
            return "<a class=\"card\" href=\"\(HTMLText.escape(post.link.absoluteString))\"><span class=\"card-meta\">\(meta.joined(separator: " · "))</span>\(text)</a>"
        }
        return "<section class=\"linked\" aria-label=\"Linked posts\"><p class=\"linked-label\">Links to</p>\(items.joined())</section>"
    }

    static func formatted(_ timestamp: String?) -> String? {
        BlygDate.parse(timestamp)?.formatted(date: .abbreviated, time: .shortened)
    }
}

/// A locked-down web view: no JavaScript, no frames, no stored cookies. Tapping a link hands it to the system.
struct PostWebView: UIViewRepresentable {
    let html: String
    let baseURL: URL
    let open: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(open: open) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.websiteDataStore = .nonPersistent()
        config.dataDetectorTypes = []
        config.allowsInlineMediaPlayback = true
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .clear
        view.allowsLinkPreview = true
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.open = open
        guard context.coordinator.loadedHTML != html else { return }
        // A reload (cards arriving, a refresh) keeps the reader where they were rather than jumping to the top.
        if context.coordinator.loadedHTML != nil { context.coordinator.restoreOffset = view.scrollView.contentOffset }
        context.coordinator.loadedHTML = html
        view.loadHTMLString(html, baseURL: baseURL)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var open: (URL) -> Void
        var loadedHTML: String?
        var restoreOffset: CGPoint?

        init(open: @escaping (URL) -> Void) { self.open = open }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let offset = restoreOffset else { return }
            restoreOffset = nil
            webView.scrollView.setContentOffset(offset, animated: false)
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            // Only the page this app loaded may render here. Frames and every other navigation are refused;
            // a tapped link opens outside the app.
            guard action.targetFrame?.isMainFrame ?? true else { return .cancel }
            if action.navigationType == .other, action.request.url == webView.url || webView.url == nil {
                return .allow
            }
            if action.navigationType == .linkActivated, let url = action.request.url,
               let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme) {
                open(url)
            }
            return .cancel
        }
    }
}
