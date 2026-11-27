import Foundation
import os
import Observation

/// The app's state: the saved library, kept in sync with disk. Opens at once from what's saved;
/// the network only ever adds to it.
///
/// This class is on the main actor (the project's default), so only quick work belongs in it. Fetching and
/// decoding (`Syncer`, `Resolver`), building the timeline and writing the file all run off it: see
/// "Timeline and saving" below.
@Observable
final class LibraryModel {
    private(set) var library: Library
    /// The main feed: the recent posts of every blyg (`FeedWindow`), newest first. Each blyg's own page gets all
    /// of that blyg's posts from `posts(of:)`. Observed like the other properties, but kept in storage of its
    /// own (`rows`, set with `show`): the setter Observation would write compares the old and new rows before
    /// telling views, a pass over every row on the main actor, and by then it's already known that they differ.
    var timeline: [TimelineEntry] {
        access(keyPath: \.timeline)
        return rows
    }
    @ObservationIgnored private var rows: [TimelineEntry] = []

    private func show(_ new: [TimelineEntry]) {
        withMutation(keyPath: \.timeline) { rows = new }
    }
    private(set) var refreshing: Set<URL> = []
    /// Refreshes of several blygs at once that haven't finished: their timeline is still to come.
    private var refreshingTogether = 0
    /// Set when the saved file couldn't be read at launch, so the app can say so instead of silently starting empty.
    private(set) var loadProblem: LibraryStore.LoadOutcome?

    private let store: (any LibraryPersisting)?
    private let fetcher: any Fetching
    private let tokens: any TokenStore
    private let transport: any HTTPTransport
    private let buildTimeline: @Sendable (Library) -> [TimelineEntry]
    /// While several blygs are being refreshed at once, the least time between one timeline rebuild finishing
    /// and the next starting: posts appear as blygs arrive, without a rebuild for every blyg.
    private let timelinePace: Duration
    /// The blygs with a token in the Keychain. Remembered here because asking the Keychain is a blocking call
    /// to another process, and views ask on every redraw: once per blyg during a refresh. Only this model
    /// saves or removes tokens (the Share extension just reads them), so it can't go stale while the app runs.
    private var tokenHolders: Set<URL> = []

    /// `buildTimeline` is `Library.timeline()` in the app; tests pass their own to count and hold rebuilds,
    /// and their own `timelinePace` so they needn't depend on half a second passing or not.
    init(store: (any LibraryPersisting)?, fetcher: any Fetching, tokens: any TokenStore = MemoryTokenStore(),
         transport: any HTTPTransport = URLSessionTransport(),
         buildTimeline: @escaping @Sendable (Library) -> [TimelineEntry] = { $0.timeline() },
         timelinePace: Duration = .milliseconds(500)) {
        self.store = store
        self.fetcher = fetcher
        self.tokens = tokens
        self.transport = transport
        self.buildTimeline = buildTimeline
        self.timelinePace = timelinePace
        if let store {
            let (library, outcome) = store.load()
            self.library = library
            if outcome == .recoveredFromBackup || outcome == .unreadable { loadProblem = outcome }
        } else {
            self.library = Library()
        }
        // A posting API saved before connect checked it is checked now, so the token can't follow it to another host.
        // A blyg that isn't https loses its posting API: it can be read, never posted to.
        for index in library.blygs.indices {
            guard let saved = library.blygs[index].postingAPI else { continue }
            library.blygs[index].postingAPI = StudioClient.trustedAPI(saved, forOrigin: library.blygs[index].origin)
        }
        tokenHolders = Set(library.blygs.filter { $0.postingAPI != nil }.map(\.origin).filter { tokens.token(for: $0) != nil })
        // The one build on the main actor: the app opens with its saved posts already in place.
        rows = buildTimeline(library)
        lastRebuild = .now // the first blygs to answer wait out the pace like any others, and share a rebuild
    }

    var isRefreshingAny: Bool { !refreshing.isEmpty || refreshingTogether > 0 }

    func blyg(_ origin: URL) -> SavedBlyg? { library.blygs.first { $0.origin == origin } }

    /// Resolves a URL to a blyg, adds it, then fetches its items. Returns the identity origin.
    @discardableResult
    func add(_ input: String) async throws -> URL { try await add(input, in: nil) }

    /// `forStudio`: a Studio's list asked for this follow, not the person (see `followFromStudio`).
    /// `whenFollowed` runs once the blyg is in the library (or is found there already), before its posts are fetched.
    @discardableResult
    private func add(_ input: String, in batch: Batch?, forStudio: Bool = false, whenFollowed: () -> Void = {}) async throws -> URL {
        let resolved = try await Resolver(fetcher: fetcher).resolve(input)
        // Unfollowed by hand while a Studio's list was still asking after it: it stays unfollowed.
        if forStudio, unfollowedDuringStudioFollow.contains(resolved.origin) {
            whenFollowed()
            return resolved.origin
        }
        let isNew = blyg(resolved.origin) == nil
        if isNew {
            library.blygs.append(SavedBlyg(origin: resolved.origin, manifest: resolved.manifest, addedAt: .now))
            save(in: batch)
        }
        // Under the address it turned out to have and the one that was asked for: a Studio lists a blyg by the
        // address typed there, which may redirect.
        for address in Set([resolved.origin, BlygURL.candidateOrigin(from: input)].compactMap { $0 }) {
            unreachableThisLaunch[address] = nil
            noLongerPending(address, in: batch)
            // A Studio's list is asking after this same address right now: whatever its own answer, it's been dealt with.
            if !forStudio, followsUnderWay[address] != nil { followedByHandDuringStudioFollow.insert(address) }
        }
        whenFollowed()
        // A blyg a Studio's list asked for that was followed already (under another address, say) has nothing new
        // to fetch here. And it mustn't be refreshed from here: if it's a Studio itself, keeping in step, with this
        // same address on its own list, that refresh would wait for this very follow to finish.
        if isNew || !forStudio { await refresh(resolved.origin, in: batch) }
        return resolved.origin
    }

