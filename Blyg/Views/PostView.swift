import SwiftUI
import WebKit

struct PostView: View {
    let entry: TimelineEntry
    @Environment(\.openURL) private var openURL
    @Environment(\.theme) private var theme

    private var pageURL: URL? { BlygURL.page(for: entry.document, origin: entry.origin) }

    var body: some View {
        PostWebView(html: PostPage.html(for: entry, pageURL: pageURL, theme: theme), baseURL: entry.origin) { url in
            openURL(url)
        }
        .accessibilityIdentifier("postWebView")
        .background(theme.page.ignoresSafeArea())
        .navigationTitle(entry.blygTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let pageURL {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: pageURL)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { openURL(pageURL) } label: { Label("Open in Safari", systemImage: "safari") }
                }
            }
        }
    }
}

/// Builds the post page. Item HTML is arbitrary, so it's shown in a web view with JavaScript off;
/// everything this app adds around it is escaped text. Layout follows Studio's item page: the apparatus
/// (blyg, author, dates) above the post, the version history and permalink below it.
nonisolated enum PostPage {
    static func html(for entry: TimelineEntry, pageURL: URL?, theme: Theme) -> String {
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
        <header class="apparatus"><p class="blyg">\(kind)\(HTMLText.escape(entry.blygTitle))</p><p>\(byline.joined(separator: " · "))</p></header>
        <article>\(document.contentHTML)</article>
        <footer>\(history)\(permalink)</footer>
        </body></html>
        """
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
        context.coordinator.loadedHTML = html
        view.loadHTMLString(html, baseURL: baseURL)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var open: (URL) -> Void
        var loadedHTML: String?

        init(open: @escaping (URL) -> Void) { self.open = open }

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
