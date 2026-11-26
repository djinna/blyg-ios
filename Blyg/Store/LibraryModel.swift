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
    private(set) var timeline: [TimelineEntry] = []
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
    /// The blygs with a token in the Keychain. Remembered here because asking the Keychain is a blocking call
    /// to another process, and views ask on every redraw: once per blyg during a refresh. Only this model
    /// saves or removes tokens (the Share extension just reads them), so it can't go stale while the app runs.
    private var tokenHolders: Set<URL> = []

    /// `buildTimeline` is `Library.timeline()` in the app; tests pass their own to count and hold rebuilds.
    init(store: (any LibraryPersisting)?, fetcher: any Fetching, tokens: any TokenStore = MemoryTokenStore(),
         transport: any HTTPTransport = URLSessionTransport(),
         buildTimeline: @escaping @Sendable (Library) -> [TimelineEntry] = { $0.timeline() }) {
        self.store = store
        self.fetcher = fetcher
        self.tokens = tokens
        self.transport = transport
        self.buildTimeline = buildTimeline
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
        timeline = buildTimeline(library)
    }

    var isRefreshingAny: Bool { !refreshing.isEmpty || refreshingTogether > 0 }

    func blyg(_ origin: URL) -> SavedBlyg? { library.blygs.first { $0.origin == origin } }

    /// Resolves a URL to a blyg, adds it, then fetches its items. Returns the identity origin.
    @discardableResult
    func add(_ input: String) async throws -> URL { try await add(input, in: nil) }

    @discardableResult
    private func add(_ input: String, in batch: Batch?) async throws -> URL {
        let resolved = try await Resolver(fetcher: fetcher).resolve(input)
        if blyg(resolved.origin) == nil {
            library.blygs.append(SavedBlyg(origin: resolved.origin, manifest: resolved.manifest, addedAt: .now))
            save(in: batch)
        }
        await refresh(resolved.origin, in: batch)
        return resolved.origin
    }

    func remove(_ origin: URL) {
        tokens.remove(for: origin)
        tokenHolders.remove(origin)
        library.blygs.removeAll { $0.origin == origin }
        // The same rows a rebuild would leave, without rescanning every post on the main actor.
        // A rebuild under way took its copy of the library with this blyg in it: it leaves these rows out too.
        timeline.removeAll { $0.origin == origin }
        if timelineTask != nil { unfollowedDuringRebuild.insert(origin) }
        save()
    }

    func refreshAll() async {
        await refreshTogether(library.blygs.map(\.origin))
    }

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

    /// Refreshes several blygs at once. Each one's result goes into the library as it arrives, but the timeline
    /// is rebuilt once and the file saved once, when all have answered: both cost time in proportion to the whole
    /// library, so doing them per blyg made a refresh of many blygs cost many times over.
    private func refreshTogether(_ origins: [URL]) async {
        guard !origins.isEmpty else { return }
        refreshingTogether += 1
        let batch = Batch()
        await withTaskGroup(of: Void.self) { group in
            for origin in origins {
                group.addTask { await self.refresh(origin, in: batch) }
            }
        }
        // Only what this refresh's own blygs left for it and nothing has saved or rebuilt since: a second
        // refresh running alongside doesn't finish this one's work early, or do it twice.
        if awaitingSave.contains(batch.id) { startSaving() }
        if awaitingTimeline.contains(batch.id) {
            await rebuildTimeline()
        } else {
            await timelineTask?.value // a rebuild already under way may be the one bringing this refresh's posts
        }
        refreshingTogether -= 1
    }

    /// One refresh of several blygs. Its blygs leave the save and the timeline rebuild for its end (see
    /// `awaitingSave` and `awaitingTimeline`).
    private final class Batch {
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
            guard let index = library.blygs.firstIndex(where: { $0.origin == origin }) else { return }
            library.blygs[index].lastError = Self.describe(error)
            save(in: batch)
            return
        }
        guard let index = library.blygs.firstIndex(where: { $0.origin == origin }) else { return } // removed meanwhile
        // The sync worked on a copy taken before the network: keep settings changed while it ran.
        var merged = updated
        merged.postingAPI = library.blygs[index].postingAPI
        merged.studioFollows = library.blygs[index].studioFollows
        library.blygs[index] = merged
        save(in: batch)
        if let batch {
            awaitingTimeline.insert(batch.id)
        } else {
            await rebuildTimeline()
        }
        if merged.studioFollows != nil { await followStudiosNewSubscriptions(origin, in: batch) }
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
    /// timeline: each will ask for that at its end, unless a rebuild asked for meanwhile has covered it.
    @ObservationIgnored private var awaitingTimeline: Set<ObjectIdentifier> = []
    /// Blygs unfollowed since the rebuild under way took its copy of the library, which still has them.
    @ObservationIgnored private var unfollowedDuringRebuild: Set<URL> = []

    /// Rebuilds the timeline from the library, off the main actor, and returns once it's in place.
    /// One rebuild runs at a time. A change that arrives meanwhile gets one more pass, so the newest library
    /// always has the last word and an older, slower rebuild can't land on top of a newer one.
    private func rebuildTimeline() async {
        awaitingTimeline = []
        timelineStale = true
        if timelineTask == nil {
            timelineTask = Task {
                while timelineStale {
                    timelineStale = false
                    unfollowedDuringRebuild = []
                    let snapshot = library
                    let shown = timeline
                    let build = buildTimeline
                    // Compared here too: setting `timeline` compares every row with the old ones first (it's
                    // observed, and rows are Equatable), which on the main actor is one more pass over them all.
                    let (built, unchanged) = await Self.offMain { () -> ([TimelineEntry], Bool) in
                        let built = build(snapshot)
                        return (built, built == shown)
                    }
                    // A blyg unfollowed while this was being built is already out of the timeline: keep it out,
                    // even if it has been followed again since (its old posts went with it).
                    let gone = unfollowedDuringRebuild
                    if !gone.isEmpty {
                        timeline = built.filter { !gone.contains($0.origin) }
                    } else if !unchanged {
                        timeline = built
                    } // else nothing new, as on most refreshes: the rows stay as they are
                }
                timelineTask = nil
            }
        }
        await timelineTask?.value
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
        awaitingSave = []
        unsaved = true
        guard saveTask == nil else { return }
        // Asked for here, not in the task: on the way to the background, the app may be suspended before the task
        // gets its turn. From now until the write ends, iOS lets the app finish before suspending it.
        let time = BackgroundTime("Saving the library")
        saveTask = Task {
            var retried = false
            while unsaved {
                unsaved = false
                let snapshot = library
                do {
                    try await Self.offMain { try store.save(snapshot) }
                    saveFailed = false
                } catch {
                    saveFailed = true
                    Log.store.error("save failed: \(error.localizedDescription, privacy: .public)")
                    // In the background no later save may come to carry the retry: try once more now.
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

    /// The saved post a link points to, so links to posts on blygs you follow open in the app.
    func entry(forPage url: URL) -> TimelineEntry? {
        guard let (origin, id) = LinkedPosts.itemPage(url) else { return nil }
        return timeline.first { entry in
            entry.origin == origin && entry.document.id == id
                && BlygURL.page(for: entry.document, origin: origin).map { LinkedPosts.samePage($0, url) } == true
        }
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
        save()
    }

    /// What following a Studio's subscriptions did, for the person to read.
    struct ImportResult: Equatable {
        var added = 0
        var alreadyFollowing = 0
        var failed: [String] = []
        var skippedFeeds = 0
    }

    /// Starts keeping in step with the connected Studio: follows, in this app, the blygs it subscribes to now,
    /// and remembers the list so later refreshes add only blygs new to it. Plain RSS subscriptions are skipped:
    /// this app reads blygs. Added one at a time, so a big list doesn't flood anyone's server.
    func importSubscriptions(from origin: URL, progress: (Int, Int) -> Void = { _, _ in }) async throws -> ImportResult {
        guard let blyg = blyg(origin), let api = blyg.postingAPI, let token = tokens.token(for: origin) else {
            throw ConnectFailure.other("Connect this blyg first.")
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
        setStudioFollows(origin, candidates)
        for (index, candidate) in candidates.enumerated() {
            progress(index, candidates.count)
            if library.blygs.contains(where: { $0.origin == candidate }) {
                result.alreadyFollowing += 1
                continue
            }
            do {
                // Resolution can land on an origin already followed under another spelling: count what changed.
                let before = library.blygs.count
                try await add(candidate.absoluteString)
                if library.blygs.count > before { result.added += 1 } else { result.alreadyFollowing += 1 }
            } catch {
                result.failed.append(candidate.host() ?? candidate.absoluteString)
            }
        }
        progress(candidates.count, candidates.count)
        return result
    }

    /// Stops keeping in step. Blygs already followed stay followed.
    func stopKeepingInStep(_ origin: URL) { setStudioFollows(origin, nil) }

    /// On refresh, while keeping in step: follow the blygs new to the Studio's list since last time. Never
    /// unfollows, and never re-adds one the person unfollowed here. Fails quietly; the next refresh tries again.
    func followStudiosNewSubscriptions(_ origin: URL) async { await followStudiosNewSubscriptions(origin, in: nil) }

    private func followStudiosNewSubscriptions(_ origin: URL, in batch: Batch?) async {
        guard let blyg = blyg(origin), let known = blyg.studioFollows, let api = blyg.postingAPI,
              let token = tokens.token(for: origin),
              let now = try? await Self.blygsFollowed(by: StudioClient(api: api, token: token, transport: transport))
        else { return }
        let seen = Set(known)
        for new in now where !seen.contains(new) {
            // Switched off, disconnected or unfollowed meanwhile: nothing more is followed.
            guard let index = library.blygs.firstIndex(where: { $0.origin == origin }),
                  library.blygs[index].studioFollows != nil else { return }
            if self.blyg(new) == nil { _ = try? await add(new.absoluteString, in: batch) }
            // Remembered one at a time, each once it has been tried and not before. If the app is closed
            // part-way, the next refresh takes up the ones not yet tried, and leaves alone the ones that were
            // (one unfollowed here since doesn't come back).
            if let index = library.blygs.firstIndex(where: { $0.origin == origin }), library.blygs[index].studioFollows != nil {
                library.blygs[index].studioFollows?.append(new)
                save(in: batch)
            }
        }
        guard self.blyg(origin)?.studioFollows != nil else { return } // switched off during the adds
        setStudioFollows(origin, now, in: batch) // the Studio's own order, without any it has dropped
    }

    nonisolated private static func blygOrigins(in subscriptions: [StudioSubscription]) -> [URL] {
        subscriptions.filter { $0.kind == "blyg" }
            .compactMap { $0.origin.flatMap { URL(string: $0.trimmingCharacters(in: .whitespaces)) } }
    }

    private func setStudioFollows(_ origin: URL, _ follows: [URL]?, in batch: Batch? = nil) {
        guard let index = library.blygs.firstIndex(where: { $0.origin == origin }) else { return }
        library.blygs[index].studioFollows = follows
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