    /// `followed` is followed now, by whatever route (by hand, too). If a Studio's list had it waiting to be tried
    /// again, it stops waiting and is remembered as dealt with: unfollowed later, it mustn't be retried and come back.
    private func noLongerPending(_ followed: URL, in batch: Batch?) {
        for index in library.blygs.indices where library.blygs[index].pendingFollows?.contains(where: { $0.origin == followed }) == true {
            library.blygs[index].pendingFollows?.removeAll { $0.origin == followed }
            if library.blygs[index].pendingFollows?.isEmpty == true { library.blygs[index].pendingFollows = nil }
            if library.blygs[index].studioFollows?.contains(followed) == false { library.blygs[index].studioFollows?.append(followed) }
            save(in: batch)
        }
    }

    func remove(_ origin: URL) {
        tokens.remove(for: origin)
        tokenHolders.remove(origin)
        library.blygs.removeAll { $0.origin == origin }
        // A Studio's list may be asking after this very blyg right now: its answer mustn't follow it again.
        // (Or it may be further down a list being worked through, its turn still to come.)
        if studioListsUnderWay > 0 || !followsUnderWay.isEmpty { unfollowedDuringStudioFollow.insert(origin) }
        // The same rows a rebuild would leave, without rescanning every post on the main actor: taken out in
        // place, and a blyg with no posts showing changes nothing, so views aren't told and no row is copied.
        let shown = rows.count
        if rows.contains(where: { $0.origin == origin }) {
            withMutation(keyPath: \.timeline) { rows.removeAll { $0.origin == origin } }
        }
        // A rebuild under way took its copy of the library with this blyg in it: it leaves these rows out too,
        // and goes round once more on a copy without the blyg (see below: its rows may have crowded others out).
        if timelineTask != nil {
            unfollowedDuringRebuild.insert(origin)
            timelineStale = true
        }
        save()
        // The one case the rows left aren't what a rebuild would leave: the feed was full, so other blygs' posts
        // were waiting below its last row, and now there's room for them. A rebuild, off the main actor, brings them in.
        if shown >= FeedWindow.maxPosts, rows.count < shown { Task { await rebuildTimeline() } }
    }

    func refreshAll() async {
        await refreshTogether(library.blygs.map(\.origin))
    }

    /// The refresh as the app opens: `refreshAll`, and also the one time a blyg a Studio follows that couldn't be
    /// reached before is tried again. Once per launch: only the first call retries, and pull to refresh or
    /// coming back to the app never does, so an address that's gone isn't asked over and over.
    func refreshAtLaunch() async {
        let retry = !retriedPendingThisLaunch
        retriedPendingThisLaunch = true
        await refreshTogether(library.blygs.map(\.origin), retryingPending: retry)
    }

    /// Whether this launch's one retry of pending follows has been used (see `refreshAtLaunch`).
    @ObservationIgnored private var retriedPendingThisLaunch = false

    /// Coming back to the app: catch up without hammering anyone. Your own blygs are refreshed after 30 seconds,
    /// so a post made from the share sheet (which can't tell the app) shows up; the others after 10 minutes.
    func refreshStale(now: Date = .now) async {
        let own = Set(postingBlygs.map(\.origin))
        let stale = library.blygs.filter { blyg in
            guard let last = blyg.lastRefresh else { return true }
            return now.timeIntervalSince(last) > (own.contains(blyg.origin) ? 30 : 600)
        }
        await refreshTogether(stale.map(\.origin))
    }

    /// Refreshes several blygs at once. Each one's result goes into the library as it arrives. Rebuilding the
    /// timeline and saving the file both cost time in proportion to the whole library, so doing them per blyg
    /// made a refresh of many blygs cost many times over. Instead the timeline is rebuilt at a pace while blygs
    /// arrive (`rebuildTimelineSoon`) and once more when all have answered, and the file is saved once, at the end.
    private func refreshTogether(_ origins: [URL], retryingPending: Bool = false) async {
        guard !origins.isEmpty else { return }
        refreshingTogether += 1
        let batch = Batch(retriesPending: retryingPending)
        await withTaskGroup(of: Void.self) { group in
            for origin in origins {
                group.addTask { await self.refresh(origin, in: batch) }
            }
        }
        // Only what this refresh's own blygs left for it and nothing has saved or rebuilt since: a second
        // refresh running alongside doesn't finish this one's work early, or do it twice. The rebuild here
        // doesn't wait for the pace: these are the last posts of the refresh.
        if awaitingSave.contains(batch.id) { startSaving() }
        if awaitingTimeline.contains(batch.id) {
            await rebuildTimeline()
        } else {
            await timelineTask?.value // a rebuild already under way may be the one bringing this refresh's posts
            // A blyg that couldn't be reached brought no posts, but time has passed since the feed was built and
            // posts may have left its window. Unless a rebuild since this refresh began has seen to that already.
            if batch.failed, let last = lastRebuild, last < batch.began { await rebuildTimeline() }
        }
        refreshingTogether -= 1
    }

    /// One refresh of several blygs. Its blygs leave the save for its end, and the timeline for the next paced
    /// rebuild or its end, whichever comes first (see `awaitingSave` and `awaitingTimeline`).
    private final class Batch {
        /// The launch refresh: blygs a Studio follows that couldn't be reached before get their one retry in it.
        let retriesPending: Bool
        let began = ContinuousClock.now
        /// One of its blygs couldn't be refreshed.
        var failed = false
        init(retriesPending: Bool) { self.retriesPending = retriesPending }
        var id: ObjectIdentifier { ObjectIdentifier(self) }
    }

