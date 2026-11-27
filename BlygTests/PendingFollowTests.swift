import Foundation
import Testing
@testable import Blyg

/// A blyg a Studio follows that couldn't be reached used to be remembered as seen at once, and never tried
/// again. It's now kept on a pending list with a count of tries, and tried again once each time the app opens,
/// up to three tries in all.
@Suite("A Studio's blygs that can't be reached are tried again, by a rule") @MainActor
struct PendingFollowTests {
    static func origin(_ host: String) -> URL { RefreshTests.origin(host) }
    static let gone = origin("gone")
    static func waiting(_ tries: Int) -> [PendingFollow] { [PendingFollow(origin: gone, attempts: tries)] }

    struct Kept {
        let model: LibraryModel
        let fetcher: FakeFetcher
        let store: CountingStore
        let transport: FakeTransport
        let tokens: MemoryTokenStore
    }

    /// The sample blyg, connected and keeping in step with its Studio, which follows "second". Both are followed
    /// and saved. "third" is there to be found; "gone" isn't: nothing answers at its address.
    func keepingInStep() async throws -> Kept {
        let fetcher = FakeFetcher.sample()
        for host in ["second", "third"] { fetcher.answer(as: host) }
        let transport = FakeTransport(RefreshTests.studio("sample", follows: ["second"]))
        let store = CountingStore()
        let tokens = MemoryTokenStore()
        let model = LibraryModel(store: store, fetcher: fetcher, tokens: tokens, transport: transport,
                                 buildTimeline: { $0.timeline(now: feedNow) }, timelinePace: .seconds(60))
        try await model.add("sample.example")
        try await model.connect(Fixtures.origin, token: "secret")
        _ = try await model.importSubscriptions(from: Fixtures.origin)
        await model.saveFinished()
        return Kept(model: model, fetcher: fetcher, store: store, transport: transport, tokens: tokens)
    }

    /// ...and then its Studio follows "gone" as well, and a pull to refresh has tried it once and not reached it.
    func withOnePending() async throws -> Kept {
        let k = try await keepingInStep()
        studio(k, follows: ["second", "gone"])
        await k.model.refreshAll()
        await k.model.saveFinished()
        #expect(pending(k.model) == Self.waiting(1))
        return k
    }

    func studio(_ k: Kept, follows hosts: [String]) {
        k.transport.set("GET https://sample.example/api/subscriptions", (200, RefreshTests.subscriptions(hosts)))
    }

    /// The app is closed and opened again: a new model on the same file, Keychain and network.
    func reopened(_ k: Kept, after model: LibraryModel? = nil, pace: Duration = .seconds(60), timeline: TimelineCounter? = nil) async -> LibraryModel {
        await (model ?? k.model).saveFinished()
        return LibraryModel(store: k.store, fetcher: k.fetcher, tokens: k.tokens, transport: k.transport,
                            buildTimeline: { timeline?.build($0) ?? $0.timeline(now: feedNow) }, timelinePace: pace)
    }

    /// How many times "gone" has been tried: each try asks for its manifest once.
    func tries(_ k: Kept) -> Int { k.fetcher.requested.filter { $0 == "https://gone.example/blyg.json" }.count }
    /// How many times the Studio has been asked what it follows: a refresh that ran its keeping-in-step pass.
    func asked(_ k: Kept) -> Int { k.transport.keys.filter { $0.hasSuffix("/subscriptions") }.count }
    func pending(_ model: LibraryModel) -> [PendingFollow]? { model.blyg(Fixtures.origin)?.pendingFollows }
    func remembered(_ model: LibraryModel) -> [URL]? { model.blyg(Fixtures.origin)?.studioFollows }

