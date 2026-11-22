import Foundation

// The Blygger protocol's public documents (spec 0.4, blygger.org/spec/0.4/).
// Readers must ignore unknown members and must not reject a document over its
// author contents (§13.1), so optional members decode leniently: a member of
// the wrong type reads as absent instead of failing the whole document.

/// `blyg.json`: the manifest (§6.1).
nonisolated struct Manifest: Codable, Sendable, Hashable {
    var blyg: String
    var title: String?
    var updated: String?
    var site: String?
    var generator: String?
    var author: Author?
    /// Where the feed and archive index live, origin-relative or absolute. Absent means the default path.
    var feed: String?
    var items: String?
    /// RFC 6570 level-1 templates for item and pinned-version documents (§6.1).
    var item: String?
    var pin: String?

    init(blyg: String, title: String? = nil, updated: String? = nil, site: String? = nil, generator: String? = nil,
         author: Author? = nil, feed: String? = nil, items: String? = nil, item: String? = nil, pin: String? = nil) {
        self.blyg = blyg; self.title = title; self.updated = updated; self.site = site; self.generator = generator
        self.author = author; self.feed = feed; self.items = items; self.item = item; self.pin = pin
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // The one test of "is this a manifest" (§12.1 step 2): a JSON object with a "blyg" version key.
        blyg = try c.decode(String.self, forKey: .blyg)
        title = c.lenient(String.self, .title)
        updated = c.lenient(String.self, .updated)
        site = c.lenient(String.self, .site)
        generator = c.lenient(String.self, .generator)
        author = c.lenient(Author.self, .author)
        feed = c.lenient(String.self, .feed)
        items = c.lenient(String.self, .items)
        item = c.lenient(String.self, .item)
        pin = c.lenient(String.self, .pin)
    }
}

/// The opaque, self-asserted author object (§5.5). Only the display members are read.
nonisolated struct Author: Codable, Sendable, Hashable {
    var name: String?
    var url: String?
    var bio: String?

    init(name: String? = nil, url: String? = nil, bio: String? = nil) {
        self.name = name; self.url = url; self.bio = bio
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.lenient(String.self, .name)
        url = c.lenient(String.self, .url)
        bio = c.lenient(String.self, .bio)
    }
}

/// `items/index.json`: every item ever published, newest first (§6.2).
nonisolated struct ItemIndex: Decodable, Sendable {
    var updated: String?
    var items: [Entry]

    nonisolated struct Entry: Decodable, Sendable, Hashable {
        var id: String
        var kind: String
        var updated: String
        var version: Int
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        updated = c.lenient(String.self, .updated)
        // An unparseable entry is skipped on its own; the index is not rejected (§13.2).
        items = try c.decode([Lossy<Entry>].self, forKey: .items).compactMap(\.value)
    }

    private enum CodingKeys: String, CodingKey { case updated, items }
}