    func refresh(_ origin: URL) async { await refresh(origin, in: nil) }

    /// `batch`: this is one of several blygs in `refreshTogether`, which rebuilds the timeline and saves at its end.
    private func refresh(_ origin: URL, in batch: Batch?) async {
        guard let current = blyg(origin), !refreshing.contains(origin) else { return }
        refreshing.insert(origin)
        defer { refreshing.remove(origin) }
        let updated: SavedBlyg
        do {
            updated = try await Syncer(fetcher: fetcher).refresh(current)
        } catch {
            // A failed refresh records why and changes nothing else (§13.2).
            batch?.failed = true
            guard let index = library.blygs.firstIndex(where: { $0.origin == origin }) else { return }
            library.blygs[index].lastError = Self.describe(error)
            save(in: batch)
            // Alone (pull to refresh on a blyg's own page): time has passed since the feed was built all the same,
            // and posts may have left its window. Among several, `refreshTogether` sees to it at their end.
            if batch == nil { Task { await rebuildTimeline() } }
            return
        }
        guard let index = library.blygs.firstIndex(where: { $0.origin == origin }) else { return } // removed meanwhile
        // The sync worked on a copy taken before the network: keep settings changed while it ran.
        var merged = updated
        merged.postingAPI = library.blygs[index].postingAPI
        merged.studioFollows = library.blygs[index].studioFollows
        merged.pendingFollows = library.blygs[index].pendingFollows
        library.blygs[index] = merged
        save(in: batch)
        if let batch {
            awaitingTimeline.insert(batch.id)
            rebuildTimelineSoon()
        } else {
            await rebuildTimeline()
        }
        if merged.studioFollows != nil {
            await followStudiosNewSubscriptions(origin, in: batch, retryingPending: batch?.retriesPending ?? false)
        }
    }

    // MARK: Timeline and saving, off the main actor

    /// Runs work that blocks or takes long off the main actor, on Swift's shared pool.
    @concurrent nonisolated private static func offMain<T: Sendable>(_ work: @Sendable () throws -> T) async rethrows -> T {
        try work()
    }

    /// The Studio's subscription list, fetched and decoded off the main actor (the client's own calls stay on their caller's).
    @concurrent nonisolated private static func subscriptions(of client: StudioClient) async throws -> [StudioSubscription] {
        try await client.listSubscriptions()
    }

    /// The blygs a Studio follows, with the list fetched, decoded and turned into addresses off the main actor.
    @concurrent nonisolated private static func blygsFollowed(by client: StudioClient) async throws -> [URL] {
        blygOrigins(in: try await client.listSubscriptions())
    }

    @ObservationIgnored private var timelineTask: Task<Void, Never>?
    /// The library has changed since the rebuild under way took its copy.
    @ObservationIgnored private var timelineStale = false
    /// The refreshes of several blygs that have changed the library and not yet had it rebuilt into the
    /// timeline: the next paced rebuild covers them, or else each asks for a rebuild at its end.
    @ObservationIgnored private var awaitingTimeline: Set<ObjectIdentifier> = []
    /// The paced rebuild waiting its turn, if any.
    @ObservationIgnored private var pacedRebuild: Task<Void, Never>?
    /// When the last rebuild finished.
    @ObservationIgnored private var lastRebuild: ContinuousClock.Instant?
    /// Blygs unfollowed since the rebuild under way took its copy of the library, which still has them.
    @ObservationIgnored private var unfollowedDuringRebuild: Set<URL> = []

    /// Rebuilds the timeline from the library, off the main actor, and returns once it's in place.
    /// One rebuild runs at a time. A change that arrives meanwhile gets one more pass, so the newest library
    /// always has the last word and an older, slower rebuild can't land on top of a newer one.
    private func rebuildTimeline() async {
        // This rebuild takes along whatever a paced one was waiting to show.
        pacedRebuild?.cancel()
        pacedRebuild = nil
        timelineStale = true
        if timelineTask == nil {
            timelineTask = Task {
                while timelineStale {
                    timelineStale = false
                    unfollowedDuringRebuild = []
                    awaitingTimeline = [] // this copy of the library has everything they were waiting to show
                    let snapshot = library
                    let shown = rows
                    let build = buildTimeline
                    // Nil when nothing changed, as on most refreshes: compared, and the new rows let go, off the main actor.
                    let built = await Self.offMain { () -> [TimelineEntry]? in
                        let built = build(snapshot)
                        return built == shown ? nil : built
                    }
                    // A blyg unfollowed while this was being built is already out of the timeline: keep it out,
                    // even if it has been followed again since (its old posts went with it). That one pass over
                    // the rows is on the main actor; it takes an unfollow in the middle of a rebuild to need it.
                    let gone = unfollowedDuringRebuild
                    if let built {
                        show(gone.isEmpty ? built : built.filter { !gone.contains($0.origin) })
                    }
                    lastRebuild = .now
                }
                timelineTask = nil
            }
        }
        await timelineTask?.value
    }

