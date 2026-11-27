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
    /// Keeping in step with this blyg's Studio: the blygs its subscriptions listed last time. Only blygs new to
    /// that list are followed on later refreshes, so one unfollowed in the app never comes back. Nil when off.
    var studioFollows: [URL]?

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

nonisolated extension TimelineEntry {
    /// The row for one post. This is the costly part of building a timeline: the post's HTML is read through
    /// for its text and first picture. So it's done only for posts that will be shown.
    init(blyg: SavedBlyg, document: ItemDocument, sortDate: Date) {
        // Only the author's own words and pictures: quoted posts are someone else's.
        let own = HTMLText.withoutTransclusions(document.contentHTML)
        self.init(origin: blyg.origin, blygTitle: blyg.title, document: document, sortDate: sortDate,
                  excerpt: String(HTMLText.plainText(from: own.html).prefix(600)),
                  imageURL: HTMLText.firstImageURL(in: own.html, origin: blyg.origin),
                  quoteCount: own.quotes)
    }
}

/// How much of what's saved the main feed shows: a recent window, so the feed has an end and building it
/// doesn't cost more every day. Older posts stay saved, and each blyg's own page lists all of its posts.
nonisolated enum FeedWindow {
    /// Posts from this many days back...
    static let days = 14
    /// ...and no more than this many, the newest. Whichever is fewer.
    static let maxPosts = 200

    /// The oldest moment the feed reaches back to, measured from `now`.
    static func cutoff(from now: Date) -> Date { now.addingTimeInterval(-Double(days) * 86_400) }

    /// The line the feed ends with: that this is the end, and how far back it goes.
    /// `shown`: the posts in the feed; `oldest`: the date on the last of them.
    static func endLine(shown: Int, oldest: Date?) -> String {
        if shown == 0 { return "No posts in the last \(days) days." }
        if shown >= maxPosts, let oldest {
            return "You're up to date. These are the newest \(maxPosts) posts, back to \(oldest.formatted(.dateTime.month(.abbreviated).day()))."
        }
        return "You're up to date. That's everything from the last \(days) days."
    }

    /// Where the rest are, said under the end line.
    static let olderLine = "Older posts are on each blyg's own page, in Your blygs."
}

nonisolated extension SavedItem {
    /// Where a post sorts, and what the feed's window is measured by. Each origin's own `updated` is
    /// self-asserted, so it is capped at the moment this app first saw that version: a future-dated post
    /// can't sit on top forever.
    func sortDate(of document: ItemDocument) -> Date {
        min(BlygDate.parse(document.updated) ?? versionSeenAt, versionSeenAt)
    }
}

nonisolated extension SavedBlyg {
    /// How many posts of this blyg are saved: all of them, not only those recent enough for the main feed.
    var postCount: Int { items.values.count(where: \.isShowable) }

    /// Every saved post of this blyg, newest first, for its own page. Unlike the main feed this has no window,
    /// so it builds a row for every post: call it off the main actor.
    func posts() -> [TimelineEntry] {
        items.values.compactMap { item -> TimelineEntry? in
            guard item.isShowable, let document = item.document else { return nil }
            return TimelineEntry(blyg: self, document: document, sortDate: item.sortDate(of: document))
        }
        .sorted { $0.sortDate != $1.sortDate ? $0.sortDate > $1.sortDate : $0.id < $1.id }
    }
}

nonisolated extension Library {
    /// Whether any post at all is saved, in the feed's window or not. Stops at the first one found.
    var hasPosts: Bool { blygs.contains { $0.items.values.contains(where: \.isShowable) } }

    /// The main feed: the posts of every blyg inside `FeedWindow`, newest first.
    ///
    /// Rows are built only for the posts that make it in. Every saved post is still looked at, but cheaply: one
    /// first seen before the cut-off is passed over without even parsing its date (its sort date can't be later
    /// than when it was seen), and the rest are sorted by date alone before any row is made.
    /// `row` is `TimelineEntry.init(blyg:document:sortDate:)` in the app; tests pass their own to count the rows built.
    func timeline(now: Date = .now,
                  row: (SavedBlyg, ItemDocument, Date) -> TimelineEntry = TimelineEntry.init(blyg:document:sortDate:)) -> [TimelineEntry] {
        struct Candidate {
            var blyg: Int
            var document: ItemDocument
            var sortDate: Date
        }
        let cutoff = FeedWindow.cutoff(from: now)
        var candidates: [Candidate] = []
        for (index, blyg) in blygs.enumerated() {
            for item in blyg.items.values where item.versionSeenAt >= cutoff {
                guard item.isShowable, let document = item.document else { continue }
                let sortDate = item.sortDate(of: document)
                if sortDate >= cutoff { candidates.append(Candidate(blyg: index, document: document, sortDate: sortDate)) }
            }
        }
        // The same order as the rows' own ids give (origin, then item id); the strings are only made for a tie.
        func id(_ candidate: Candidate) -> String { blygs[candidate.blyg].origin.absoluteString + "#" + candidate.document.id }
        candidates.sort { $0.sortDate != $1.sortDate ? $0.sortDate > $1.sortDate : id($0) < id($1) }
        return candidates.prefix(FeedWindow.maxPosts).map { row(blygs[$0.blyg], $0.document, $0.sortDate) }
    }
}
