import SwiftUI
import WebKit

struct PostView: View {
    let entry: TimelineEntry
    @Environment(\.openURL) private var openURL

    private var pageURL: URL? { BlygURL.page(for: entry.document, origin: entry.origin) }

    var body: some View {
        PostWebView(html: PostPage.html(for: entry, pageURL: pageURL), baseURL: entry.origin) { url in
            openURL(url)
        }
        .accessibilityIdentifier("postWebView")
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
/// everything this app adds around it is escaped text.
nonisolated enum PostPage {
    static func html(for entry: TimelineEntry, pageURL: URL?) -> String {
        let document = entry.document
        let posted = formatted(document.created)
        let updated = formatted(document.updated)
        var meta: [String] = []
        if let name = document.author?.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            meta.append(HTMLText.escape(name))
        }
        if let posted { meta.append("Posted \(posted)") }
        if document.version > 1, let updated, updated != posted { meta.append("updated \(updated)") }

        var history = ""
        if document.version > 1 || !document.pinnedVersions.isEmpty {
            let rows = document.changelog.sorted { $0.version > $1.version }.map { change -> String in
                var line = "Version \(change.version)"
                if let at = formatted(change.at) { line += " · \(at)" }
                if change.pinned == true { line += " · pinned" }
                if let note = change.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                    line += "<br><span class=\"note\">\(HTMLText.escape(note))</span>"
                }
                return "<li>\(line)</li>"
            }.joined()
            // Notes are shown as text only. Older versions aren't linked: only pinned ones are ever served (§8.4).
            history = "<section class=\"history\"><h2>\(document.version) versions</h2><ul>\(rows)</ul></section>"
        }

        let permalink = pageURL.map { "<p class=\"permalink\"><a href=\"\(HTMLText.escape($0.absoluteString))\">Open this post on the web</a></p>" } ?? ""
        let kind = document.kind == ItemKind.thread.rawValue ? "<span class=\"kind\">Thread</span> " : ""

        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="script-src 'none'; object-src 'none'; frame-src 'none'; form-action 'none'">
        <style>\(css)</style></head><body>
        <header><p class="meta">\(kind)\(meta.joined(separator: " · "))</p></header>
        <article>\(document.contentHTML)</article>
        <footer>\(history)\(permalink)</footer>
        </body></html>
        """
    }

    static func formatted(_ timestamp: String?) -> String? {
        BlygDate.parse(timestamp)?.formatted(date: .abbreviated, time: .shortened)
    }

    static let css = """
    :root { color-scheme: light dark; }
    html { -webkit-text-size-adjust: 100%; }
    body { font: -apple-system-body; margin: 16px 20px 40px; line-height: 1.45; overflow-wrap: anywhere; }
    img, video { max-width: 100%; height: auto; border-radius: 6px; }
    pre, code { font-family: ui-monospace, monospace; font-size: 0.9em; }
    pre { white-space: pre-wrap; padding: 10px; border-radius: 6px; background: rgba(127,127,127,0.12); }
    blockquote { margin: 1em 0; padding: 0.1em 0 0.1em 14px; border-left: 3px solid rgba(127,127,127,0.45); }
    blockquote.blyg-transclusion { border-left-color: rgba(0,122,255,0.6); }
    table { border-collapse: collapse; display: block; overflow-x: auto; }
    td, th { border: 1px solid rgba(127,127,127,0.35); padding: 4px 8px; }
    .meta, .history, .permalink { font: -apple-system-footnote; color: rgba(127,127,127,1); }
    .kind { font-weight: 600; }
    .history h2 { font: -apple-system-headline; margin: 2em 0 0.5em; }
    .history ul { list-style: none; padding: 0; margin: 0; }
    .history li { margin: 0 0 0.6em; }
    .history .note { color: CanvasText; }
    hr { border: none; border-top: 1px solid rgba(127,127,127,0.35); }
    """
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
        view.backgroundColor = .systemBackground
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