    /// One of several blygs being refreshed at once has arrived: its posts should show soon, though not by
    /// rebuilding for every blyg. One rebuild is set to start once the rebuild under way (if any) has finished
    /// and `timelinePace` has passed since; blygs that arrive before then go into that same rebuild. Doesn't wait.
    private func rebuildTimelineSoon() {
        guard pacedRebuild == nil else { return }
        pacedRebuild = Task {
            while true {
                if let underWay = timelineTask { await underWay.value }
                // Cancelled: another rebuild was asked for meanwhile. It covers this one, and has cleared `pacedRebuild`.
                guard !Task.isCancelled else { return }
                guard let last = lastRebuild else { break }
                let wait = last + timelinePace - ContinuousClock.now
                guard wait > .zero else { break }
                try? await Task.sleep(for: wait)
                guard !Task.isCancelled else { return }
            }
            pacedRebuild = nil
            if !awaitingTimeline.isEmpty { await rebuildTimeline() }
        }
    }

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// The library has changed since the write under way took its copy.
    @ObservationIgnored private var unsaved = false
    /// The refreshes of several blygs that have changed the library and not yet had it saved: each will ask
    /// for a save at its end, unless a save asked for meanwhile has covered it.
    @ObservationIgnored private var awaitingSave: Set<ObjectIdentifier> = []
    /// The last write failed, so the file is behind the library. Tried again with the next save, or on leaving the app.
    @ObservationIgnored private var saveFailed = false
    @ObservationIgnored private var inBackground = false

    /// Saves the library soon, off the main actor. `batch`: the caller is one of several blygs being
    /// refreshed at once, and one save at their end covers them all. Not in the background, though: there iOS
    /// may stop the app before that end comes, so each blyg is saved as it arrives, as it always was.
    private func save(in batch: Batch? = nil) {
        guard store != nil else { return }
        if let batch, !inBackground {
            awaitingSave.insert(batch.id)
        } else {
            startSaving()
        }
    }

    /// One write runs at a time, each of the whole library as it is when the write starts. A change that arrives
    /// during a write gets one more pass, so writes can't overtake each other and the last one holds the newest library.
    private func startSaving() {
        guard let store else { return }
        unsaved = true
        guard saveTask == nil else { return }
        // Asked for here, not in the task: on the way to the background, the app may be suspended before the task
        // gets its turn. From now until the write ends, iOS lets the app finish before suspending it.
        let time = BackgroundTime("Saving the library")
        saveTask = Task {
            var retried = false
            while unsaved {
                unsaved = false
                let covered = awaitingSave // this copy of the library has everything they were waiting to save
                awaitingSave = []
                let snapshot = library
                do {
                    try await Self.offMain { try store.save(snapshot) }
                    saveFailed = false
                    retried = false
                } catch {
                    saveFailed = true
                    // Not covered after all. A refresh still running asks for its save at its end, as it would
                    // have, and that save is the retry.
                    awaitingSave.formUnion(covered)
                    Log.store.error("save failed: \(error.localizedDescription, privacy: .public)")
                    // In the background no later save may come to carry the retry: try once more now
                    // (once per failure in a row, so a full disk doesn't spin).
                    if inBackground, !retried {
                        retried = true
                        unsaved = true
                    }
                }
            }
            saveTask = nil
            time.end()
        }
    }

    /// Returns once the saves asked for so far have been written, or have failed (see `saveFailed`). Saves held
    /// back for the end of a refresh of several blygs aren't asked for until that end, or until `enteredBackground()`.
    func saveFinished() async {
        await saveTask?.value
    }

    /// The app has left the screen. iOS may suspend it within seconds and never resume it, so nothing waits any
    /// longer: what a refresh was holding back for its end is saved now, and so is each blyg that arrives from here on.
    func enteredBackground() {
        inBackground = true
        if !awaitingSave.isEmpty || saveFailed { startSaving() }
    }

    func becameActive() {
        inBackground = false
    }

    // MARK: Quote cards

    /// Cards fetched this session, by origin#id. Only successes are kept, so a failure is retried next time.
    @ObservationIgnored private var linkedCache: [String: LinkedPost] = [:]

    /// The cards that can be drawn now, from what's saved and fetched before: no network.
    func savedLinkedPosts(for document: ItemDocument, origin: URL) -> [LinkedPost] {
        LinkedPosts.candidates(in: document, origin: origin).compactMap { savedLinkedPost($0) ?? nil }
    }

    /// Every card, fetching from blygs this phone doesn't hold (two small JSON files each, see `LinkedPostLoader`).
    func linkedPosts(for document: ItemDocument, origin: URL) async -> [LinkedPost] {
        let candidates = LinkedPosts.candidates(in: document, origin: origin)
        var results: [LinkedPost?] = candidates.map { savedLinkedPost($0) ?? nil }
        let missing = candidates.indices.filter { savedLinkedPost(candidates[$0]) == nil }
        guard !missing.isEmpty else { return results.compactMap { $0 } }
        let loader = LinkedPostLoader(fetcher: fetcher)
        let fetched = await withTaskGroup(of: (Int, LinkedPost?).self) { group in
            for index in missing {
                let candidate = candidates[index]
                group.addTask { (index, await loader.load(candidate)) }
            }
            var out: [(Int, LinkedPost?)] = []
            for await result in group { out.append(result) }
            return out
        }
        for (index, post) in fetched {
            results[index] = post
            if let post { linkedCache[Self.cacheKey(candidates[index])] = post }
        }
        return results.compactMap { $0 }
    }

    /// `.some(card)` or `.some(nil)` (known not to be a card) when the answer is already here; nil when it needs a fetch.
    private func savedLinkedPost(_ candidate: LinkedPosts.Candidate) -> LinkedPost?? {
        if let cached = linkedCache[Self.cacheKey(candidate)] { return .some(cached) }
        guard let blyg = blyg(candidate.origin), let item = blyg.items[candidate.id] else { return nil }
        let fallback = candidate.href ?? BlygURL.resolve("f/\(candidate.id)/", against: candidate.origin) ?? candidate.origin
        if item.kind == ItemKind.withdrawn.rawValue {
            return .some(LinkedPost.from(nil, id: candidate.id, origin: candidate.origin, blygTitle: blyg.title, fallbackLink: fallback))
        }
        guard item.isShowable, let document = item.document else { return nil }
        if let href = candidate.href {
            guard let page = BlygURL.page(for: document, origin: candidate.origin), LinkedPosts.samePage(page, href) else { return .some(nil) }
        }
        return .some(LinkedPost.from(document, id: candidate.id, origin: candidate.origin, blygTitle: blyg.title, fallbackLink: fallback))
    }