    // 1. A blyg that can't be reached is kept pending, with its tries counted, and not remembered as seen.
    @Test(arguments: ["nothing there", "a network error", "a timeout", "a page that isn't a blyg"])
    func aBlygThatCantBeReachedIsKeptPendingAndNotRememberedAsSeen(why: String) async throws {
        let k = try await keepingInStep()
        defer { k.store.removeFiles() }
        switch why {
        case "a network error": k.fetcher.fail("gone.example", with: .cannotFindHost)
        case "a timeout": k.fetcher.fail("gone.example", with: .timedOut)
        case "a page that isn't a blyg":
            for path in ["", "blyg.json", "blyg/blyg.json"] { k.fetcher.set("https://gone.example/\(path)", .init(body: "<html><p>Parked.</p></html>")) }
        default: break // every address answers 404
        }
        studio(k, follows: ["second", "gone", "third"])

        await k.model.refreshAll()
        await k.model.saveFinished()
        #expect(tries(k) == 1)
        #expect(pending(k.model) == Self.waiting(1))
        #expect(remembered(k.model) == [Self.origin("second"), Self.origin("third")]) // "gone" isn't among those dealt with
        #expect(k.model.blyg(Self.gone) == nil)
        #expect(k.model.blyg(Self.origin("third")) != nil) // the one after it on the list was still followed
    }

    // 2. It's tried again once per launch, during the launch refresh, and nowhere else.
    @Test func aPendingBlygIsTriedAgainOncePerLaunchAndNowhereElse() async throws {
        let k = try await withOnePending()
        defer { k.store.removeFiles() }
        var studioAsked = asked(k)
        /// The refresh did run its keeping-in-step pass (it asked the Studio), so "not tried" isn't "nothing ran".
        func ranAPass() -> Bool {
            defer { studioAsked = asked(k) }
            return asked(k) == studioAsked + 1
        }

        await k.model.refreshAll() // pull to refresh
        #expect(ranAPass())
        await k.model.refreshStale(now: .now.addingTimeInterval(20 * 60)) // coming back from the background
        #expect(ranAPass())
        await k.model.refresh(Fixtures.origin) // one blyg refreshed alone
        #expect(ranAPass())
        #expect(tries(k) == 1)
        #expect(pending(k.model) == Self.waiting(1))

        let launched = await reopened(k)
        await launched.refreshAtLaunch()
        #expect(ranAPass())
        #expect(tries(k) == 2) // the launch refresh tried it
        #expect(pending(launched) == Self.waiting(2))

        await launched.refreshAtLaunch() // only the first launch refresh of a launch retries
        #expect(ranAPass())
        await launched.refreshAll()
        await launched.refreshStale(now: .now.addingTimeInterval(20 * 60))
        #expect(tries(k) == 2)
        #expect(pending(launched) == Self.waiting(2))
        await launched.saveFinished()
    }

    // 3. After three failed tries in all, the first included, it's remembered as seen and never tried again.
    @Test func afterThreeTriesInAllItIsRememberedAsSeenAndLeftAlone() async throws {
        #expect(PendingFollow.maxAttempts == 3)
        let k = try await withOnePending() // the first try
        defer { k.store.removeFiles() }

        let second = await reopened(k)
        await second.refreshAtLaunch()
        #expect(tries(k) == 2)
        #expect(pending(second) == Self.waiting(2))
        #expect(remembered(second) == [Self.origin("second")])

        let third = await reopened(k, after: second)
        await third.refreshAtLaunch()
        #expect(tries(k) == 3)
        #expect(pending(third) == nil)
        #expect(remembered(third) == [Self.origin("second"), Self.gone]) // dealt with, for good

        k.fetcher.answer(as: "gone") // it turns up later: too late, as before this rule
        let fourth = await reopened(k, after: third)
        await fourth.refreshAtLaunch()
        await fourth.saveFinished()
        #expect(tries(k) == 3)
        #expect(fourth.blyg(Self.gone) == nil)
        #expect(pending(fourth) == nil)
        #expect(k.store.load().0.blygs.first?.studioFollows == [Self.origin("second"), Self.gone])
    }