/// `items/{id}.json`: the ground truth for one item (§5).
nonisolated struct ItemDocument: Codable, Sendable, Hashable {
    var id: String
    var kind: String
    var version: Int
    var created: String
    var updated: String
    var origin: String?
    var page: String?
    var author: Author?
    var contentHTML: String
    var media: [Media]
    var changelog: [ChangelogEntry]
    /// Set when this item is a reply: the one thing it answers (§10.6).
    var stubOf: StubOf?
    /// Plain internal links (`[[id]]`), in document order (§10.3a). Origin absent means this document's own.
    var links: [LinkRef] = []

    nonisolated struct LinkRef: Codable, Sendable, Hashable {
        var id: String
        var origin: String?
    }

    /// A reply's target (§10.6, §5.9): a blyg item `{origin, id, version}` or a plain web `{url}`,
    /// with the citing publisher's frozen label. The label is self-asserted and shown as such.
    nonisolated struct StubOf: Codable, Sendable, Hashable {
        var origin: String?
        var id: String?
        var version: Int?
        var url: String?
        var cited: Cited?

        nonisolated struct Cited: Codable, Sendable, Hashable {
            var source: String?
            var author: String?
            var excerpt: String?
            var url: String?
            var retrieved: String?

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                source = c.lenient(String.self, .source); author = c.lenient(String.self, .author)
                excerpt = c.lenient(String.self, .excerpt); url = c.lenient(String.self, .url)
                retrieved = c.lenient(String.self, .retrieved)
            }
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            origin = c.lenient(String.self, .origin); id = c.lenient(String.self, .id)
            version = c.lenient(Int.self, .version); url = c.lenient(String.self, .url)
            cited = c.lenient(Cited.self, .cited)
        }

        /// What to call the target: the citation's source, else its host.
        var label: String {
            if let source = cited?.source?.trimmingCharacters(in: .whitespacesAndNewlines), !source.isEmpty { return source }
            let address = (origin ?? url ?? "").trimmingCharacters(in: .whitespaces)
            return URL(string: address)?.host() ?? address
        }

        /// Where tapping the target goes: the cited page, else the item's conventional page, else the URL.
        var link: URL? {
            if let page = cited?.url, let url = URL(string: page.trimmingCharacters(in: .whitespaces)) { return url }
            if let origin, let id, let base = URL(string: origin.trimmingCharacters(in: .whitespaces)) {
                return BlygURL.resolve("f/\(id)/", against: base)
            }
            return url.flatMap { URL(string: $0) }
        }
    }

    nonisolated struct Media: Codable, Sendable, Hashable {
        var url: String
        var mime: String?
        var alt: String?
    }

    nonisolated struct ChangelogEntry: Codable, Sendable, Hashable {
        var version: Int
        var at: String?
        var note: String?
        var pinned: Bool?

        init(version: Int, at: String? = nil, note: String? = nil, pinned: Bool? = nil) {
            self.version = version; self.at = at; self.note = note; self.pinned = pinned
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decode(Int.self, forKey: .version)
            at = c.lenient(String.self, .at)
            note = c.lenient(String.self, .note)
            pinned = c.lenient(Bool.self, .pinned)
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, version, created, updated, origin, page, author, media, changelog
        case contentHTML = "content_html"
        case stubOf = "stub_of"
        case links
    }

    init(id: String, kind: String, version: Int, created: String, updated: String, origin: String? = nil,
         page: String? = nil, author: Author? = nil, contentHTML: String, media: [Media] = [], changelog: [ChangelogEntry] = [],
         stubOf: StubOf? = nil, links: [LinkRef] = []) {
        self.id = id; self.kind = kind; self.version = version; self.created = created; self.updated = updated
        self.origin = origin; self.page = page; self.author = author; self.contentHTML = contentHTML
        self.media = media; self.changelog = changelog; self.stubOf = stubOf; self.links = links
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(String.self, forKey: .kind)
        version = try c.decode(Int.self, forKey: .version)
        created = try c.decode(String.self, forKey: .created)
        updated = try c.decode(String.self, forKey: .updated)
        origin = c.lenient(String.self, .origin)
        page = c.lenient(String.self, .page)
        author = c.lenient(Author.self, .author)
        contentHTML = c.lenient(String.self, .contentHTML) ?? ""
        media = (c.lenient([Lossy<Media>].self, .media) ?? []).compactMap(\.value)
        changelog = (c.lenient([Lossy<ChangelogEntry>].self, .changelog) ?? []).compactMap(\.value)
        stubOf = c.lenient(StubOf.self, .stubOf)
        links = (c.lenient([Lossy<LinkRef>].self, .links) ?? []).compactMap(\.value)
    }

    /// Versions the publisher has promised to serve forever (§8). Only these may be offered as history (§8.4).
    var pinnedVersions: [Int] { changelog.filter { $0.pinned == true }.map(\.version) }
}

/// Item kinds this reader shows. Anything else is an unknown construct and is ignored (§5.3).
nonisolated enum ItemKind: String, Sendable {
    case fragment, thread, withdrawn
}

/// Decodes a value or yields nil, so one bad array element doesn't sink its neighbours.
nonisolated struct Lossy<T: Decodable & Sendable>: Decodable, Sendable {
    var value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

nonisolated extension KeyedDecodingContainer {
    func lenient<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }
}
