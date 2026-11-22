import Foundation

/// Everything the app saves: the blygs added and a copy of their items. Versioned JSON (ios.md: Data).
nonisolated struct Library: Codable, Sendable, Equatable {
    static let currentVersion = 1
    var version = Library.currentVersion
    var blygs: [SavedBlyg] = []
}

nonisolated struct SavedBlyg: Codable, Sendable, Equatable, Identifiable {
    /// Subscription identity (§12.2).
    var origin: URL
    var manifest: Manifest
    var addedAt: Date
    var lastRefresh: Date?
    /// Why the last refresh failed, for display. A failed refresh never changes stored items (§12.3, §13.2).
    var lastError: String?
    /// Items by id, scoped to this origin (§13.1 rule 7).
    var items: [String: SavedItem] = [:]
    /// The owner API this phone can post to, set when the owner connects a token (kept in the Keychain, not here).
    var postingAPI: URL?

    var id: URL { origin }

    var title: String {
        let title = manifest.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? (origin.host() ?? origin.absoluteString) : title
    }
}

nonisolated struct SavedItem: Codable, Sendable, Equatable {
    var id: String
    var kind: String
    /// The watermark: the highest version ever seen (§13.3). Never goes down.
    var version: Int
    /// When this app first saw `version`. Used to keep a skewed clock from dominating the timeline (§13.7).
    var versionSeenAt: Date
    /// The latest document, or nil when withdrawn or not fetched yet.
    var document: ItemDocument?

    var isShowable: Bool {
        guard let document, document.version == version else { return false }
        return document.kind == ItemKind.fragment.rawValue || document.kind == ItemKind.thread.rawValue
    }
}

/// One row of the timeline: an item and the blyg it came from.
nonisolated struct TimelineEntry: Sendable, Identifiable, Hashable {
    var origin: URL
    var blygTitle: String
    var document: ItemDocument
    var sortDate: Date
    /// Plain text for the row, worked out once rather than on every redraw.
    var excerpt: String
    var imageURL: URL?
    /// How many other posts a thread quotes (baked transclusions, §10). They're kept out of `excerpt`.
    var quoteCount = 0

    /// Ids are scoped to their origin (§13.1 rule 7).
    var id: String { origin.absoluteString + "#" + document.id }
}

nonisolated extension Library {
    /// Newest first across all blygs. Each origin's own `updated` is self-asserted, so it is
    /// capped at the moment this app first saw that version: a future-dated post can't sit on top forever.
    func timeline() -> [TimelineEntry] {
        blygs.flatMap { blyg in
            blyg.items.values.compactMap { item -> TimelineEntry? in
                guard item.isShowable, let document = item.document else { return nil }
                let claimed = BlygDate.parse(document.updated) ?? item.versionSeenAt
                // Only the author's own words and pictures: quoted posts are someone else's.
                let own = HTMLText.withoutTransclusions(document.contentHTML)
                return TimelineEntry(origin: blyg.origin, blygTitle: blyg.title, document: document,
                                     sortDate: min(claimed, item.versionSeenAt),
                                     excerpt: String(HTMLText.plainText(from: own.html).prefix(600)),
                                     imageURL: HTMLText.firstImageURL(in: own.html, origin: blyg.origin),
                                     quoteCount: own.quotes)
            }
        }
        .sorted { $0.sortDate != $1.sortDate ? $0.sortDate > $1.sortDate : $0.id < $1.id }
    }
}