    // 4. If it answers on any try, it's followed like any other and leaves the pending list.
    @Test func aPendingBlygThatAnswersIsFollowedAndLeavesTheList() async throws {
        let k = try await withOnePending()
        defer { k.store.removeFiles() }
        let second = await reopened(k)
        await second.refreshAtLaunch() // still not there: two tries used
        #expect(pending(second) == Self.waiting(2))

        k.fetcher.answer(as: "gone")
        k.fetcher.publish("8a8a8a8a8a8a8a8a8a8a8a8a8a", on: "gone")
        let third = await reopened(k, after: second)
        await third.refreshAtLaunch() // the third and last try
        await third.saveFinished()
        #expect(third.blyg(Self.gone)?.items.count == 1)
        #expect(third.timeline.contains { $0.origin == Self.gone })
        #expect(pending(third) == nil)
        #expect(remembered(third) == [Self.origin("second"), Self.gone])
        let saved = try #require(k.store.load().0.blygs.first)
        #expect(saved.pendingFollows == nil)
        #expect(saved.studioFollows == [Self.origin("second"), Self.gone])

        // Unfollowed now, it stays unfollowed: it has been dealt with.
        third.remove(Self.gone)
        let fourth = await reopened(k, after: third)
        await fourth.refreshAtLaunch()
        await fourth.saveFinished()
        #expect(fourth.blyg(Self.gone) == nil)
    }

    // 5. Switching keeping in step off, disconnecting, or unfollowing the Studio's own blyg ends the retries.
    @Test(arguments: ["switched off", "disconnected", "its Studio's blyg unfollowed"])
    func aPendingBlygIsNotRetriedOnceKeepingInStepEnds(how: String) async throws {
        let k = try await withOnePending()
        defer { k.store.removeFiles() }
        switch how {
        case "switched off": k.model.stopKeepingInStep(Fixtures.origin)
        case "disconnected": k.model.disconnect(Fixtures.origin)
        default: k.model.remove(Fixtures.origin)
        }
        #expect(pending(k.model) == nil)
        await k.model.saveFinished()
        #expect(k.store.load().0.blygs.allSatisfy { $0.pendingFollows == nil })

        k.fetcher.answer(as: "gone") // it would be found now
        let launched = await reopened(k)
        await launched.refreshAtLaunch()
        await launched.saveFinished()
        #expect(tries(k) == 1)
        #expect(launched.blyg(Self.gone) == nil)
    }

    // 5. A blyg the Studio stops listing leaves the pending list, untried.
    @Test func aBlygTheStudioStopsListingLeavesThePendingListUntried() async throws {
        let k = try await withOnePending()
        defer { k.store.removeFiles() }
        studio(k, follows: ["second"])
        k.fetcher.answer(as: "gone") // it would be found now

        let launched = await reopened(k)
        await launched.refreshAtLaunch()
        await launched.saveFinished()
        #expect(tries(k) == 1)
        #expect(pending(launched) == nil)
        #expect(remembered(launched) == [Self.origin("second")])
        #expect(launched.blyg(Self.gone) == nil)
        #expect(k.store.load().0.blygs.first?.pendingFollows == nil)

        // It needn't wait for a launch to leave the list: any refresh that reads the Studio's list drops it.
        let other = try await withOnePending()
        defer { other.store.removeFiles() }
        studio(other, follows: ["second"])
        await other.model.refreshAll()
        await other.model.saveFinished()
        #expect(pending(other.model) == nil)
        #expect(tries(other) == 1)
    }

    // 5. A pending blyg followed by hand has been dealt with: unfollowed afterwards, it isn't retried and doesn't come back.
    @Test func aPendingBlygFollowedByHandAndThenUnfollowedIsNotRetried() async throws {
        let k = try await withOnePending()
        defer { k.store.removeFiles() }
        k.fetcher.answer(as: "gone")

        try await k.model.add("gone.example")
        #expect(pending(k.model) == nil)
        #expect(remembered(k.model) == [Self.origin("second"), Self.gone])
        k.model.remove(Self.gone)

        let launched = await reopened(k)
        await launched.refreshAtLaunch()
        await launched.saveFinished()
        #expect(launched.blyg(Self.gone) == nil)
        #expect(pending(launched) == nil)
    }

