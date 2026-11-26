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
    func following(tokens: any TokenStore = MemoryTokenStore(), transport: FakeTransport = FakeTransport([:])) async throws -> Following {
        let fetcher = FakeFetcher.sample()
        for host in Self.hosts + ["fifth"] { // "fifth" is there to be found, but not followed
            fetcher.set("https://\(host).example/blyg.json", .init(body: #"{"blyg":"0.4","title":"\#(host)"}"#))
            fetcher.set("https://\(host).example/items/index.json", .init(body: #"{"items":[]}"#))
        }
        let store = CountingStore()
        let timeline = TimelineCounter()
        let model = LibraryModel(store: store, fetcher: fetcher, tokens: tokens, transport: transport,
                                 buildTimeline: { timeline.build($0) })
        for host in ["sample"] + Self.hosts { try await model.add("\(host).example") }
        await model.saveFinished()
        timeline.reset()
        return Following(model: model, fetcher: fetcher, store: store, timeline: timeline)
    }

    /// A Studio at `host` that accepts any token and follows the blygs at `follows`.
    static func studio(_ host: String, follows: [String] = []) -> [String: (Int, String)] {
        ["GET https://\(host).example/api/capabilities": (200, SandboxResponses.capabilities.replacingOccurrences(of: "blyg-sandbox.exe.xyz", with: "\(host).example")),
         "GET https://\(host).example/api/subscriptions": (200, subscriptions(follows))]
    }

    static func subscriptions(_ hosts: [String]) -> String {
        #"{"items":["# + hosts.map { #"{"kind":"blyg","origin":"https://\#($0).example/","title":"T"}"# }.joined(separator: ",")
            + #"],"page":{"limit":100,"nextCursor":null}}"#
    }

    /// When each blyg last answered, to tell later which have answered since.
    func answers(_ f: Following) -> [URL: Date] {
        Dictionary(uniqueKeysWithValues: f.model.library.blygs.compactMap { blyg in blyg.lastRefresh.map { (blyg.origin, $0) } })
    }

    /// True once `held`'s request is being held and every other blyg has answered since `before`. Just
    /// "only `held` is refreshing" isn't enough: that's also so if `held` happens to be the first to start.
    func onlyStillOut(_ held: String, _ hold: Hold, _ f: Following, since before: [URL: Date]) -> Bool {
        hold.wasReached && f.model.refreshing == [Self.origin(held)]
            && f.model.library.blygs.allSatisfy { blyg in
                blyg.origin == Self.origin(held) || blyg.lastError != nil || blyg.lastRefresh != before[blyg.origin]
            }
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
        let before = answers(f)
        let slow = f.fetcher.hold("https://third.example/blyg.json") // blygs answer at different times

        let refresh = Task { await f.model.refreshAll() }
        await until { onlyStillOut("third", slow, f, since: before) }
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
        let before = answers(f)
        let slow = f.fetcher.hold("https://third.example/blyg.json")

        let refresh = Task { await f.model.refreshStale(now: .now.addingTimeInterval(20 * 60)) }
        await until { onlyStillOut("third", slow, f, since: before) }
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

    @Test func oneBlygRefreshedAloneIsShownWhenItReturnsAndSavedOnce() async throws {
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

    /// The fetcher is the probe for the decoding too. `Syncer.refresh` asks it before and after each decode, from
    /// one function body that is either on the main actor throughout or (`@concurrent`) never: so a request seen
    /// off the main thread means the decoding between requests was off it as well.
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
        let before = answers(f)
        let slow = f.fetcher.hold("https://third.example/blyg.json")

        let refresh = Task { await f.model.refreshAll() }
        await until { onlyStillOut("third", slow, f, since: before) } // the others are in; third is still out
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

    @Test func aBlygUnfollowedDuringARebuildAndFollowedAgainDoesNotGetItsOldPostsBack() async throws {
        let f = try await following()
        defer { f.store.removeFiles() }
        f.fetcher.publish("8a8a8a8a8a8a8a8a8a8a8a8a8a", on: "second")
        await f.model.refreshAll()
        f.fetcher.publish("9b9b9b9b9b9b9b9b9b9b9b9b9b", on: "third")
        let hold = f.timeline.holdNextBuild()

        let refresh = Task { await f.model.refresh(Self.origin("third")) }
        await until { hold.wasReached } // this rebuild's copy of the library has "second" and its post
        f.model.remove(Self.origin("second"))
        f.fetcher.set("https://second.example/items/index.json", .init(status: 500, body: "")) // followed again, but its posts can't be read
        try await f.model.add("second.example")
        #expect(f.model.blyg(Self.origin("second"))?.items.isEmpty == true)
        hold.release()
        await refresh.value
        await f.model.saveFinished()

        #expect(!f.model.timeline.contains { $0.origin == Self.origin("second") })
        #expect(f.model.timeline == f.model.library.timeline())
    }

    @Test func aRefreshRunningAlongsideDoesNotFinishAnothersWorkEarly() async throws {
        // "third" is this phone's own blyg, so coming back to the app refreshes it after 30 s and the others after 10 minutes.
        let f = try await following(transport: FakeTransport(Self.studio("third")))
        defer { f.store.removeFiles() }
        try await f.model.connect(Self.origin("third"), token: "secret")
        await f.model.saveFinished()
        f.fetcher.publish("8a8a8a8a8a8a8a8a8a8a8a8a8a", on: "second")
        let saves = f.store.saves
        let before = answers(f)
        let slow = f.fetcher.hold("https://third.example/blyg.json")

        let launch = Task { await f.model.refreshAll() }
        await until { onlyStillOut("third", slow, f, since: before) }
        // Coming back now picks only "third", which is already being refreshed: this refresh has nothing of its own to finish.
        await f.model.refreshStale(now: .now.addingTimeInterval(45))
        #expect(f.timeline.builds == 0)
        #expect(f.store.saves == saves)
        slow.release()
        await launch.value
        await f.model.saveFinished()

        #expect(f.timeline.builds == 1)
        #expect(f.store.saves == saves + 1)
        #expect(f.model.timeline.contains { $0.document.id == "8a8a8a8a8a8a8a8a8a8a8a8a8a" })
        #expect(digest(f.store.load().0) == digest(f.model.library))
    }

    @Test func aFailedWriteIsTriedAgainOnLeavingTheApp() async throws {
        let f = try await following()
        defer { f.store.removeFiles() }
        f.store.failNextSave()

        f.model.remove(Self.origin("fourth"))
        await f.model.saveFinished()
        #expect(f.store.load().0.blygs.count == 4) // the write failed: the file still has all four

        f.model.enteredBackground()
        await f.model.saveFinished()
        #expect(f.store.load().0.blygs.count == 3)
        #expect(digest(f.store.load().0) == digest(f.model.library))
    }

    // MARK: A connected Studio

    @Test func aStudiosNewFollowIsRememberedOnlyOnceItHasBeenTried() async throws {
        let transport = FakeTransport(Self.studio("sample", follows: ["second"]))
        let f = try await following(transport: transport)
        defer { f.store.removeFiles() }
        try await f.model.connect(Fixtures.origin, token: "secret")
        _ = try await f.model.importSubscriptions(from: Fixtures.origin)
        #expect(f.model.blyg(Fixtures.origin)?.studioFollows == [Self.origin("second")])
        transport.set("GET https://sample.example/api/subscriptions", (200, Self.subscriptions(["second", "fifth"])))
        let slow = f.fetcher.hold("https://fifth.example/blyg.json")

        let refresh = Task { await f.model.refresh(Fixtures.origin) }
        await until { slow.wasReached } // "fifth" is being added
        // The app is closed here. The saved list mustn't say "fifth" has been seen, or it would never be followed.
        f.model.enteredBackground()
        await f.model.saveFinished()
        #expect(f.store.load().0.blygs.first?.studioFollows == [Self.origin("second")])
        #expect(f.store.load().0.blygs.count == 4)

        slow.release()
        await refresh.value
        await f.model.saveFinished()
        #expect(!slow.gaveUp)
        #expect(f.model.blyg(Self.origin("fifth")) != nil)
        #expect(f.store.load().0.blygs.first?.studioFollows == [Self.origin("second"), Self.origin("fifth")])
        #expect(f.store.load().0.blygs.count == 5)
    }

    @Test func aConnectedBlygCostsNoKeychainReadsToDrawAndItsStudioIsReadOffTheMainActor() async throws {
        let tokens = CountingTokens()
        let transport = FakeTransport(Self.studio("sample", follows: ["second"]))
        let f = try await following(tokens: tokens, transport: transport)
        defer { f.store.removeFiles() }
        try await f.model.connect(Fixtures.origin, token: "secret")
        _ = try await f.model.importSubscriptions(from: Fixtures.origin)

        // What views ask on every redraw, and what coming back to the app asks: answered from memory.
        let reads = tokens.reads
        #expect(f.model.postingBlygs.map(\.origin) == [Fixtures.origin])
        #expect(f.model.isConnected(Fixtures.origin))
        #expect(!f.model.isConnected(Self.origin("second")))
        await f.model.refreshStale(now: .now) // nothing is stale yet
        #expect(tokens.reads == reads)

        await f.model.refreshAll() // asks the Studio what it follows
        await f.model.saveFinished()
        #expect(transport.keys.filter { $0.hasSuffix("/subscriptions") }.count == 2)
        #expect(!transport.keysSentOnMainThread.contains { $0.hasSuffix("/subscriptions") })

        f.model.disconnect(Fixtures.origin)
        #expect(f.model.postingBlygs.isEmpty)
        await f.model.saveFinished()
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
