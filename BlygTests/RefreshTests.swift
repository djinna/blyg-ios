import Foundation
import Testing
@testable import Blyg

/// A tester's build 9 hung while refreshing. The model is on the main actor, and it used to do each blyg's
/// decoding there, then rebuild the whole timeline and rewrite the whole library file once per blyg.
@Suite("Refreshing without holding the main actor") @MainActor
struct RefreshTests {
    static let hosts = ["second", "third", "fourth"]
    static func origin(_ host: String) -> URL { URL(string: "https://\(host).example/")! }

    struct Following {
        let model: LibraryModel
        let fetcher: FakeFetcher
        let store: CountingStore
        let timeline: TimelineCounter
    }

    /// A model following the sample blyg and three empty ones, all refreshed and saved, with the counts at zero.
    func following() async throws -> Following {
        let fetcher = FakeFetcher.sample()
        for host in Self.hosts {
            fetcher.set("https://\(host).example/blyg.json", .init(body: #"{"blyg":"0.4","title":"\#(host)"}"#))
            fetcher.set("https://\(host).example/items/index.json", .init(body: #"{"items":[]}"#))
        }
        let store = CountingStore()
        let timeline = TimelineCounter()
        let model = LibraryModel(store: store, fetcher: fetcher, buildTimeline: { timeline.build($0) })
        for host in ["sample"] + Self.hosts { try await model.add("\(host).example") }
        await model.saveFinished()
        timeline.reset()
        return Following(model: model, fetcher: fetcher, store: store, timeline: timeline)
    }

    /// What the file must agree with the model on. Not `==`: saved dates drop their fractions of a second.
    func digest(_ library: Library) -> [String] {
        library.blygs.map { blyg in
            "\(blyg.origin.absoluteString) items \(blyg.items.keys.sorted()) error \(blyg.lastError ?? "none") "
                + "refreshed \(blyg.lastRefresh != nil) follows \(blyg.studioFollows?.count ?? -1)"
        }
    }

    // MARK: Once per refresh

    @Test func refreshingEveryBlygRebuildsTheTimelineOnceAndSavesOnce() async throws {
        let f = try await following()
        defer { f.store.removeFiles() }
        f.fetcher.publish("8a8a8a8a8a8a8a8a8a8a8a8a8a", on: "second")
        f.fetcher.publish("9b9b9b9b9b9b9b9b9b9b9b9b9b", on: "third")
        f.fetcher.set("https://fourth.example/blyg.json", .init(status: 500, body: "")) // a failure is saved too
        let saves = f.store.saves
        let slow = f.fetcher.hold("https://third.example/blyg.json") // blygs answer at different times

        let refresh = Task { await f.model.refreshAll() }
        await until { f.model.refreshing == [Self.origin("third")] }
        // Three blygs are in, one with a new post, and nothing has been rebuilt or written for them yet.
        #expect(f.model.blyg(Self.origin("second"))?.items.count == 1)
        #expect(f.timeline.builds == 0)
        #expect(f.store.saves == saves)
        slow.release()
        await refresh.value
        await f.model.saveFinished()

        #expect(!slow.gaveUp)
        #expect(f.timeline.builds == 1)
        #expect(f.store.saves == saves + 1)
        // Nothing was lost by waiting: both new posts are showing, and the file holds what the model does.
        #expect(f.model.timeline == f.model.library.timeline())
        #expect(Set(f.model.timeline.map(\.document.id)).isSuperset(of: ["8a8a8a8a8a8a8a8a8a8a8a8a8a", "9b9b9b9b9b9b9b9b9b9b9b9b9b"]))
        #expect(f.model.blyg(Self.origin("fourth"))?.lastError == "Its blyg.json answered 500.")
        #expect(digest(f.store.load().0) == digest(f.model.library))
        #expect(!f.model.isRefreshingAny)
    }

    @Test func comingBackRefreshesStaleBlygsWithOneRebuildAndOneSave() async throws {
        let f = try await following()
        defer { f.store.removeFiles() }
        f.fetcher.publish("8a8a8a8a8a8a8a8a8a8a8a8a8a", on: "second")
        let saves = f.store.saves
        let slow = f.fetcher.hold("https://third.example/blyg.json")

        let refresh = Task { await f.model.refreshStale(now: .now.addingTimeInterval(20 * 60)) }
        await until { f.model.refreshing == [Self.origin("third")] }
        #expect(f.timeline.builds == 0)
        #expect(f.store.saves == saves)
        slow.release()
        await refresh.value
        await f.model.saveFinished()

        #expect(!slow.gaveUp)
        #expect(f.timeline.builds == 1)
        #expect(f.store.saves == saves + 1)
        #expect(f.model.timeline.contains { $0.document.id == "8a8a8a8a8a8a8a8a8a8a8a8a8a" })
        #expect(digest(f.store.load().0) == digest(f.model.library))
    }

    @Test func oneBlygRefreshedAloneIsShownAndSavedByTheTimeItReturns() async throws {
        let f = try await following()
        defer { f.store.removeFiles() }
        f.fetcher.publish("8a8a8a8a8a8a8a8a8a8a8a8a8a", on: "second")
        let saves = f.store.saves

        await f.model.refresh(Self.origin("second"))
        #expect(f.model.timeline.contains { $0.document.id == "8a8a8a8a8a8a8a8a8a8a8a8a8a" }) // no waiting needed
        await f.model.saveFinished()

        #expect(f.timeline.builds == 1)
        #expect(f.store.saves == saves + 1)
        #expect(digest(f.store.load().0) == digest(f.model.library))
    }

    // MARK: The main actor stays free

    @Test func slowFetchingAndDecodingDoNotHoldTheMainActor() async throws {
        let f = try await following()
        defer { f.store.removeFiles() }
        #expect(!f.fetcher.askedOnMainThread) // adding a blyg: the resolver and the first sync
        let hold = f.fetcher.hold("https://second.example/items/index.json")

        let refresh = Task { await f.model.refreshAll() }
        // This test is on the main actor. If the sync were too, the hold would block the next line until it gave up.
        await until { hold.wasReached }
        hold.release()
        await refresh.value
        await f.model.saveFinished()

        #expect(!hold.gaveUp)
        #expect(!f.fetcher.askedOnMainThread)
    }

    @Test func aSlowSaveDoesNotHoldTheMainActor() async throws {
        let f = try await following()
        defer { f.store.removeFiles() }
        let hold = f.store.holdNextSave()

        f.model.disconnect(Self.origin("second")) // any change made on the main actor: it saves
        await until { hold.wasReached }
        hold.release()
        await f.model.saveFinished()

        #expect(!hold.gaveUp)
        #expect(!f.store.savedOnMainThread)
    }

    @Test func aSlowTimelineRebuildDoesNotHoldTheMainActorAndTheSpinnerWaitsForIt() async throws {
        let f = try await following()
        defer { f.store.removeFiles() }
        f.fetcher.publish("8a8a8a8a8a8a8a8a8a8a8a8a8a", on: "second")
        let hold = f.timeline.holdNextBuild()

        let refresh = Task { await f.model.refreshAll() }
        await until { hold.wasReached }
        // Every blyg has answered but the new posts aren't in place yet: still "updating", never "No posts yet".
        #expect(f.model.refreshing.isEmpty)
        #expect(f.model.isRefreshingAny)
        hold.release()
        await refresh.value
        await f.model.saveFinished()

        #expect(!hold.gaveUp)
        #expect(!f.timeline.builtOnMainThread)
        #expect(f.model.timeline.contains { $0.document.id == "8a8a8a8a8a8a8a8a8a8a8a8a8a" })
    }

    // MARK: Nothing lost

    @Test func changesMadeDuringASaveGetOneMoreSaveAndNoneAreLost() async throws {
        let f = try await following()
        defer { f.store.removeFiles() }
        let saves = f.store.saves
        let hold = f.store.holdNextSave()

        f.model.disconnect(Self.origin("second"))
        await until { hold.wasReached } // the first write is under way, with the library as it was
        f.model.remove(Self.origin("third"))
        f.model.remove(Self.origin("fourth"))
        f.model.disconnect(Self.origin("second"))
        hold.release()
        await f.model.saveFinished()

        #expect(f.store.saves == saves + 2) // three changes, one more write
        #expect(f.store.load().0.blygs.map(\.origin) == [Fixtures.origin, Self.origin("second")])
        #expect(digest(f.store.load().0) == digest(f.model.library))
    }

    @Test func leavingTheAppMidRefreshSavesWhatHasArrivedThenEachBlygAsItArrives() async throws {
        let f = try await following()
        defer { f.store.removeFiles() }
        f.fetcher.publish("8a8a8a8a8a8a8a8a8a8a8a8a8a", on: "second")
        f.fetcher.publish("9b9b9b9b9b9b9b9b9b9b9b9b9b", on: "third")
        let saves = f.store.saves
        let slow = f.fetcher.hold("https://third.example/blyg.json")

        let refresh = Task { await f.model.refreshAll() }
        await until { f.model.refreshing == [Self.origin("third")] } // the others are in; third is still out
        #expect(f.store.saves == saves) // held back for the end of the refresh

        f.model.enteredBackground()
        await f.model.saveFinished()
        #expect(f.store.saves == saves + 1) // ...but not once the app may be suspended
        #expect(f.store.load().0.blygs.first { $0.origin == Self.origin("second") }?.items.count == 1)
        #expect(digest(f.store.load().0) == digest(f.model.library))

        slow.release()
        await refresh.value
        await f.model.saveFinished()
        #expect(!slow.gaveUp)
        #expect(f.store.saves == saves + 2) // third was saved as it arrived; the end had nothing left to save
        #expect(f.store.load().0.blygs.first { $0.origin == Self.origin("third") }?.items.count == 1)
        #expect(digest(f.store.load().0) == digest(f.model.library))

        f.model.becameActive() // back on screen: one save per refresh again
        await f.model.refreshAll()
        await f.model.saveFinished()
        #expect(f.store.saves == saves + 3)
    }

    @Test func aBlygUnfollowedDuringARebuildStaysOutOfTheTimeline() async throws {
        let f = try await following()
        defer { f.store.removeFiles() }
        f.fetcher.publish("8a8a8a8a8a8a8a8a8a8a8a8a8a", on: "second")
        await f.model.refreshAll()
        #expect(f.model.timeline.contains { $0.origin == Self.origin("second") })
        f.fetcher.publish("9b9b9b9b9b9b9b9b9b9b9b9b9b", on: "third")
        let hold = f.timeline.holdNextBuild()

        let refresh = Task { await f.model.refresh(Self.origin("third")) }
        await until { hold.wasReached } // this rebuild's copy of the library still has "second" in it
        f.model.remove(Self.origin("second"))
        #expect(!f.model.timeline.contains { $0.origin == Self.origin("second") }) // gone at once
        hold.release()
        await refresh.value
        await f.model.saveFinished()

        #expect(!f.model.timeline.contains { $0.origin == Self.origin("second") })
        #expect(f.model.timeline == f.model.library.timeline())
    }

    @Test func aChangeDuringARebuildGetsOneMorePassSoTheNewestLibraryWins() async throws {
        let f = try await following()
        defer { f.store.removeFiles() }
        f.fetcher.publish("8a8a8a8a8a8a8a8a8a8a8a8a8a", on: "second")
        f.fetcher.publish("9b9b9b9b9b9b9b9b9b9b9b9b9b", on: "third")
        let hold = f.timeline.holdNextBuild()

        let first = Task { await f.model.refresh(Self.origin("second")) }
        await until { hold.wasReached } // rebuilding from a library that hasn't got third's post
        let second = Task { await f.model.refresh(Self.origin("third")) }
        await until { f.model.blyg(Self.origin("third"))?.items.isEmpty == false }
        hold.release()
        await first.value
        await second.value
        await f.model.saveFinished()

        #expect(f.timeline.builds == 2)
        #expect(f.model.timeline == f.model.library.timeline())
        #expect(f.model.timeline.contains { $0.document.id == "9b9b9b9b9b9b9b9b9b9b9b9b9b" })
    }
}

extension FakeFetcher {
    /// Gives a blyg (`second.example` and the like) one fragment, as its only item.
    func publish(_ id: String, on host: String) {
        set("https://\(host).example/items/index.json", .init(body: """
            {"items":[{"id":"\(id)","kind":"fragment","created":"2026-11-20T08:00:00Z","updated":"2026-11-20T08:00:00Z","version":1}]}
            """))
        set("https://\(host).example/items/\(id).json", .init(body: """
            {"blyg":"0.4","id":"\(id)","kind":"fragment","origin":"https://\(host).example/","page":"f/\(id)/",\
            "created":"2026-11-20T08:00:00Z","updated":"2026-11-20T08:00:00Z","version":1,\
            "content_md":"A post on \(host).","content_html":"<p>A post on \(host).</p>","media":[],\
            "changelog":[{"version":1,"at":"2026-11-20T08:00:00Z","note":null}]}
            """))
    }
}