    // 6. The first import of a Studio's follows uses the same rule.
    @Test func theFirstImportKeepsABlygItCantReachPendingToo() async throws {
        let k = try await keepingInStep()
        defer { k.store.removeFiles() }
        k.model.stopKeepingInStep(Fixtures.origin)
        studio(k, follows: ["second", "gone", "third"])

        let result = try await k.model.importSubscriptions(from: Fixtures.origin) // switched on: the first import
        #expect(result.added == 1)
        #expect(result.failed == ["gone.example"])
        #expect(result.retrying == 1)
        #expect(tries(k) == 1)
        #expect(pending(k.model) == Self.waiting(1))
        #expect(remembered(k.model) == [Self.origin("second"), Self.origin("third")])

        await k.model.refreshAll() // not on pull to refresh
        #expect(tries(k) == 1)
        // Nor by a launch refresh in the same launch (one still running when the switch went on): once per launch.
        await k.model.refreshAtLaunch()
        #expect(tries(k) == 1)
        #expect(pending(k.model) == Self.waiting(1))
        let second = await reopened(k)
        await second.refreshAtLaunch()
        #expect(tries(k) == 2)
        #expect(pending(second) == Self.waiting(2))

        k.fetcher.answer(as: "gone")
        let third = await reopened(k, after: second)
        await third.refreshAtLaunch()
        await third.saveFinished()
        #expect(third.blyg(Self.gone) != nil)
        #expect(pending(third) == nil)
        #expect(remembered(third) == [Self.origin("second"), Self.gone, Self.origin("third")]) // the Studio's own order
    }

    // 7. The pending list and its counts are saved with the library, and an older file without them still loads.
    @Test func thePendingListIsSavedAndAnOlderFileWithoutOneStillLoads() async throws {
        let k = try await withOnePending()
        defer { k.store.removeFiles() }
        #expect(k.store.load().1 == .loaded)
        #expect(k.store.load().0.blygs.first?.pendingFollows == Self.waiting(1))
        // The app is killed and opened: the count carries on from where it was.
        let launched = await reopened(k)
        #expect(pending(launched) == Self.waiting(1))
        await launched.refreshAtLaunch()
        await launched.saveFinished()
        #expect(k.store.load().0.blygs.first?.pendingFollows == Self.waiting(2))

        // A file as build 10 wrote it: no "pendingFollows" at all.
        let older = CountingStore()
        defer { older.removeFiles() }
        try FileManager.default.createDirectory(at: older.store.directory, withIntermediateDirectories: true)
        try Data("""
            {"version":1,"blygs":[{"origin":"https://sample.example/","manifest":{"blyg":"0.4","title":"Sample Notes"},\
            "addedAt":"2026-11-20T08:00:00Z","items":{},"postingAPI":"https://sample.example/api",\
            "studioFollows":["https://second.example/"]}]}
            """.utf8).write(to: older.store.fileURL)
        let (library, outcome) = older.load()
        #expect(outcome == .loaded)
        #expect(library.blygs.first?.studioFollows == [Self.origin("second")])
        #expect(library.blygs.first?.pendingFollows == nil)
        let model = LibraryModel(store: older, fetcher: FakeFetcher(), buildTimeline: { $0.timeline(now: feedNow) })
        #expect(model.loadProblem == nil)
        #expect(model.library.blygs.count == 1)
    }

