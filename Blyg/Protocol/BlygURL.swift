import Foundation

/// URL rules from the spec, plus defensive trimming: some live blygs have published
/// URLs with stray whitespace (" https://…"), which the protocol doesn't allow but readers meet.
nonisolated enum BlygURL {
    static let defaultFeed = "feed.xml"
    static let defaultIndex = "items/index.json"
    static let defaultItemTemplate = "items/{id}.json"
    static let manifestName = "blyg.json"

    /// Resolves an origin-relative or absolute reference against an identity origin.
    static func resolve(_ reference: String, against origin: URL) -> URL? {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed, relativeTo: origin)?.absoluteURL
    }

    /// Expands an RFC 6570 level-1 template such as `items/{id}.json` (§6.1).
    static func expand(_ template: String, _ variables: [String: String]) -> String {
        var out = template
        for (name, value) in variables {
            let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
            out = out.replacingOccurrences(of: "{\(name)}", with: encoded)
        }
        return out
    }

    /// The item document's address, honouring the manifest's `item` template.
    static func itemDocument(id: String, origin: URL, manifest: Manifest) -> URL? {
        resolve(expand(manifest.item ?? defaultItemTemplate, ["id": id]), against: origin)
    }

    static func index(origin: URL, manifest: Manifest) -> URL? {
        resolve(manifest.items ?? defaultIndex, against: origin)
    }

    static func manifest(origin: URL) -> URL {
        origin.appending(path: manifestName)
    }

    /// Subscription identity (§12.2): the URL the manifest was actually fetched from,
    /// after redirects, minus its last path segment. Never the manifest's self-asserted `site`.
    static func identityOrigin(manifestURL: URL) -> URL? {
        guard var parts = URLComponents(url: manifestURL, resolvingAgainstBaseURL: true) else { return nil }
        parts.query = nil
        parts.fragment = nil
        var path = parts.path
        if let slash = path.lastIndex(of: "/") { path = String(path[...slash]) } else { path = "/" }
        parts.path = path
        return parts.url
    }

    /// Step 1 of resolution (§12.1): parse, strip query and fragment, make the path end in "/".
    /// Also accepts a bare host ("blyg.example.com") and a pasted manifest URL, as conveniences.
    static func candidateOrigin(from input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard var parts = URLComponents(string: text), let scheme = parts.scheme?.lowercased(),
              scheme == "https" || scheme == "http", let host = parts.host, !host.isEmpty else { return nil }
        parts.query = nil
        parts.fragment = nil
        var path = parts.path
        if path.hasSuffix("/" + manifestName) { path.removeLast(manifestName.count) }
        if !path.hasSuffix("/") { path += "/" }
        parts.path = path
        return parts.url
    }

    /// The item's permalink (§5.8): its `page`, else the reference client's convention.
    static func page(for document: ItemDocument, origin: URL) -> URL? {
        if let page = document.page, let url = resolve(page, against: origin) { return url }
        let prefix = document.kind == ItemKind.thread.rawValue ? "t" : "f"
        return resolve("\(prefix)/\(document.id)/", against: origin)
    }
}

/// Protocol timestamps are ISO 8601 UTC (§4), with or without fractional seconds.
nonisolated enum BlygDate {
    static func parse(_ string: String?) -> Date? {
        guard let string = string?.trimmingCharacters(in: .whitespaces), !string.isEmpty else { return nil }
        if let date = try? Date(string, strategy: .iso8601) { return date }
        return try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }
}
