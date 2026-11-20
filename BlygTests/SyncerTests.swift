import Foundation
import Testing
@testable import Blyg

@Suite("Syncing from the archive index (§13)")
struct SyncerTests {
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    @Test func firstRefreshShowsFragmentsAndThreadsOnly() async throws {
        let blyg = try await Syncer(fetcher: FakeFetcher.sample()).refresh(try .sample(), now: now)
        let shown = Library(blygs: [blyg]).timeline().map(\.document.id)
        #expect(shown == [Fixtures.thread, Fixtures.fragmentEdited, Fixtures.fragmentPlain])
        #expect(blyg.items[Fixtures.withdrawn]?.document == nil)       // withdrawn: rolled up to null
        #expect(blyg.items[Fixtures.withdrawn]?.version == 3)          // ...but the watermark stays
        #expect(blyg.items[Fixtures.unknownKind] == nil)               // unknown kind: ignored
        #expect(blyg.lastRefresh == now)
        #expect(blyg.lastError == nil)
    }

    @Test func secondRefreshFetchesOnlyWhatChanged() async throws {
        let fetcher = FakeFetcher.sample()
        let first = try await Syncer(fetcher: fetcher).refresh(try .sample(), now: now)
        let before = fetcher.requestCount

        // Nothing changed: manifest and index only.
        let same = try await Syncer(fetcher: fetcher).refresh(first, now: now)
        #expect(fetcher.requestCount - before == 2)
        #expect(same.items == first.items)

        // The plain fragment gets a version 2.
        let bumpedIndex = Fixtures.index.replacingOccurrences(
            of: #""id":"\#(Fixtures.fragmentPlain)","kind":"fragment","created":"2026-11-15T07:30:00Z","updated":"2026-11-15T07:30:00Z","version":1"#,
            with: #""id":"\#(Fixtures.fragmentPlain)","kind":"fragment","created":"2026-11-15T07:30:00Z","updated":"2026-11-19T12:00:00Z","version":2"#)
        #expect(bumpedIndex != Fixtures.index)
        let bumpedDoc = Fixtures.fragmentPlainDocument
            .replacingOccurrences(of: #""version":1"#, with: #""version":2"#)
            .replacingOccurrences(of: "First post.", with: "First post, edited.")
        fetcher.set("https://sample.example/items/index.json", .init(body: bumpedIndex))
        fetcher.set("https://sample.example/items/\(Fixtures.fragmentPlain).json", .init(body: bumpedDoc))
        let mark = fetcher.requestCount
        let later = now.addingTimeInterval(60)
        let bumped = try await Syncer(fetcher: fetcher).refresh(same, now: later)
        #expect(fetcher.requestCount - mark == 3)
        #expect(bumped.items[Fixtures.fragmentPlain]?.version == 2)
        #expect(bumped.items[Fixtures.fragmentPlain]?.versionSeenAt == later)
        #expect(bumped.items[Fixtures.fragmentPlain]?.document?.contentHTML.contains("edited") == true)
    }

    @Test func aLowerVersionIsAReplayAndIsIgnored() async throws {
        var blyg = try await Syncer(fetcher: FakeFetcher.sample()).refresh(try .sample(), now: now)
        let stale = try decode(ItemDocument.self, Fixtures.fragmentEditedDocument
            .replacingOccurrences(of: #""version":2,"#, with: #""version":1,"#)
            .replacingOccurrences(of: "Reading about", with: "OLD"))
        let entry = ItemIndex.Entry(id: stale.id, kind: "fragment", updated: stale.updated, version: 1)
        Syncer(fetcher: FakeFetcher()).apply(stale, entry: entry, to: &blyg, now: now)
        #expect(blyg.items[Fixtures.fragmentEdited]?.version == 2)
        #expect(blyg.items[Fixtures.fragmentEdited]?.document?.contentHTML.contains("OLD") == false)
    }

    @Test func aWithdrawnItemThatReturnsIsShownAgain() async throws {
        let fetcher = FakeFetcher.sample()
        let first = try await Syncer(fetcher: fetcher).refresh(try .sample(), now: now)
        let returned = #"{"blyg":"0.4","id":"\#(Fixtures.withdrawn)","kind":"fragment","created":"2026-11-10T08:00:00Z","updated":"2026-11-19T11:00:00Z","version":4,"content_html":"<p>Back again.</p>","media":[],"changelog":[]}"#
        fetcher.set("https://sample.example/items/index.json", .init(body: Fixtures.index.replacingOccurrences(
            of: #""id":"\#(Fixtures.withdrawn)","kind":"withdrawn","created":"2026-11-10T08:00:00Z","updated":"2026-11-17T12:00:00Z","version":3"#,
            with: #""id":"\#(Fixtures.withdrawn)","kind":"fragment","created":"2026-11-10T08:00:00Z","updated":"2026-11-19T11:00:00Z","version":4"#)))
        fetcher.set("https://sample.example/items/\(Fixtures.withdrawn).json", .init(body: returned))
        let second = try await Syncer(fetcher: fetcher).refresh(first, now: now)
        #expect(second.items[Fixtures.withdrawn]?.isShowable == true)
    }

    @Test func aFailedManifestChangesNothing() async throws {
        let fetcher = FakeFetcher.sample()
        let first = try await Syncer(fetcher: fetcher).refresh(try .sample(), now: now)
        fetcher.set("https://sample.example/blyg.json", .init(status: 500, body: "oops"))
        await #expect(throws: Syncer.Failure.manifest(status: 500)) {
            _ = try await Syncer(fetcher: fetcher).refresh(first, now: now)
        }
    }

    @Test func rateLimitingStopsTheRefresh() async throws {
        let fetcher = FakeFetcher.sample()
        fetcher.set("https://sample.example/items/index.json", .init(status: 429, body: ""))
        await #expect(throws: Syncer.Failure.rateLimited) {
            _ = try await Syncer(fetcher: fetcher).refresh(try .sample(), now: now)
        }
    }

    @Test func aMissingItemDocumentIsRetriedNextTime() async throws {
        let fetcher = FakeFetcher.sample()
        fetcher.set("https://sample.example/items/\(Fixtures.thread).json", nil)
        let first = try await Syncer(fetcher: fetcher).refresh(try .sample(), now: now)
        #expect(first.items[Fixtures.thread] == nil)
        fetcher.set("https://sample.example/items/\(Fixtures.thread).json", .init(body: Fixtures.threadDocument))
        let second = try await Syncer(fetcher: fetcher).refresh(first, now: now)
        #expect(second.items[Fixtures.thread]?.isShowable == true)
    }

    @Test func firstImportIsCappedNewestFirst() async throws {
        var syncer = Syncer(fetcher: FakeFetcher.sample())
        syncer.maxDocumentsPerRefresh = 1
        let blyg = try await syncer.refresh(try .sample(), now: now)
        #expect(Library(blygs: [blyg]).timeline().map(\.document.id) == [Fixtures.thread])
    }

    @Test func aFutureDatedPostDoesntStayOnTop() async throws {
        var blyg = try await Syncer(fetcher: FakeFetcher.sample()).refresh(try .sample(), now: now)
        // An item claiming a date far in the future sorts at the time we first saw it, not at its claim.
        var doc = try #require(blyg.items[Fixtures.fragmentPlain]?.document)
        doc.updated = "2099-01-01T00:00:00Z"
        blyg.items[Fixtures.fragmentPlain]?.document = doc
        blyg.items[Fixtures.fragmentPlain]?.versionSeenAt = Date(timeIntervalSince1970: 1_000)
        #expect(Library(blygs: [blyg]).timeline().last?.document.id == Fixtures.fragmentPlain)
    }
}

@Suite("Saving")
struct StoreTests {
    func tempStore() -> LibraryStore {
        LibraryStore(directory: FileManager.default.temporaryDirectory.appending(path: "blyg tests \(UUID().uuidString)"))
    }

    @Test func savesAndLoadsAndKeepsABackup() async throws {
        let store = tempStore()
        let blyg = try await Syncer(fetcher: FakeFetcher.sample()).refresh(try .sample(), now: Date(timeIntervalSince1970: 2_000_000_000))
        var library = Library(blygs: [blyg])
        try store.save(library)
        #expect(store.load().0 == library)
        #expect(store.load().1 == .loaded)
        library.blygs[0].lastError = "x"
        try store.save(library)
        #expect(FileManager.default.fileExists(atPath: store.backupURL.path(percentEncoded: false)))
    }

    @Test func anUnreadableFileIsSetAsideAndTheBackupLoads() throws {
        let store = tempStore()
        let good = Library(blygs: [try .sample()])
        try store.save(good)
        try store.save(good) // now there's a backup
        try Data("{ not json".utf8).write(to: store.fileURL)
        let (loaded, outcome) = store.load()
        #expect(outcome == .recoveredFromBackup)
        #expect(loaded == good)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: store.directory.path(percentEncoded: false))
        #expect(leftovers.contains { $0.hasPrefix("library.unreadable-") })
    }

    @Test func aNewerFileVersionIsNotOverwrittenOrMisread() throws {
        let store = tempStore()
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data(#"{"version":99,"blygs":[]}"#.utf8).write(to: store.fileURL)
        #expect(store.load().1 == .unreadable)
    }
}