    // 8. A retry doesn't hold up the first timeline or the main actor, and goes through the same paced rebuild
    //    and the same single save at the end as the rest of the refresh.
    @Test func aRetryAtLaunchSharesThePacedRebuildAndTheOneSaveAndHoldsNothingUp() async throws {
        let k = try await withOnePending()
        defer { k.store.removeFiles() }
        try await k.model.add("third.example")
        k.fetcher.publish("9b9b9b9b9b9b9b9b9b9b9b9b9b", on: "third")
        k.fetcher.answer(as: "gone")
        k.fetcher.publish("8a8a8a8a8a8a8a8a8a8a8a8a8a", on: "gone")
        let slow = k.fetcher.delay("https://gone.example/blyg.json") // the retry will be slow to answer
        let requests = k.fetcher.requestCount

        let timeline = TimelineCounter()
        let launched = await reopened(k, pace: .milliseconds(20), timeline: timeline)
        // The app opens with its saved posts in place, built once, before anything is asked of the network.
        #expect(timeline.builds == 1)
        #expect(launched.timeline.count == 3)
        #expect(k.fetcher.requestCount == requests)
        timeline.reset()
        let saves = k.store.saves

        let launch = Task { await launched.refreshAtLaunch() }
        // While the retry is still out, third's new post arrives and is shown, at the pace: the retry delays no one.
        await until { slow.wasReached && launched.timeline.contains { $0.document.id == "9b9b9b9b9b9b9b9b9b9b9b9b9b" } }
        #expect(launched.isRefreshingAny)
        #expect(launched.blyg(Self.gone) == nil)
        #expect(k.store.saves == saves) // nothing written until the end of the refresh
        slow.release()
        await launch.value
        await launched.saveFinished()

        #expect(!k.fetcher.askedOnMainThread)
        #expect(!timeline.builtOnMainThread)
        #expect(launched.timeline.contains { $0.document.id == "8a8a8a8a8a8a8a8a8a8a8a8a8a" }) // the retried blyg's post
        #expect(launched.timeline == launched.library.timeline(now: feedNow))
        #expect(pending(launched) == nil)
        #expect(k.store.saves == saves + 1) // one save for the whole launch refresh, the retry's follow included
        #expect((2...4).contains(timeline.builds)) // whether the retry waits for the pace is the next test's question
        let f = RefreshTests.Following(model: launched, fetcher: k.fetcher, store: k.store, timeline: timeline)
        #expect(RefreshTests().unsaved(f) == [])
    }

    // 8. The retried blyg's posts wait for the paced rebuild like anyone's: following it doesn't rebuild at once.
    @Test func aRetriedBlygsPostsWaitForThePacedRebuild() async throws {
        let k = try await withOnePending()
        defer { k.store.removeFiles() }
        try await k.model.add("third.example")
        k.fetcher.answer(as: "gone")
        k.fetcher.publish("8a8a8a8a8a8a8a8a8a8a8a8a8a", on: "gone")
        let retry = k.fetcher.delay("https://gone.example/blyg.json")
        let other = k.fetcher.delay("https://third.example/blyg.json") // keeps the refresh open after the retry is in
        let timeline = TimelineCounter()
        let launched = await reopened(k, pace: .seconds(60), timeline: timeline) // the last rebuild was just now, as it opened
        timeline.reset()
        let saves = k.store.saves

        let launch = Task { await launched.refreshAtLaunch() }
        await until { retry.wasReached && other.wasReached }
        retry.release()
        await until { launched.blyg(Self.gone)?.items.count == 1 } // followed, and its post fetched
        try await Task.sleep(for: .milliseconds(100)) // a rebuild free to start at once would have by now
        #expect(timeline.builds == 0)
        #expect(!launched.timeline.contains { $0.origin == Self.gone })
        #expect(k.store.saves == saves)
        other.release()
        await launch.value
        await launched.saveFinished()
        #expect(timeline.builds == 1) // the one at the end of the refresh
        #expect(launched.timeline.contains { $0.document.id == "8a8a8a8a8a8a8a8a8a8a8a8a8a" })
        #expect(k.store.saves == saves + 1)
    }