    private static func cacheKey(_ candidate: LinkedPosts.Candidate) -> String {
        candidate.origin.absoluteString + "#" + candidate.id
    }

    /// The saved post a link points to, so links to posts on blygs you follow open in the app. Looked up in the
    /// library, not the timeline: a post too old for the main feed is still saved, and still opens here.
    func entry(forPage url: URL) -> TimelineEntry? {
        guard let (origin, id) = LinkedPosts.itemPage(url), let blyg = blyg(origin), let item = blyg.items[id],
              item.isShowable, let document = item.document,
              BlygURL.page(for: document, origin: origin).map({ LinkedPosts.samePage($0, url) }) == true else { return nil }
        return TimelineEntry(blyg: blyg, document: document, sortDate: item.sortDate(of: document))
    }

    /// Every saved post of one blyg, newest first, for that blyg's own page: the main feed shows only a recent
    /// window (`FeedWindow`), and this is where the rest can be read. Built off the main actor, when asked for.
    func posts(of origin: URL) async -> [TimelineEntry] {
        guard let blyg = blyg(origin) else { return [] }
        return await Self.offMain { blyg.posts() }
    }

    // MARK: Posting

    /// Blygs this phone can post to: connected, with a token still in the Keychain.
    var postingBlygs: [SavedBlyg] {
        library.blygs.filter { $0.postingAPI != nil && tokenHolders.contains($0.origin) }
    }

    func isConnected(_ origin: URL) -> Bool { postingBlygs.contains { $0.origin == origin } }

    enum ConnectFailure: Error, Equatable {
        case empty
        case rejected
        case needsHTTPS
        case noOwnerAPI(URL)
        case other(String)
    }

