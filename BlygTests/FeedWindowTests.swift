import Foundation
import Testing
@testable import Blyg

/// The main feed used to be every saved post of every blyg, so it had no end and cost more to build each day.
/// It now shows a recent window (`FeedWindow`); everything else stays saved and is read on each blyg's own page.
@Suite("The main feed is a recent window") @MainActor
struct FeedWindowTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static func daysAgo(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }
    static let origin = URL(string: "https://window.example/")!

    /// A saved post. `seen`: when this phone first saw it; the same as `updated` unless a test says otherwise.
    static func post(_ id: String, updated: Date, seen: Date? = nil) throws -> SavedItem {
        let stamp = updated.formatted(.iso8601)
        let document = try decode(ItemDocument.self, """
            {"id":"\(id)","kind":"fragment","version":1,"page":"f/\(id)/","created":"\(stamp)","updated":"\(stamp)",\
            "content_html":"<p>Post \(id).</p><p><img src=\\"media/\(id).png\\"></p>"}
            """)
        return SavedItem(id: id, kind: "fragment", version: 1, versionSeenAt: seen ?? updated, document: document)
    }

    static func blyg(_ items: [SavedItem], origin: URL = origin) -> SavedBlyg {
        var blyg = SavedBlyg(origin: origin, manifest: Manifest(blyg: "0.4", title: "Window"), addedAt: daysAgo(400))
        for item in items { blyg.items[item.id] = item }
        return blyg
    }

    /// `recent` posts a minute apart from an hour ago, and `old` posts a day apart from 15 days ago.
    static func library(recent: Int, old: Int) throws -> Library {
        let new = try (0..<recent).map { try post("new\($0)", updated: now.addingTimeInterval(-3_600 - Double($0) * 60)) }
        let aged = try (0..<old).map { try post("old\($0)", updated: daysAgo(15 + Double($0))) }
        return Library(blygs: [blyg(new + aged)])
    }

    static let other = URL(string: "https://other.example/")!

    /// Two blygs, each posting once a minute: the first one's newest post a minute ago, the second's `bStartsMinutesAgo`.
    static func twoBlygs(a: Int, b: Int, bStartsMinutesAgo: Double) throws -> Library {
        let first = try (0..<a).map { try post("a\($0)", updated: now.addingTimeInterval(-60 - Double($0) * 60)) }
        let second = try (0..<b).map { try post("b\($0)", updated: now.addingTimeInterval(-bStartsMinutesAgo * 60 - Double($0) * 60)) }
        return Library(blygs: [blyg(first), blyg(second, origin: other)])
    }

    /// A clock a test can set, and a build it can hold, for a model's feed.
    final class Feed: @unchecked Sendable {
        private let lock = NSLock()
        private var date: Date
        private var hold: Hold?
        init(now: Date) { date = now }
        var now: Date {
            get { lock.withLock { date } }
            set { lock.withLock { date = newValue } }
        }
        func holdNextBuild() -> Hold {
            let hold = Hold()
            lock.withLock { self.hold = hold }
            return hold
        }
        func build(_ library: Library) -> [TimelineEntry] {
            let (now, hold) = lock.withLock { (date, self.hold) }
            hold?.wait()
            return library.timeline(now: now)
        }
    }

    /// A model opened on a saved file holding `library`, with the feed's window measured from `now`.
    func opened(on library: Library, fetcher: FakeFetcher = FakeFetcher()) throws -> (LibraryModel, CountingStore) {
        let store = CountingStore()
        try store.store.save(library)
        let now = Self.now
        return (LibraryModel(store: store, fetcher: fetcher, buildTimeline: { $0.timeline(now: now) }), store)
    }

    // 1. The last 14 days, and at most 200 posts, whichever is fewer.
    @Test func theFeedShowsTheLastFourteenDaysAndAtMostTwoHundredPosts() throws {
        #expect(FeedWindow.days == 14)
        #expect(FeedWindow.maxPosts == 200)

        let byAge = Library(blygs: [Self.blyg([
            try Self.post("a", updated: Self.daysAgo(1)), try Self.post("b", updated: Self.daysAgo(13.9)),
            try Self.post("c", updated: Self.daysAgo(14.1)), try Self.post("d", updated: Self.daysAgo(300)),
        ])])
        #expect(byAge.timeline(now: Self.now).map(\.document.id) == ["a", "b"])

        // Fewer by count: 250 posts in the last day, and the newest 200 are the ones shown.
        let byCount = try Self.library(recent: 250, old: 0).timeline(now: Self.now)
        #expect(byCount.map(\.document.id) == (0..<200).map { "new\($0)" })

        // 200 in all, not 200 for each blyg: two blygs with 150 each, posting turn about.
        let two = try Self.twoBlygs(a: 150, b: 150, bStartsMinutesAgo: 0.5).timeline(now: Self.now)
        #expect(two.count == 200)
        #expect(two.count { $0.origin == Self.origin } == 100)
        #expect(two.count { $0.origin == Self.other } == 100)
        #expect(two.last?.document.id == "a99") // the 200th newest of the 300
    }

    // 2. The cut-off is measured by the same date the feed is sorted by.
    @Test func theCutOffUsesTheDateTheFeedSortsBy() throws {
        let library = Library(blygs: [Self.blyg([
            // Says it was written yesterday, but this phone has had it for 20 days: it sorts where it was first seen.
            try Self.post("claimsToBeNew", updated: Self.daysAgo(1), seen: Self.daysAgo(20)),
            // First seen today (a blyg just followed), written 20 days ago: it sorts where it was written.
            try Self.post("oldButJustSeen", updated: Self.daysAgo(20), seen: Self.now),
            try Self.post("inside", updated: Self.daysAgo(3), seen: Self.now),
        ])])
        let feed = library.timeline(now: Self.now)
        #expect(feed.map(\.document.id) == ["inside"])
        #expect(feed.first?.sortDate == Self.daysAgo(3))
        // Each post's own page list puts all three in that same order.
        #expect(library.blygs[0].posts().map(\.document.id) == ["inside", "claimsToBeNew", "oldButJustSeen"])
    }

    // 3. The feed ends with a plain line that says how far back it goes, and says so when it's empty.
    @Test func theFeedEndsWithALineSayingHowFarBackItGoes() {
        let quiet = FeedWindow.endLine(shown: 12, oldest: Self.daysAgo(9))
        #expect(quiet.hasPrefix("You're up to date."))
        #expect(quiet.contains("last 14 days"))

        let oldest = Self.daysAgo(2)
        let busy = FeedWindow.endLine(shown: 200, oldest: oldest)
        #expect(busy.hasPrefix("You're up to date."))
        #expect(busy.contains("newest 200 posts"))
        #expect(busy.contains(oldest.formatted(.dateTime.month(.abbreviated).day())))
        #expect(!busy.contains("14 days")) // it stopped at 200, short of 14 days back

        #expect(FeedWindow.endLine(shown: 0, oldest: nil) == "No posts in the last 14 days.")
    }

    // 4. Each blyg's own page still has every saved post of that blyg, from a source of its own.
    @Test func aBlygsOwnPageShowsEverySavedPostOfThatBlyg() async throws {
        let (model, store) = try opened(on: try Self.library(recent: 210, old: 40))
        defer { store.removeFiles() }
        #expect(model.timeline.count == 200)

        let page = await model.posts(of: Self.origin)
        #expect(page.count == 250)
        #expect(page.first?.document.id == "new0")  // newest first
        #expect(page.last?.document.id == "old39")  // 54 days old, and still here
        #expect(page.last?.excerpt == "Post old39.")
        // A link to a post too old for the feed still opens in the app.
        #expect(!model.timeline.contains { $0.document.id == "old39" })
        #expect(model.entry(forPage: URL(string: "https://window.example/f/old39/")!)?.document.id == "old39")
        #expect(await model.posts(of: URL(string: "https://nobody.example/")!) == [])
    }

    // 5. The rebuild does less work: no row is built for a post outside the window.
    @Test func rowsAreBuiltOnlyForPostsInsideTheWindow() throws {
        func rowsBuilt(for library: Library) -> [Int] {
            var built = 0
            let feed = library.timeline(now: Self.now) { blyg, document, sortDate in
                built += 1
                return TimelineEntry(blyg: blyg, document: document, sortDate: sortDate)
            }
            return [built, feed.count]
        }
        // 5 recent posts among 400 old ones: 5 rows built, not 405.
        #expect(rowsBuilt(for: try Self.library(recent: 5, old: 400)) == [5, 5])
        // 300 recent ones: only the 200 shown are built.
        #expect(rowsBuilt(for: try Self.library(recent: 300, old: 400)) == [200, 200])
        // Nothing recent: nothing built.
        #expect(rowsBuilt(for: try Self.library(recent: 0, old: 400)) == [0, 0])
    }

    // 6. Nothing is deleted from storage: what the feed leaves out stays in the library and in its file.
    @Test func postsOutsideTheWindowStaySaved() async throws {
        let fetcher = FakeFetcher([
            "https://window.example/blyg.json": .init(body: #"{"blyg":"0.4","title":"Window"}"#),
            "https://window.example/items/index.json": .init(body: #"{"items":[]}"#),
        ])
        let (model, store) = try opened(on: try Self.library(recent: 3, old: 40), fetcher: fetcher)
        defer { store.removeFiles() }
        #expect(model.timeline.count == 3)

        await model.refreshAll() // a refresh rebuilds the feed and saves the library
        await model.saveFinished()
        #expect(store.saves == 1)
        #expect(model.blyg(Self.origin)?.lastRefresh != nil)
        #expect(model.timeline.count == 3)
        #expect(model.blyg(Self.origin)?.items.count == 43)
        let saved = try #require(store.load().0.blygs.first)
        #expect(saved.items.count == 43)
        #expect(saved.items["old39"]?.document?.contentHTML.contains("Post old39.") == true)
    }

    // From Codex's review: unfollowing the blyg that filled the feed makes room, and the others' posts move up into it.
    @Test func unfollowingABlygThatFilledTheFeedBringsInTheOthersPosts() async throws {
        // The first blyg's 200 posts are all newer than the second's 20, which are a day old.
        let (model, store) = try opened(on: try Self.twoBlygs(a: 200, b: 20, bStartsMinutesAgo: 24 * 60))
        defer { store.removeFiles() }
        #expect(model.timeline.count == 200)
        #expect(model.timeline.allSatisfy { $0.origin == Self.origin })

        model.remove(Self.origin)
        #expect(model.timeline.isEmpty) // its rows go at once...
        await until { model.timeline.count == 20 } // ...and the posts that were below them come in
        #expect(model.timeline.allSatisfy { $0.origin == Self.other })
        await model.saveFinished()
    }

    // The same, when the unfollow lands while a rebuild that still has the blyg is under way.
    @Test func aBlygUnfollowedDuringARebuildItWouldHaveFilledLeavesRoomForTheOthers() async throws {
        // Ten days ago the first blyg posted 60 times; two days before that the second posted 20; an hour ago the first posted 150.
        let recent = try (0..<150).map { try Self.post("a\($0)", updated: Self.now.addingTimeInterval(-3_600 - Double($0) * 60)) }
        let older = try (0..<60).map { try Self.post("a-old\($0)", updated: Self.daysAgo(10).addingTimeInterval(-Double($0) * 60)) }
        let quiet = try (0..<20).map { try Self.post("b\($0)", updated: Self.daysAgo(12).addingTimeInterval(-Double($0) * 60)) }
        let fetcher = FakeFetcher([
            "https://other.example/blyg.json": .init(body: #"{"blyg":"0.4","title":"Other"}"#),
            "https://other.example/items/index.json": .init(body: #"{"items":[]}"#),
        ])
        let store = CountingStore()
        defer { store.removeFiles() }
        try store.store.save(Library(blygs: [Self.blyg(recent + older), Self.blyg(quiet, origin: Self.other)]))
        let feed = Feed(now: Self.now)
        feed.now = Self.now.addingTimeInterval(5 * 86_400) // five days on, only the 150 are inside the window: not a full feed
        let model = LibraryModel(store: store, fetcher: fetcher, buildTimeline: { feed.build($0) })
        #expect(model.timeline.count == 150)

        feed.now = Self.now // back to where 230 posts are inside it: the next build is full, all of it the first blyg's
        let hold = feed.holdNextBuild()
        let refresh = Task { await model.refresh(Self.other) }
        await until { hold.wasReached }
        model.remove(Self.origin)
        hold.release()
        await refresh.value
        await until { model.timeline.count == 20 }
        #expect(!hold.gaveUp)
        #expect(model.timeline.allSatisfy { $0.origin == Self.other })
        await model.saveFinished()
    }

    // From Codex's review: a refresh that reaches no blyg brings no posts, but still moves the window.
    @Test func aRefreshThatReachesNoOneStillMovesTheWindow() async throws {
        let store = CountingStore()
        defer { store.removeFiles() }
        try store.store.save(Library(blygs: [Self.blyg([try Self.post("almostOut", updated: Self.daysAgo(13.5))])]))
        let feed = Feed(now: Self.now)
        let model = LibraryModel(store: store, fetcher: FakeFetcher(), buildTimeline: { feed.build($0) }) // nothing answers
        #expect(model.timeline.count == 1)

        feed.now = Self.now.addingTimeInterval(86_400) // a day passes with the app open; the post is now 14.5 days old
        await model.refreshAll()
        await model.saveFinished()
        #expect(model.blyg(Self.origin)?.lastError != nil)
        #expect(model.timeline.isEmpty)
        #expect(model.blyg(Self.origin)?.items.count == 1) // still saved
    }

    // 7. The post counts on "Your blygs" are of every saved post, whatever the feed shows.
    @Test func aBlygsPostCountIsOfEverySavedPost() throws {
        let library = try Self.library(recent: 3, old: 40)
        #expect(library.timeline(now: Self.now).count == 3)
        #expect(library.blygs[0].postCount == 43)
        #expect(library.hasPosts)

        var withdrawn = library.blygs[0]
        withdrawn.items["old0"]?.document = nil // withdrawn, or not fetched yet: not a post to count
        #expect(withdrawn.postCount == 42)
        #expect(!Library(blygs: [Self.blyg([])]).hasPosts)
    }
}
