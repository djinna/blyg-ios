import Foundation

/// Quote cards: a post that links to a blyg post shows that post's opening words under it.
///
/// What counts as a link to a blyg post, and nothing else (so opening a post never makes the app probe ordinary websites):
/// - a `links[]` entry (§10.3a): an exact id, scoped to its origin;
/// - an `<a href>` shaped like a blyg item page, `{origin}f/{id}/` or `{origin}t/{id}/`, Studio's convention (§5.8).
///   It's only believed once the fetched item's own `page` resolves back to the same address.
///
/// Links inside a baked quote are the quoted author's, not this post's, and are skipped, as are the post's own page and
/// the post it replies to (already shown as "Replying to"). At most three cards.
nonisolated enum LinkedPosts {
    static let limit = 3

    struct Candidate: Sendable, Equatable {
        var origin: URL
        var id: String
        /// The address as written in the post, when it came from an `<a href>`; nil for a `links[]` entry.
        var href: URL?
    }

    static func candidates(in document: ItemDocument, origin: URL) -> [Candidate] {
        var found: [Candidate] = []
        func add(_ candidate: Candidate) {
            guard !found.contains(where: { $0.origin == candidate.origin && $0.id == candidate.id }) else { return }
            if candidate.origin == origin, candidate.id == document.id { return } // itself
            if let stub = document.stubOf, stub.id == candidate.id,
               stub.origin.flatMap({ URL(string: $0.trimmingCharacters(in: .whitespaces)) }) == candidate.origin { return }
            found.append(candidate)
        }
        let own = HTMLText.withoutTransclusions(document.contentHTML).html
        for href in hrefs(in: own) {
            guard let url = BlygURL.resolve(HTMLText.decodeEntities(href), against: origin),
                  let (itemOrigin, id) = itemPage(url) else { continue }
            add(Candidate(origin: itemOrigin, id: id, href: url))
        }
        for link in document.links {
            let linkOrigin = link.origin.flatMap { BlygURL.resolve($0, against: origin) } ?? origin
            add(Candidate(origin: linkOrigin, id: link.id, href: nil))
        }
        return Array(found.prefix(limit))
    }

    /// `https://host/mount/f/{id}/` → (`https://host/mount/`, id). Query and fragment are ignored.
    static func itemPage(_ url: URL) -> (URL, String)? {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let path = parts.path
        guard let regex = try? Regex(#"^(.*/)[ft]/([A-Za-z0-9_-]{1,64})/?$"#, as: (Substring, Substring, Substring).self),
              let match = path.firstMatch(of: regex) else { return nil }
        parts.path = String(match.1)
        parts.query = nil
        parts.fragment = nil
        guard let origin = parts.url else { return nil }
        return (origin, String(match.2))
    }

    /// Two spellings of one page: same scheme, host and path, ignoring case in the host, a trailing slash, query and fragment.
    static func samePage(_ a: URL, _ b: URL) -> Bool {
        func key(_ url: URL) -> String {
            var path = url.path(percentEncoded: false)
            if path.hasSuffix("/") { path.removeLast() }
            return "\(url.scheme?.lowercased() ?? "")://\(url.host()?.lowercased() ?? ""):\(url.port ?? 0)\(path)"
        }
        return key(a) == key(b)
    }

    static func hrefs(in html: String) -> [String] {
        var out: [String] = []
        var search = html[...]
        while let start = search.range(of: "<a", options: .caseInsensitive) {
            guard let end = search[start.upperBound...].firstIndex(of: ">") else { break }
            let tag = search[start.upperBound..<end]
            if tag.first?.isWhitespace == true, let href = HTMLText.attribute("href", in: tag) { out.append(href) }
            search = search[end...]
        }
        return out
    }
}

/// What a quote card shows. Everything here is the linked blyg's own, self-asserted text, shown as plain text.
nonisolated struct LinkedPost: Sendable, Hashable, Identifiable {
    var origin: URL
    var itemID: String
    /// Where tapping goes: the item's page.
    var link: URL
    var blygTitle: String
    var author: String?
    var updated: String?
    var kind: String
    /// The post's own words (quotes taken out), or empty when it was withdrawn.
    var excerpt: String
    var withdrawn: Bool

    var id: String { origin.absoluteString + "#" + itemID }

    static func from(_ document: ItemDocument?, id: String, origin: URL, blygTitle: String, fallbackLink: URL) -> LinkedPost? {
        guard let document else {
            return LinkedPost(origin: origin, itemID: id, link: fallbackLink, blygTitle: blygTitle, kind: ItemKind.withdrawn.rawValue,
                              excerpt: "", withdrawn: true)
        }
        guard let kind = ItemKind(rawValue: document.kind) else { return nil } // unknown kinds are ignored (§5.3)
        let text = HTMLText.plainText(from: HTMLText.withoutTransclusions(document.contentHTML).html)
        let author = document.author?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return LinkedPost(origin: origin, itemID: id, link: BlygURL.page(for: document, origin: origin) ?? fallbackLink,
                          blygTitle: blygTitle, author: author?.isEmpty == false ? author : nil, updated: document.updated,
                          kind: document.kind, excerpt: String(text.prefix(400)), withdrawn: kind == .withdrawn)
    }
}

/// Fetches what a quote card needs from a blyg the reader doesn't follow: its `blyg.json` and the one item document.
/// Two public GETs per card, JSON only; no images, no pages.
nonisolated struct LinkedPostLoader: Sendable {
    let fetcher: any Fetching

    func load(_ candidate: LinkedPosts.Candidate) async -> LinkedPost? {
        guard let manifestResult = try? await fetcher.get(BlygURL.manifest(origin: candidate.origin)), manifestResult.isOK,
              let manifest = try? JSONDecoder().decode(Manifest.self, from: manifestResult.data),
              let origin = BlygURL.identityOrigin(manifestURL: manifestResult.finalURL),
              let itemURL = BlygURL.itemDocument(id: candidate.id, origin: origin, manifest: manifest),
              let itemResult = try? await fetcher.get(itemURL), itemResult.isOK,
              let document = try? JSONDecoder().decode(ItemDocument.self, from: itemResult.data),
              document.id == candidate.id
        else { return nil }
        let page = BlygURL.page(for: document, origin: origin)
        // An address guessed from Studio's page convention must turn out to be the item's real page.
        if let href = candidate.href {
            guard let page, LinkedPosts.samePage(page, href) else { return nil }
        }
        let title = manifest.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fallback = page ?? candidate.href ?? origin
        if document.kind == ItemKind.withdrawn.rawValue {
            return LinkedPost.from(nil, id: candidate.id, origin: origin, blygTitle: title.isEmpty ? (origin.host() ?? "") : title,
                                   fallbackLink: fallback)
        }
        return LinkedPost.from(document, id: candidate.id, origin: origin,
                               blygTitle: title.isEmpty ? (origin.host() ?? origin.absoluteString) : title, fallbackLink: fallback)
    }
}