    // MARK: From Codex's review

    /// A second Studio: "third" is followed, connected and keeping in step, following "second" like the first.
    func withASecondStudio(_ k: Kept) async throws {
        for (key, answer) in RefreshTests.studio("third", follows: ["second"]) { k.transport.set(key, answer) }
        try await k.model.add("third.example")
        try await k.model.connect(Self.origin("third"), token: "secret")
        _ = try await k.model.importSubscriptions(from: Self.origin("third"))
        await k.model.saveFinished()
    }

    @Test func twoStudiosListingOneDeadAddressMakeOneTryPerLaunchBetweenThem() async throws {
        let k = try await keepingInStep()
        defer { k.store.removeFiles() }
        try await withASecondStudio(k)
        func pendingOnBoth(_ model: LibraryModel) -> [[PendingFollow]?] {
            [Fixtures.origin, Self.origin("third")].map { model.blyg($0)?.pendingFollows }
        }
        studio(k, follows: ["second", "gone"])
        k.transport.set("GET https://third.example/api/subscriptions", (200, RefreshTests.subscriptions(["second", "gone"])))

        await k.model.refreshAll() // both lists find it new in the same refresh
        #expect(tries(k) == 1)
        #expect(pendingOnBoth(k.model) == [Self.waiting(1), Self.waiting(1)])

        let second = await reopened(k)
        await second.refreshAtLaunch()
        #expect(tries(k) == 2)
        #expect(pendingOnBoth(second) == [Self.waiting(2), Self.waiting(2)])

        let third = await reopened(k, after: second)
        await third.refreshAtLaunch()
        #expect(tries(k) == 3) // three in all, not three for each list
        #expect(pendingOnBoth(third) == [nil, nil])
        #expect(third.blyg(Fixtures.origin)?.studioFollows == [Self.origin("second"), Self.gone])
        #expect(third.blyg(Self.origin("third"))?.studioFollows == [Self.origin("second"), Self.gone])

        let fourth = await reopened(k, after: third)
        await fourth.refreshAtLaunch()
        await fourth.saveFinished()
        #expect(tries(k) == 3)
    }

    @Test func aFirstImportCutShortLeavesTheRestForTheNextRefresh() async throws {
        let k = try await keepingInStep()
        k.fetcher.answer(as: "fourth")
        k.model.stopKeepingInStep(Fixtures.origin)
        studio(k, follows: ["second", "third", "fourth"])
        let held = k.fetcher.delayNext("https://third.example/blyg.json")

        let importing = Task { try await k.model.importSubscriptions(from: Fixtures.origin) }
        await until { held.wasReached } // "third" is being followed; "fourth" hasn't been tried
        k.model.enteredBackground()
        await k.model.saveFinished()
        // The app is closed here. The file mustn't say "third" or "fourth" has been dealt with: neither would ever be followed.
        #expect(k.store.load().0.blygs.first?.studioFollows == [Self.origin("second")])

        let launched = await reopened(k)
        await launched.refreshAtLaunch()
        await launched.saveFinished()
        #expect(launched.blyg(Self.origin("third")) != nil)
        #expect(launched.blyg(Self.origin("fourth")) != nil)
        #expect(remembered(launched) == ["second", "third", "fourth"].map(Self.origin))

        held.release() // let the first model's import end before its files go
        _ = try await importing.value
        await k.model.saveFinished()
        k.store.removeFiles()
    }

