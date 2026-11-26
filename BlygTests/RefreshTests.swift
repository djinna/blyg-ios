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
    /// `pace`: the least time between timeline rebuilds while blygs arrive. A minute unless a test says otherwise,
    /// so no rebuild comes before the end of a refresh and the counts don't depend on how fast the tests run.
    func following(pace: Duration = .seconds(60), tokens: any TokenStore = MemoryTokenStore(),
                   transport: FakeTransport = FakeTransport([:])) async throws -> Following {
        let fetcher = FakeFetcher.sample()
        for host in Self.hosts + ["fifth"] { // "fifth" is there to be found, but not followed
            fetcher.set("https://\(host).example/blyg.json", .init(body: #"{"blyg":"0.4","title":"\#(host)"}"#))
            fetcher.set("https://\(host).example/items/index.json", .init(body: #"{"items":[]}"#))
        }
        let store = CountingStore()
        let timeline = TimelineCounter()
        let model = LibraryModel(store: store, fetcher: fetcher, tokens: tokens, transport: transport,
                                 buildTimeline: { timeline.build($0) }, timelinePace: pace)
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
    func onlyStillOut(_ held: String, _ gate: Gate, _ f: Following, since before: [URL: Date]) -> Bool {
        onlyStillOut([held], [gate], f, since: before)
    }

    func onlyStillOut(_ held: [String], _ gates: [Gate], _ f: Following, since before: [URL: Date]) -> Bool {
        let out = Set(held.map(Self.origin))
        return gates.allSatisfy(\.wasReached) && f.model.refreshing == out
            && f.model.library.blygs.allSatisfy { blyg in
                out.contains(blyg.origin) || blyg.lastError != nil || blyg.lastRefresh != before[blyg.origin]
            }
    }

    /// Where an array keeps its elements: the same before and after means it wasn't replaced.
    func storage(_ rows: [TimelineEntry]) -> UnsafeRawPointer? {
        rows.withUnsafeBufferPointer { UnsafeRawPointer($0.baseAddress) }
    }

    final class Flag: @unchecked Sendable { var isSet = false }

    /// Where the saved file differs from the model: empty when everything is saved. Not `==` on the two
    /// libraries, because saved dates drop their fractions of a second; so dates may differ by up to a second.
    func unsaved(_ f: Following) -> [String] {
        let (saved, live) = (f.store.load().0, f.model.library)
        guard saved.blygs.map(\.origin) == live.blygs.map(\.origin) else {
            return ["blygs: saved \(saved.blygs.map(\.origin.absoluteString)), in the model \(live.blygs.map(\.origin.absoluteString))"]
        }
        func near(_ a: Date?, _ b: Date?) -> Bool {
            guard let a, let b else { return a == nil && b == nil }
            return abs(a.timeIntervalSince(b)) <= 1
        }
        var differences: [String] = []
        for (a, b) in zip(saved.blygs, live.blygs) {
            let name = b.origin.host() ?? b.origin.absoluteString
            if a.manifest != b.manifest { differences.append("\(name): manifest") }
            if a.lastError != b.lastError { differences.append("\(name): error \(a.lastError ?? "none") / \(b.lastError ?? "none")") }
            if !near(a.lastRefresh, b.lastRefresh) { differences.append("\(name): last refresh") }
            if a.postingAPI != b.postingAPI { differences.append("\(name): posting API") }
            if a.studioFollows != b.studioFollows { differences.append("\(name): Studio follows") }
            if Set(a.items.keys) != Set(b.items.keys) { differences.append("\(name): items \(a.items.keys.sorted()) / \(b.items.keys.sorted())") }
            for (id, item) in b.items {
                guard let other = a.items[id] else { continue }
                if other.version != item.version || other.kind != item.kind || other.document != item.document
                    || !near(other.versionSeenAt, item.versionSeenAt) { differences.append("\(name): item \(id)") }
            }
        }
        return differences
    }

    // MARK: One save per refresh, and rebuilds at a pace

    @Test func refreshingEveryBlygSavesOnceAndRebuildsNoFasterThanThePace() async throws {
        let f = try await following()
        defer { f.store.removeFiles() }
        f.fetcher.publish("8a8a8a8a8a8a8a8a8a8a8a8a8a", on: "second")
        f.fetcher.publish("9b9b9b9b9b9b9b9b9b9b9b9b9b", on: "third")
        f.fetcher.set("https://fourth.example/blyg.json", .init(status: 500, body: "")) // a failure is saved too
        let saves = f.store.saves
        let before = answers(f)
        let slow = f.fetcher.delay("https://third.example/blyg.json") // blygs answer at different times

        let refresh = Task { await f.model.refreshAll() }
        await until { onlyStillOut("third", slow, f, since: before) }
        // Three blygs are in, one with a new post. The last rebuild was under a minute ago, so none has started
        // for them (a rebuild per blyg would have); and nothing is written until the end.
        #expect(f.model.blyg(Self.origin("second"))?.items.count == 1)
        #expect(f.timeline.builds == 0)
        #expect(f.store.saves == saves)
        let released = ContinuousClock.now
        slow.release()
        await refresh.value
        #expect(ContinuousClock.now - released < .seconds(10)) // the end of the refresh doesn't wait out the minute
        await f.model.saveFinished()

        #expect(f.timeline.builds == 1)
        #expect(f.store.saves == saves + 1)
        // Nothing was lost by waiting: both new posts are showing, and the file holds what the model does.
        #expect(f.model.timeline == f.model.library.timeline())
        #expect(Set(f.model.timeline.map(\.document.id)).isSuperset(of: ["8a8a8a8a8a8a8a8a8a8a8a8a8a", "9b9b9b9b9b9b9b9b9b9b9b9b9b"]))
        #expect(f.model.blyg(Self.origin("fourth"))?.lastError == "Its blyg.json answered 500.")
        #expect(unsaved(f) == [])
        #expect(!f.model.isRefreshingAny)
    }

    @Test func postsFromAFastBlygShowBeforeASlowOneAnswers() async throws {
        let f = try await following(pace: .milliseconds(20))
        defer { f.store.removeFiles() }
        f.fetcher.publish("8a8a8a8a8a8a8a8a8a8a8a8a8a", on: "second")
        f.fetcher.publish("9b9b9b9b9b9b9b9b9b9b9b9b9b", on: "third")
        let saves = f.store.saves
        let slow = f.fetcher.delay("https://third.example/blyg.json")

        let refresh = Task { await f.model.refreshAll() }
        await until { f.model.timeline.contains { $0.document.id == "8a8a8a8a8a8a8a8a8a8a8a8a8a" } }
        // second's post is showing while third is still out and the refresh still running...
        #expect(f.model.blyg(Self.origin("third"))?.items.isEmpty == true)
        #expect(f.model.isRefreshingAny)
        #expect(f.store.saves == saves) // ...and the file still waits for the end
        slow.release()
        await refresh.value
        await f.model.saveFinished()

        #expect(f.model.timeline == f.model.library.timeline())
        #expect(f.model.timeline.contains { $0.document.id == "9b9b9b9b9b9b9b9b9b9b9b9b9b" })
        #expect(f.store.saves == saves + 1)
        #expect((2...4).contains(f.timeline.builds)) // one while third was out, one at the end; never more than one per blyg
        #expect(!f.timeline.builtOnMainThread)
    }

    @Test func blygsThatArriveDuringARebuildShareTheNextOne() async throws {
        let f = try await following(pace: .zero) // no waiting between rebuilds: only a rebuild under way holds the next back
        defer { f.store.removeFiles() }
        let ids = ["second": "8a8a8a8a8a8a8a8a8a8a8a8a8a", "third": "9b9b9b9b9b9b9b9b9b9b9b9b9b", "fourth": "7c7c7c7c7c7c7c7c7c7c7c7c7c"]
        for (host, id) in ids { f.fetcher.publish(id, on: host) }
        func showing(_ host: String) -> Bool { f.model.timeline.contains { $0.document.id == ids[host] } }
        func arrived(_ host: String) -> Bool { f.model.blyg(Self.origin(host))?.items.count == 1 }
        let saves = f.store.saves
        let gates = Dictionary(uniqueKeysWithValues: Self.hosts.map { ($0, f.fetcher.delay("https://\($0).example/blyg.json")) })
        let build = f.timeline.holdNextBuild()

        let refresh = Task { await f.model.refreshAll() }
        await until { build.wasReached } // the sample blyg has arrived and its rebuild is under way
        gates["second"]?.release()
        gates["third"]?.release()
        await until { arrived("second") && arrived("third") }
        #expect(f.timeline.builds == 1) // both wait for the rebuild under way to finish
        build.release()
        await until { showing("second") && showing("third") }
        #expect(f.timeline.builds == 2) // ...and then share one
        #expect(!showing("fourth"))
        #expect(f.store.saves == saves)
        gates["fourth"]?.release()
        await refresh.value
        await f.model.saveFinished()

        #expect(!build.gaveUp)
        #expect(showing("fourth"))
        #expect(f.timeline.builds == 3) // four blygs, three rebuilds
        #expect(f.store.saves == saves + 1)
        #expect(!f.timeline.builtOnMainThread)
        #expect(f.model.timeline == f.model.library.timeline())
    }

    @Test func aPacedRebuildWaitsOutThePaceFromTheEndOfTheLastRebuild() async throws {
        let pace = Duration.milliseconds(200)
        let f = try await following(pace: pace)
        defer { f.store.removeFiles() }
        f.fetcher.publish("8a8a8a8a8a8a8a8a8a8a8a8a8a", on: "second")
        let gates = Dictionary(uniqueKeysWithValues: Self.hosts.map { ($0, f.fetcher.delay("https://\($0).example/blyg.json")) })
        let build = f.timeline.holdNextBuild()

        let refresh = Task { await f.model.refreshAll() }
        await until { build.wasReached } // the sample blyg's rebuild is under way...
        gates["second"]?.release()
        await until { f.model.blyg(Self.origin("second"))?.items.count == 1 }
        try await Task.sleep(for: pace + .milliseconds(50)) // ...and takes longer than the pace
        build.release()
        await until { f.model.timeline.contains { $0.document.id == "8a8a8a8a8a8a8a8a8a8a8a8a8a" } }

        // second's rebuild didn't start the moment the long one ended, though the pace had passed since that one started.
        let spans = f.timeline.spans
        #expect(spans.count == 2)
        if spans.count == 2 { #expect(spans[1].start - spans[0].end >= pace) }
        gates["third"]?.release()
        gates["fourth"]?.release()
        await refresh.value
        await f.model.saveFinished()
        #expect(!build.gaveUp)
    }

    @Test func aPacedRebuildCoveredByAnotherDoesNotComeBackEarly() async throws {
        let pace = Duration.seconds(1)
        let f = try await following(pace: pace) // the last rebuild was just now: the next paced one is a second away
        defer { f.store.removeFiles() }
        f.fetcher.publish("8a8a8a8a8a8a8a8a8a8a8a8a8a", on: "second")
        f.fetcher.publish("9b9b9b9b9b9b9b9b9b9b9b9b9b", on: "third")
        let before = answers(f)
        let third = f.fetcher.delay("https://third.example/blyg.json")
        let fourth = f.fetcher.delay("https://fourth.example/blyg.json")

        let refresh = Task { await f.model.refreshAll() }
        await until { onlyStillOut(["third", "fourth"], [third, fourth], f, since: before) } // second's post waits for the pace
        try await Task.sleep(for: .milliseconds(300))
        #expect(f.timeline.builds == 0)
        await f.model.refresh(Fixtures.origin) // a refresh of one blyg rebuilds at once, and takes second's post along
        #expect(f.timeline.builds == 1)
        #expect(f.model.timeline.contains { $0.document.id == "8a8a8a8a8a8a8a8a8a8a8a8a8a" })
        third.release() // third's post now waits a full pace from that rebuild, not what was left of the first wait
        await until { f.model.timeline.contains { $0.document.id == "9b9b9b9b9b9b9b9b9b9b9b9b9b" } }

        let spans = f.timeline.spans
        #expect(spans.count == 2)
        if spans.count == 2 { #expect(spans[1].start - spans[0].end >= pace) }
        fourth.release()
        await refresh.value
        await f.model.saveFinished()
    }

    @Test func theFirstBlygsToAnswerAfterOpeningWaitOutThePaceToo() async throws {
        let f = try await following()
        defer { f.store.removeFiles() }
        f.fetcher.publish("8a8a8a8a8a8a8a8a8a8a8a8a8a", on: "second")
        // The app opens again: a new model on the same file, which builds its timeline once as it starts.
        let timeline = TimelineCounter()
        let reopened = LibraryModel(store: f.store, fetcher: f.fetcher, buildTimeline: { timeline.build($0) }, timelinePace: .seconds(60))
        #expect(reopened.library.blygs.count == 4)
        timeline.reset()
        let slow = f.fetcher.delay("https://third.example/blyg.json")

        let refresh = Task { await reopened.refreshAll() }
        await until { slow.wasReached && reopened.refreshing == [Self.origin("third")] && reopened.blyg(Self.origin("second"))?.items.count == 1 }
        #expect(timeline.builds == 0) // not a second build right behind the opening one
        slow.release()
        await refresh.value
        await reopened.saveFinished()
        #expect(timeline.builds == 1)
        #expect(reopened.timeline.contains { $0.document.id == "8a8a8a8a8a8a8a8a8a8a8a8a8a" })
    }

    @Test func viewsAreToldWhenTheTimelineChanges() async throws {
        let f = try await following()
        defer { f.store.removeFiles() }
        f.fetcher.publish("8a8a8a8a8a8a8a8a8a8a8a8a8a", on: "second")
        let rebuilt = Flag()
        withObservationTracking { _ = f.model.timeline } onChange: { rebuilt.isSet = true }
        await f.model.refreshAll()
        #expect(rebuilt.isSet)

        let unfollowed = Flag()
        withObservationTracking { _ = f.model.timeline } onChange: { unfollowed.isSet = true }
        f.model.remove(Self.origin("second"))
        #expect(unfollowed.isSet)
        await f.model.saveFinished()
    }

    @Test func comingBackRefreshesStaleBlygsWithOneSaveAndRebuildsAtThePace() async throws {
        let f = try await following()
        defer { f.store.removeFiles() }
        f.fetcher.publish("8a8a8a8a8a8a8a8a8a8a8a8a8a", on: "second")
        let saves = f.store.saves
        let before = answers(f)
        let slow = f.fetcher.delay("https://third.example/blyg.json")

        let refresh = Task { await f.model.refreshStale(now: .now.addingTimeInterval(20 * 60)) }
        await until { onlyStillOut("third", slow, f, since: before) }
        #expect(f.timeline.builds == 0)
        #expect(f.store.saves == saves)
        slow.release()
        await refresh.value
        await f.model.saveFinished()

        #expect(f.timeline.builds == 1)
        #expect(f.store.saves == saves + 1)
        #expect(f.model.timeline.contains { $0.document.id == "8a8a8a8a8a8a8a8a8a8a8a8a8a" })
        #expect(unsaved(f) == [])
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
        #expect(unsaved(f) == [])
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
        #expect(unsaved(f) == [])
    }

    @Test func leavingTheAppMidRefreshSavesWhatHasArrivedThenEachBlygAsItArrives() async throws {
        let f = try await following()
        defer { f.store.removeFiles() }
        for (id, host) in [("8a8a8a8a8a8a8a8a8a8a8a8a8a", "second"), ("9b9b9b9b9b9b9b9b9b9b9b9b9b", "third"), ("7c7c7c7c7c7c7c7c7c7c7c7c7c", "fourth")] {
            f.fetcher.publish(id, on: host)
        }
        let saves = f.store.saves
        let before = answers(f)
        let slow = f.fetcher.delay("https://third.example/blyg.json")
        let slower = f.fetcher.delay("https://fourth.example/blyg.json")
        func saved(_ host: String) -> Int? { f.store.load().0.blygs.first { $0.origin == Self.origin(host) }?.items.count }

        let refresh = Task { await f.model.refreshAll() }
        await until { onlyStillOut(["third", "fourth"], [slow, slower], f, since: before) } // two are in, two still out
        #expect(f.store.saves == saves) // held back for the end of the refresh

        f.model.enteredBackground()
        await f.model.saveFinished()
        #expect(f.store.saves == saves + 1) // ...but not once the app may be suspended
        #expect(saved("second") == 1)
        #expect(unsaved(f) == [])

        slow.release()
        await until { f.model.blyg(Self.origin("third"))?.items.count == 1 }
        await f.model.saveFinished()
        #expect(f.model.refreshing == [Self.origin("fourth")]) // the refresh hasn't ended,
        #expect(f.store.saves == saves + 2)                    // and third is saved already
        #expect(saved("third") == 1)
        #expect(saved("fourth") == 0)

        slower.release()
        await refresh.value
        await f.model.saveFinished()
        #expect(f.store.saves == saves + 3) // fourth was saved as it arrived; the end had nothing left to save
        #expect(saved("fourth") == 1)
        #expect(unsaved(f) == [])

        f.model.becameActive() // back on screen: one save per refresh again
        await f.model.refreshAll()
        await f.model.saveFinished()
        #expect(f.store.saves == saves + 4)
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
        let slow = f.fetcher.delay("https://third.example/blyg.json")

        let launch = Task { await f.model.refreshAll() }
        await until { onlyStillOut("third", slow, f, since: before) }
        // Coming back now picks only "third", which is already being refreshed: this refresh has nothing of its own to finish.
        let back = Flag()
        Task {
            await f.model.refreshStale(now: .now.addingTimeInterval(45))
            back.isSet = true
        }
        await until { back.isSet } // with a deadline: if it waited for "third", this test would otherwise never end
        #expect(f.timeline.builds == 0)
        #expect(f.store.saves == saves)
        slow.release()
        await launch.value
        await f.model.saveFinished()

        #expect(f.timeline.builds == 1)
        #expect(f.store.saves == saves + 1)
        #expect(f.model.timeline.contains { $0.document.id == "8a8a8a8a8a8a8a8a8a8a8a8a8a" })
        #expect(unsaved(f) == [])
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
        #expect(unsaved(f) == [])
    }

    @Test func aWriteThatFailsWhileTheAppIsInTheBackgroundIsTriedAgainAtOnce() async throws {
        let f = try await following()
        defer { f.store.removeFiles() }
        let saves = f.store.saves
        let hold = f.store.holdNextSave()
        f.store.failNextSave()

        f.model.remove(Self.origin("fourth"))
        await until { hold.wasReached } // the write is under way
        f.model.enteredBackground()     // nothing held back and nothing known to have failed: nothing to do yet
        hold.release()                  // ...and now the write fails
        await f.model.saveFinished()

        #expect(f.store.saves == saves + 2)
        #expect(f.store.load().0.blygs.count == 3)
    }

    @Test func eachWriteThatFailsInTheBackgroundGetsARetryOfItsOwn() async throws {
        let f = try await following()
        defer { f.store.removeFiles() }
        let saves = f.store.saves
        f.store.failSave(1)              // the first write fails,
        let retry = f.store.holdSave(2)  // its retry works, but is slow,
        f.store.failSave(3)              // and the write after that fails too
        f.model.enteredBackground()

        f.model.remove(Self.origin("fourth"))
        await until { retry.wasReached }
        f.model.remove(Self.origin("third")) // a change during the retry: the same writer goes round again
        retry.release()
        await f.model.saveFinished()

        #expect(!retry.gaveUp)
        #expect(f.store.saves == saves + 4)
        #expect(f.store.load().0.blygs.count == 2)
        #expect(unsaved(f) == [])
    }

    @Test func aSaveAlreadyWaitingItsTurnCoversARefreshThatHasNothingMoreToAdd() async throws {
        let f = try await following()
        defer { f.store.removeFiles() }
        let saves = f.store.saves
        let gates = Dictionary(uniqueKeysWithValues: (["sample"] + Self.hosts).map { ($0, f.fetcher.delay("https://\($0).example/blyg.json")) })
        let hold = f.store.holdNextSave()

        let refresh = Task { await f.model.refreshAll() }
        await until { f.model.refreshing.count == 4 && gates.values.allSatisfy(\.wasReached) }
        f.model.remove(Self.origin("fourth"))      // a write starts, and is slow;
        await until { hold.wasReached }
        f.model.disconnect(Self.origin("second"))  // another is asked for, and waits its turn.
        let before = answers(f)
        for host in ["sample", "second", "third"] { gates[host]?.release() }
        await until { f.model.library.blygs.allSatisfy { $0.lastRefresh != before[$0.origin] } } // three blygs arrive, held back for the end
        hold.release()
        await until { f.store.saves == saves + 2 }
        await f.model.saveFinished()               // the waiting write took them along
        #expect(unsaved(f) == [])
        gates["fourth"]?.release()                 // the refresh ends with nothing new (fourth was unfollowed)
        await refresh.value
        await f.model.saveFinished()

        #expect(!hold.gaveUp)
        #expect(f.store.saves == saves + 2) // so it doesn't write the same library again
    }

    @Test func aRefreshThatBringsNothingNewLeavesTheRowsAlone() async throws {
        let f = try await following()
        defer { f.store.removeFiles() }
        let rows = storage(f.model.timeline)
        #expect(rows != nil)

        await f.model.refreshAll()
        #expect(f.timeline.builds == 1)
        #expect(storage(f.model.timeline) == rows) // not replaced by an equal copy, which costs a comparison of every row

        f.fetcher.publish("8a8a8a8a8a8a8a8a8a8a8a8a8a", on: "second")
        await f.model.refreshAll()
        #expect(storage(f.model.timeline) != rows)
        #expect(f.model.timeline == f.model.library.timeline())
        await f.model.saveFinished()
    }

    @Test func aRefreshDoesNotSaveAgainForWorkASaveHasAlreadyCovered() async throws {
        let f = try await following()
        defer { f.store.removeFiles() }
        let saves = f.store.saves
        var before = answers(f)
        let slow = f.fetcher.delay("https://fourth.example/blyg.json")

        let first = Task { await f.model.refreshAll() }
        await until { onlyStillOut("fourth", slow, f, since: before) } // three are in and waiting for the end to be saved
        f.model.remove(Self.origin("fourth"))                           // ...and this saves them, with the unfollow
        await f.model.saveFinished()
        #expect(f.store.saves == saves + 1)

        before = answers(f)
        let slower = f.fetcher.delay("https://third.example/blyg.json")
        let second = Task { await f.model.refreshAll() } // a second refresh, with work of its own held back
        await until {
            slower.wasReached && [Fixtures.origin, Self.origin("second")].allSatisfy { f.model.blyg($0)?.lastRefresh != before[$0] }
        }
        slow.release() // the first refresh ends: it has nothing left to save, and must leave the second's alone
        await first.value
        await f.model.saveFinished()
        #expect(f.store.saves == saves + 1)

        slower.release()
        await second.value
        await f.model.saveFinished()
        #expect(f.store.saves == saves + 2)
        #expect(unsaved(f) == [])
    }

    @Test func aRefreshWaitsForARebuildAlreadyBringingItsPosts() async throws {
        let f = try await following()
        defer { f.store.removeFiles() }
        f.fetcher.publish("8a8a8a8a8a8a8a8a8a8a8a8a8a", on: "second")
        f.fetcher.set("https://fourth.example/blyg.json", .init(status: 500, body: "")) // its answer will change no posts
        let before = answers(f)
        let slow = f.fetcher.delay("https://fourth.example/blyg.json")
        let returned = Flag()

        let all = Task {
            await f.model.refreshAll()
            returned.isSet = true
        }
        await until { onlyStillOut("fourth", slow, f, since: before) } // second's post is in the library, not yet in the rows
        let build = f.timeline.holdNextBuild()
        let single = Task { await f.model.refresh(Self.origin("third")) } // this one's rebuild takes second's post along
        await until { build.wasReached }
        slow.release()
        await until { f.model.blyg(Self.origin("fourth"))?.lastError != nil }
        try await Task.sleep(for: .milliseconds(50))
        // Every blyg has answered and the rebuild is still under way: refreshAll mustn't have returned without its posts.
        #expect(!returned.isSet)
        #expect(!f.model.timeline.contains { $0.document.id == "8a8a8a8a8a8a8a8a8a8a8a8a8a" })
        build.release()
        await all.value
        #expect(f.model.timeline.contains { $0.document.id == "8a8a8a8a8a8a8a8a8a8a8a8a8a" })
        await single.value
        await f.model.saveFinished()
    }

    // MARK: A connected Studio

    @Test func switchingOffKeepingInStepStopsFollowingTheRestOfTheList() async throws {
        let transport = FakeTransport(Self.studio("sample", follows: ["second"]))
        let f = try await following(transport: transport)
        defer { f.store.removeFiles() }
        f.fetcher.set("https://sixth.example/blyg.json", .init(body: #"{"blyg":"0.4","title":"sixth"}"#))
        f.fetcher.set("https://sixth.example/items/index.json", .init(body: #"{"items":[]}"#))
        try await f.model.connect(Fixtures.origin, token: "secret")
        _ = try await f.model.importSubscriptions(from: Fixtures.origin)
        transport.set("GET https://sample.example/api/subscriptions", (200, Self.subscriptions(["second", "fifth", "sixth"])))
        let slow = f.fetcher.delay("https://fifth.example/blyg.json")

        let refresh = Task { await f.model.refresh(Fixtures.origin) }
        await until { slow.wasReached } // "fifth" is being added
        f.model.stopKeepingInStep(Fixtures.origin)
        slow.release()
        await refresh.value
        await f.model.saveFinished()

        #expect(f.model.blyg(Self.origin("fifth")) != nil)  // already under way
        #expect(f.model.blyg(Self.origin("sixth")) == nil)  // not started after the switch went off
        #expect(f.model.blyg(Fixtures.origin)?.studioFollows == nil)
    }

    @Test func aStudiosNewFollowsAreRememberedOneByOneAsEachIsTried() async throws {
        let transport = FakeTransport(Self.studio("sample", follows: ["second"]))
        let f = try await following(transport: transport)
        defer { f.store.removeFiles() }
        f.fetcher.set("https://sixth.example/blyg.json", .init(body: #"{"blyg":"0.4","title":"sixth"}"#))
        f.fetcher.set("https://sixth.example/items/index.json", .init(body: #"{"items":[]}"#))
        try await f.model.connect(Fixtures.origin, token: "secret")
        _ = try await f.model.importSubscriptions(from: Fixtures.origin)
        #expect(f.model.blyg(Fixtures.origin)?.studioFollows == [Self.origin("second")])
        transport.set("GET https://sample.example/api/subscriptions", (200, Self.subscriptions(["second", "fifth", "sixth"])))
        let slow = f.fetcher.delay("https://fifth.example/blyg.json")
        let slower = f.fetcher.delay("https://sixth.example/blyg.json")
        func saved() -> Library { f.store.load().0 }

        let refresh = Task { await f.model.refresh(Fixtures.origin) }
        await until { slow.wasReached } // "fifth" is being added
        // If the app were closed here, the saved list mustn't say "fifth" or "sixth" has been seen: neither would ever be followed.
        f.model.enteredBackground()
        await f.model.saveFinished()
        #expect(saved().blygs.first?.studioFollows == [Self.origin("second")])
        #expect(saved().blygs.count == 4)

        slow.release()
        await until { slower.wasReached } // "fifth" is in, "sixth" is being added
        await f.model.saveFinished()
        // Closed here, "fifth" has been tried and is never taken up again, even if it's unfollowed meanwhile; "sixth" still will be.
        #expect(saved().blygs.first?.studioFollows == [Self.origin("second"), Self.origin("fifth")])
        #expect(saved().blygs.count == 5)

        slower.release()
        await refresh.value
        await f.model.saveFinished()
        #expect(saved().blygs.first?.studioFollows == [Self.origin("second"), Self.origin("fifth"), Self.origin("sixth")])
        #expect(saved().blygs.count == 6)
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