    /// Checks the token against the blyg's owner API, then saves it to the Keychain.
    func connect(_ origin: URL, token rawToken: String) async throws(ConnectFailure) {
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw .empty }
        guard StudioClient.isHTTPS(origin) else { throw .needsHTTPS } // before any request: the token is never sent
        let api = StudioClient.apiBase(forOrigin: origin)
        let capabilities: StudioCapabilities
        do {
            capabilities = try await StudioClient(api: api, token: token, transport: transport).getCapabilities()
        } catch let error as StudioError {
            if error.status == 401 || error.status == 403 { throw .rejected }
            if error.status == 404 { throw .noOwnerAPI(api) }
            throw .other(error.message)
        } catch {
            throw .other(error.localizedDescription)
        }
        let advertised = StudioClient.trustedAPI(URL(string: capabilities.endpoints.api), forOrigin: origin) ?? api
        guard let index = library.blygs.firstIndex(where: { $0.origin == origin }) else { return }
        do {
            try tokens.save(token, for: origin, title: library.blygs[index].title, api: advertised)
        } catch {
            throw .other("Couldn't save the token to the Keychain.")
        }
        tokenHolders.insert(origin)
        library.blygs[index].postingAPI = advertised
        save()
    }

    func disconnect(_ origin: URL) {
        tokens.remove(for: origin)
        tokenHolders.remove(origin)
        guard let index = library.blygs.firstIndex(where: { $0.origin == origin }) else { return }
        library.blygs[index].postingAPI = nil
        library.blygs[index].studioFollows = nil
        library.blygs[index].pendingFollows = nil
        save()
    }

    /// What following a Studio's subscriptions did, for the person to read.
    struct ImportResult: Equatable {
        var added = 0
        var alreadyFollowing = 0
        var failed: [String] = []
        /// How many of `failed` couldn't be reached and will be tried again when the app next opens.
        var retrying = 0
        var skippedFeeds = 0
    }

    /// Starts keeping in step with the connected Studio: follows, in this app, the blygs it subscribes to now,
    /// and remembers the list so later refreshes add only blygs new to it. Plain RSS subscriptions are skipped:
    /// this app reads blygs. Added one at a time, so a big list doesn't flood anyone's server.
    func importSubscriptions(from origin: URL, progress: (Int, Int) -> Void = { _, _ in }) async throws -> ImportResult {
        guard let blyg = blyg(origin), let api = blyg.postingAPI, let token = tokens.token(for: origin) else {
            throw ConnectFailure.other("Connect this blyg first.")
        }
        // While this runs, a refresh leaves this Studio's list alone: both would try the same blygs.
        importing.insert(origin)
        studioListsUnderWay += 1
        defer {
            importing.remove(origin)
            studioListsUnderWay -= 1
            forgetStudioFollowNotesIfIdle()
        }
        setStudioFollows(origin, []) // on at once, so the switch doesn't flick back while the list loads
        let subscriptions: [StudioSubscription]
        do {
            subscriptions = try await Self.subscriptions(of: StudioClient(api: api, token: token, transport: transport))
        } catch {
            setStudioFollows(origin, nil)
            throw error
        }
        var result = ImportResult()
        let blygs = subscriptions.filter { $0.kind == "blyg" }
        result.skippedFeeds = subscriptions.count - blygs.count
        let candidates = Self.blygOrigins(in: subscriptions)
        // Each is remembered as it's dealt with, and not before, as on any later refresh: if the app is closed
        // part-way, the next refresh takes up the ones not yet tried. Those followed here already need nothing
        // more, so they're remembered at once, together: one unfollowed while the others are tried doesn't come back.
        let followed = Set(library.blygs.map(\.origin))
        rememberStudioFollows(origin, candidates.filter(followed.contains), in: nil)
        for (index, candidate) in candidates.enumerated() {
            // Disconnected, unfollowed or switched off since (the list may still have been on its way): nothing more is followed.
            guard self.blyg(origin)?.studioFollows != nil else { break }
            progress(index, candidates.count)
            if followed.contains(candidate) {
                result.alreadyFollowing += 1
                continue
            }
            // Resolution can land on an origin already followed under another spelling: count what changed.
            let before = library.blygs.count
            let outcome = await followFromStudio(candidate, for: origin, wasPending: false, in: nil)
            if outcome == .followed {
                if library.blygs.count > before { result.added += 1 } else { result.alreadyFollowing += 1 }
            } else {
                result.failed.append(candidate.host() ?? candidate.absoluteString)
                if self.blyg(origin)?.pendingFollows?.contains(where: { $0.origin == candidate }) == true { result.retrying += 1 }
            }
        }
        progress(candidates.count, candidates.count)
        return result
    }

    #if DEBUG
    /// For the UI test of the launch retry (`-seedPendingFollow`): as if `candidate`, on the list of this
    /// connected blyg's Studio, had been tried once before and not reached.
    func seedPendingFollow(_ candidate: URL, for origin: URL) {
        guard let index = library.blygs.firstIndex(where: { $0.origin == origin }) else { return }
        library.blygs[index].studioFollows = library.blygs[index].studioFollows ?? []
        library.blygs[index].pendingFollows = [PendingFollow(origin: candidate, attempts: 1)]
        save()
    }
    #endif

    /// Stops keeping in step. Blygs already followed stay followed.
    func stopKeepingInStep(_ origin: URL) { setStudioFollows(origin, nil) }

    /// On refresh, while keeping in step: follow the blygs new to the Studio's list since last time. Never
    /// unfollows, and never re-adds one the person unfollowed here. Fails quietly; the next refresh tries again.
    ///
    /// A blyg that can't be reached isn't remembered as dealt with: it goes on the pending list with a count of
    /// tries. `retryingPending` (the launch refresh, once per launch) tries those again; no other refresh does.
    /// One that answers is followed and leaves the list; after `PendingFollow.maxAttempts` tries in all it's
    /// remembered as dealt with and left alone. One the Studio no longer lists leaves the list untried.
    func followStudiosNewSubscriptions(_ origin: URL, retryingPending: Bool = false) async {
        await followStudiosNewSubscriptions(origin, in: nil, retryingPending: retryingPending)
    }

    private func followStudiosNewSubscriptions(_ origin: URL, in batch: Batch?, retryingPending: Bool) async {
        // Not while the first import is working through the same list: both would try the same blygs.
        guard let blyg = blyg(origin), blyg.studioFollows != nil, !importing.contains(origin), let api = blyg.postingAPI,
              let token = tokens.token(for: origin) else { return }
        // From before the list is asked for until the last of it is dealt with, unfollows are noted (see `remove`).
        studioListsUnderWay += 1
        defer {
            studioListsUnderWay -= 1
            forgetStudioFollowNotesIfIdle()
        }
        guard let now = try? await Self.blygsFollowed(by: StudioClient(api: api, token: token, transport: transport)) else { return }
        // As things stand now the list has arrived, not as they were when it was asked for.
        guard let current = self.blyg(origin), let known = current.studioFollows, !importing.contains(origin) else { return } // switched off meanwhile
        // Sets, so a list of thousands isn't searched once per entry on the main actor.
        let listed = Set(now)
        var pending = current.pendingFollows ?? []
        if pending.contains(where: { !listed.contains($0.origin) }) {
            // The Studio has stopped following these: there's nothing left to try.
            pending.removeAll { !listed.contains($0.origin) }
            setPendingFollows(origin, pending, in: batch)
        }
        let waiting = Set(pending.map(\.origin))
        let retries = retryingPending ? pending.map(\.origin) : []
        // New to the Studio's list: not dealt with before, and not already waiting for the next launch.
        // (A list remembered by an earlier build may hold an address as the Studio spelled it: compared as it's spelled now.)
        let seen = Set(known.map { BlygURL.candidateOrigin(from: $0.absoluteString) ?? $0 })
        let fresh = now.filter { !seen.contains($0) && !waiting.contains($0) }
        if !fresh.isEmpty || !retries.isEmpty { // most refreshes find nothing new, and needn't look through the library at all
            // Remembered as soon as each has been dealt with, and not before. If the app is closed part-way, the next
            // refresh takes up the ones not yet tried and leaves alone the ones that were (one unfollowed here
            // since doesn't come back). Those already followed here need nothing more, so they're remembered at once.
            let followed = Set(library.blygs.map(\.origin))
            rememberStudioFollows(origin, fresh.filter(followed.contains), in: batch)
            // One at a time, the retries first; each is tried once in this pass.
            for candidate in retries + fresh.filter({ !followed.contains($0) }) {
                // Switched off, disconnected or unfollowed meanwhile: nothing more is followed.
                guard let state = self.blyg(origin), state.studioFollows != nil else { return }
                // A retry that stopped waiting while the earlier ones were tried (followed by hand, say) is done with.
                let isRetry = waiting.contains(candidate)
                if isRetry, state.pendingFollows?.contains(where: { $0.origin == candidate }) != true { continue }
                _ = await followFromStudio(candidate, for: origin, wasPending: isRetry, in: batch)
            }
        }
        guard let after = self.blyg(origin), after.studioFollows != nil else { return } // switched off during the adds
        // The Studio's own order, without any it has dropped, and without those still waiting to be tried again.
        let stillWaiting = Set((after.pendingFollows ?? []).map(\.origin))
        setStudioFollows(origin, stillWaiting.isEmpty ? now : now.filter { !stillWaiting.contains($0) }, in: batch)
    }

    /// How a try at following a blyg from a Studio's list went.
    private enum FollowOutcome {
        case followed
        /// No blyg answered at its address: a network error, a timeout, or something there that isn't a blyg.
        /// It may answer another day.
        case unreachable
        /// It isn't an address this app can follow at all, so trying again can't help.
        case impossible
    }

    /// The first imports under way: a refresh leaves those Studios' lists to them.
    @ObservationIgnored private var importing: Set<URL> = []
    /// How many Studios' lists are being worked through right now, by a refresh or a first import.
    @ObservationIgnored private var studioListsUnderWay = 0
    /// The addresses from Studios' lists being asked after right now, each by one request that every list wanting it shares.
    @ObservationIgnored private var followsUnderWay: [URL: Task<FollowOutcome, Never>] = [:]
    /// Blygs unfollowed by hand while a Studio's list was being worked through: neither an answer still on its
    /// way nor a later turn on that list follows them again.
    @ObservationIgnored private var unfollowedDuringStudioFollow: Set<URL> = []
    /// Addresses followed by hand while a Studio's list was asking after them: dealt with, even if the list's own request then fails.
    @ObservationIgnored private var followedByHandDuringStudioFollow: Set<URL> = []
    /// Addresses from Studios' lists tried since the app opened that couldn't be reached, with the tries counted
    /// against each so far. None is asked twice in one launch, whichever list or refresh wants it: two Studios
    /// listing one dead address make one try between them, and a list that meets it later takes up the same count.
    @ObservationIgnored private var unreachableThisLaunch: [URL: Int] = [:]

    private func forgetStudioFollowNotesIfIdle() {
        guard studioListsUnderWay == 0, followsUnderWay.isEmpty else { return }
        unfollowedDuringStudioFollow = []
        followedByHandDuringStudioFollow = []
    }

    /// Follows `candidate`, which is on the list of `origin`'s Studio, and writes down how it went: one try at
    /// most per address per launch of the app, shared by every list it's on. `wasPending`: this is a retry of
    /// one that list had waiting, not a blyg new to it.
    private func followFromStudio(_ candidate: URL, for origin: URL, wasPending: Bool, in batch: Batch?) async -> FollowOutcome {
        // One followed already (by hand, perhaps while the earlier ones were being added) needs no adding, but it
        // has been dealt with and is remembered like the rest: unfollowed later, it mustn't look new next time.
        // The same for one unfollowed by hand since this list began to be worked through: it stays unfollowed.
        if blyg(candidate) != nil || unfollowedDuringStudioFollow.contains(candidate) {
            recordFollow(.followed, of: candidate, for: origin, wasPending: wasPending, in: batch)
            return .followed
        }
        // Tried already since the app opened, and counted then on every list it was waiting on.
        if unreachableThisLaunch[candidate] != nil {
            if !wasPending { waitWithoutTrying(candidate, for: origin, in: batch) }
            return .unreachable
        }
        // Another list is asking after this address right now. Its answer serves both, and the try is counted
        // once, by the list that asked, on every list the address waits on.
        if let underWay = followsUnderWay[candidate] {
            let outcome = await underWay.value
            if outcome != .unreachable {
                recordFollow(outcome, of: candidate, for: origin, wasPending: wasPending, in: batch)
            } else if !wasPending {
                waitWithoutTrying(candidate, for: origin, in: batch)
            }
            return outcome
        }
        let task = Task { () -> FollowOutcome in
            var outcome = FollowOutcome.followed
            var recorded = false
            do {
                try await self.add(candidate.absoluteString, in: batch, forStudio: true) {
                    // Remembered the moment the blyg is in the library, in the same save, and before its posts are
                    // fetched: unfollowed during that fetch with the app then closed, it mustn't look new next time.
                    self.recordFollow(.followed, of: candidate, for: origin, wasPending: wasPending, in: batch)
                    recorded = true
                }
            } catch Resolver.Failure.notFound {
                // Followed by hand while this request was out: dealt with, though this request found nothing.
                let byHand = self.followedByHandDuringStudioFollow.contains(candidate) || self.blyg(candidate) != nil
                outcome = byHand ? .followed : .unreachable
            } catch {
                outcome = .impossible
            }
            // Written down before any other list waiting on this answer hears it.
            if !recorded {
                let tries = self.recordFollow(outcome, of: candidate, for: origin, wasPending: wasPending, in: batch)
                if outcome == .unreachable { self.unreachableThisLaunch[candidate] = tries ?? 1 }
            }
            return outcome
        }
        followsUnderWay[candidate] = task
        let outcome = await task.value
        followsUnderWay[candidate] = nil
        forgetStudioFollowNotesIfIdle()
        return outcome
    }

    /// Writes down how a try at following `candidate`, from the list of `origin`'s Studio, went: dealt with for
    /// good (followed, impossible, or out of tries), or kept pending with one more try counted against it.
    /// It's one address and it was asked once, so the try counts on every list it's waiting on, not only this one.
    /// `wasPending`: it was a retry. If it has stopped waiting on this list since (followed by hand while the
    /// answer was on its way), it has been dealt with here, and a late answer changes nothing.
    /// Returns the tries now counted against it, or nil if no list was there to count them.
    @discardableResult
    private func recordFollow(_ outcome: FollowOutcome, of candidate: URL, for origin: URL, wasPending: Bool, in batch: Batch?) -> Int? {
        func tries(_ index: Int) -> Int? { library.blygs[index].pendingFollows?.first { $0.origin == candidate }?.attempts }
        let lists = library.blygs.indices.filter { index in
            guard library.blygs[index].studioFollows != nil else { return false } // switched off meanwhile: nothing is kept
            return tries(index) != nil || (library.blygs[index].origin == origin && !wasPending)
        }
        guard !lists.isEmpty else { return nil }
        let attempts = (lists.compactMap(tries).max() ?? 0) + 1
        for index in lists {
            var pending = library.blygs[index].pendingFollows ?? []
            pending.removeAll { $0.origin == candidate }
            if outcome == .unreachable, attempts < PendingFollow.maxAttempts {
                pending.append(PendingFollow(origin: candidate, attempts: attempts))
                library.blygs[index].studioFollows?.removeAll { $0 == candidate }
            } else if library.blygs[index].studioFollows?.contains(candidate) == false {
                library.blygs[index].studioFollows?.append(candidate)
            }
            library.blygs[index].pendingFollows = pending.isEmpty ? nil : pending
        }
        save(in: batch)
        return attempts
    }

    /// `candidate` is new to the list of `origin`'s Studio, and has already been tried since the app opened and not
    /// reached. It isn't asked again in this launch: it waits on this list too, with the tries already counted
    /// against it; or, if they were its last, it's remembered here as dealt with as well.
    private func waitWithoutTrying(_ candidate: URL, for origin: URL, in batch: Batch?) {
        guard let index = library.blygs.firstIndex(where: { $0.origin == origin }), library.blygs[index].studioFollows != nil,
              library.blygs[index].pendingFollows?.contains(where: { $0.origin == candidate }) != true else { return }
        // The count as it stood after this launch's try, kept apart from the lists: the list that made the try
        // may have been switched off or disconnected since.
        let counted = unreachableThisLaunch[candidate] ?? 1
        if counted >= PendingFollow.maxAttempts {
            if library.blygs[index].studioFollows?.contains(candidate) == false { library.blygs[index].studioFollows?.append(candidate) }
        } else {
            library.blygs[index].pendingFollows = (library.blygs[index].pendingFollows ?? []) + [PendingFollow(origin: candidate, attempts: counted)]
            library.blygs[index].studioFollows?.removeAll { $0 == candidate }
        }
        save(in: batch)
    }

    private func setPendingFollows(_ origin: URL, _ pending: [PendingFollow], in batch: Batch?) {
        guard let index = library.blygs.firstIndex(where: { $0.origin == origin }) else { return }
        library.blygs[index].pendingFollows = pending.isEmpty ? nil : pending
        save(in: batch)
    }

    /// The blygs in a Studio's list, in its order, each once: one listed twice is still tried, and counted, once.
    /// Each address is spelled the way this app spells one typed in (a trailing slash, no query), so "the same
    /// address" means the same thing on every list, in the pending list, and when a blyg is followed by hand.
    nonisolated private static func blygOrigins(in subscriptions: [StudioSubscription]) -> [URL] {
        var listed: Set<URL> = []
        return subscriptions.filter { $0.kind == "blyg" }
            .compactMap { subscription -> URL? in
                guard let text = subscription.origin?.trimmingCharacters(in: .whitespaces) else { return nil }
                return BlygURL.candidateOrigin(from: text) ?? URL(string: text)
            }
            .filter { listed.insert($0).inserted }
    }

    /// Adds to the remembered list, if keeping in step is still on.
    private func rememberStudioFollows(_ origin: URL, _ more: [URL], in batch: Batch?) {
        guard !more.isEmpty, let index = library.blygs.firstIndex(where: { $0.origin == origin }),
              library.blygs[index].studioFollows != nil else { return }
        library.blygs[index].studioFollows?.append(contentsOf: more)
        save(in: batch)
    }

    private func setStudioFollows(_ origin: URL, _ follows: [URL]?, in batch: Batch? = nil) {
        guard let index = library.blygs.firstIndex(where: { $0.origin == origin }) else { return }
        library.blygs[index].studioFollows = follows
        // Off: nothing waits to be tried again. (Switching on again starts from the Studio's list as it is then.)
        if follows == nil { library.blygs[index].pendingFollows = nil }
        save(in: batch)
    }

    func poster(for origin: URL) -> Poster? {
        guard let blyg = blyg(origin), let api = blyg.postingAPI, let token = tokens.token(for: origin) else { return nil }
        return Poster(client: StudioClient(api: api, token: token, transport: transport), origin: origin)
    }

    static func describe(_ failure: ConnectFailure) -> String {
        switch failure {
        case .empty: return "Paste the token first."
        case .rejected: return "The blyg didn't accept that token. Check you copied all of it, and that it's a REST API token."
        // No "you can still read it" here: iOS blocks plain-http loads to public hosts, so often it can't be read either.
        case .needsHTTPS: return StudioClient.needsHTTPS.message + " This blyg's address is http, so this app can't post to it. If it also has an https address, follow that one to post."
        case .noOwnerAPI(let api): return "There's no Blygger Studio owner API at \(api.absoluteString), so this app can't post to this blyg. You can still read it."
        case .other(let message): return message
        }
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case Syncer.Failure.manifest(let status): return status.map { "Its blyg.json answered \($0)." } ?? "Couldn't reach it."
        case Syncer.Failure.index(let status): return status.map { "Its archive index answered \($0)." } ?? "Couldn't read its archive index."
        case Syncer.Failure.rateLimited: return "It asked us to slow down. Try again later."
        case Resolver.Failure.notAURL: return "That doesn't look like a web address."
        case Resolver.Failure.notFound(let tried):
            let list = tried.map { "• \($0.absoluteString)" }.joined(separator: "\n")
            return "No blyg found there. Tried:\n\(list)"
        default: return error.localizedDescription
        }
    }
}