    @Test(arguments: ["while the Studio's list is on its way", "while the list is being worked through"])
    func disconnectingDuringTheFirstImportStopsIt(when: String) async throws {
        let k = try await keepingInStep()
        defer { k.store.removeFiles() }
        k.fetcher.answer(as: "fourth")
        k.model.stopKeepingInStep(Fixtures.origin)
        studio(k, follows: ["second", "third", "fourth"])
        let early = when.contains("on its way")
        let list = early ? k.transport.delay("GET https://sample.example/api/subscriptions") : nil
        let follow = early ? nil : k.fetcher.delay("https://third.example/blyg.json")

        let importing = Task { try await k.model.importSubscriptions(from: Fixtures.origin) }
        await until { list?.wasReached ?? follow?.wasReached ?? true }
        k.model.disconnect(Fixtures.origin)
        list?.release()
        follow?.release()
        _ = try await importing.value
        await k.model.saveFinished()

        #expect(remembered(k.model) == nil) // disconnected is disconnected: keeping in step didn't come back on
        #expect(pending(k.model) == nil)
        // Only the one already being followed when it happened; with the list still on its way, none.
        #expect((k.model.blyg(Self.origin("third")) == nil) == early)
        #expect(k.model.blyg(Self.origin("fourth")) == nil)
    }

    @Test func aBlygUnfollowedWhileItsRetryIsOutStaysUnfollowed() async throws {
        let k = try await withOnePending()
        defer { k.store.removeFiles() }
        k.fetcher.answer(as: "gone")
        let launched = await reopened(k)
        let held = k.fetcher.delayNext("https://gone.example/blyg.json") // the retry's request; a later one goes through

        let launch = Task { await launched.refreshAtLaunch() }
        await until { held.wasReached }
        try await launched.add("gone.example") // followed by hand while the retry is still asking,
        #expect(pending(launched) == nil)
        launched.remove(Self.gone)             // and unfollowed again.
        held.release()                         // Now the retry's answer arrives: there is a blyg there.
        await launch.value
        await launched.saveFinished()

        #expect(launched.blyg(Self.gone) == nil)
        #expect(pending(launched) == nil)
        #expect(remembered(launched) == [Self.origin("second"), Self.gone])
    }

    @Test func aRetryThatFailsAfterTheBlygWasFollowedByHandDoesNotPutItBackOnTheList() async throws {
        let k = try await withOnePending()
        defer { k.store.removeFiles() }
        k.fetcher.answer(as: "gone")
        let launched = await reopened(k)
        let held = k.fetcher.delayNext("https://gone.example/blyg.json")

        let launch = Task { await launched.refreshAtLaunch() }
        await until { held.wasReached }
        try await launched.add("gone.example") // followed by hand: dealt with
        k.fetcher.fail("gone.example", with: .timedOut)
        held.release()                         // the retry's own request times out
        await launch.value
        await launched.saveFinished()

        #expect(launched.blyg(Self.gone) != nil)
        #expect(pending(launched) == nil)
        #expect(remembered(launched) == [Self.origin("second"), Self.gone])
    }

    @Test func aPendingBlygFollowedByHandThroughARedirectStopsWaitingToo() async throws {
        let k = try await withOnePending()
        defer { k.store.removeFiles() }
        // The address the Studio lists now answers, as a blyg that lives at another address.
        k.fetcher.answer(as: "moved")
        k.fetcher.set("https://gone.example/blyg.json", .init(body: #"{"blyg":"0.4","title":"moved"}"#, finalURL: "https://moved.example/blyg.json"))

        #expect(try await k.model.add("gone.example") == Self.origin("moved"))
        #expect(pending(k.model) == nil)
        #expect(remembered(k.model) == [Self.origin("second"), Self.gone])
        k.model.remove(Self.origin("moved"))

        let asked = tries(k)
        let launched = await reopened(k)
        await launched.refreshAtLaunch()
        await launched.saveFinished()
        #expect(tries(k) == asked)
        #expect(launched.blyg(Self.origin("moved")) == nil)
    }
}

extension FakeFetcher {
    /// A blyg with no posts answers at `host`.example from now on.
    func answer(as host: String) {
        fail("\(host).example", with: nil)
        set("https://\(host).example/blyg.json", .init(body: #"{"blyg":"0.4","title":"\#(host)"}"#))
        set("https://\(host).example/items/index.json", .init(body: #"{"items":[]}"#))
    }
}
