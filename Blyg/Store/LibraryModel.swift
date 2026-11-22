import Foundation
import os
import Observation

/// The app's state: the saved library, kept in sync with disk. Opens at once from what's saved;
/// the network only ever adds to it.
@Observable
final class LibraryModel {
    private(set) var library: Library
    private(set) var timeline: [TimelineEntry] = []
    private(set) var refreshing: Set<URL> = []
    /// Set when the saved file couldn't be read at launch, so the app can say so instead of silently starting empty.
    private(set) var loadProblem: LibraryStore.LoadOutcome?

    private let store: LibraryStore?
    private let fetcher: any Fetching
    private let tokens: any TokenStore
    private let transport: any HTTPTransport

    init(store: LibraryStore?, fetcher: any Fetching, tokens: any TokenStore = MemoryTokenStore(),
         transport: any HTTPTransport = URLSessionTransport()) {
        self.store = store
        self.fetcher = fetcher
        self.tokens = tokens
        self.transport = transport
        if let store {
            let (library, outcome) = store.load()
            self.library = library
            if outcome == .recoveredFromBackup || outcome == .unreadable { loadProblem = outcome }
        } else {
            self.library = Library()
        }
        timeline = library.timeline()
    }

    var isRefreshingAny: Bool { !refreshing.isEmpty }

    func blyg(_ origin: URL) -> SavedBlyg? { library.blygs.first { $0.origin == origin } }

    /// Resolves a URL to a blyg, adds it, then fetches its items. Returns the identity origin.
    @discardableResult
    func add(_ input: String) async throws -> URL {
        let resolved = try await Resolver(fetcher: fetcher).resolve(input)
        if blyg(resolved.origin) == nil {
            library.blygs.append(SavedBlyg(origin: resolved.origin, manifest: resolved.manifest, addedAt: .now))
            save()
        }
        await refresh(resolved.origin)
        return resolved.origin
    }

    func remove(_ origin: URL) {
        tokens.remove(for: origin)
        library.blygs.removeAll { $0.origin == origin }
        timeline = library.timeline()
        save()
    }

    func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for blyg in library.blygs {
                group.addTask { await self.refresh(blyg.origin) }
            }
        }
    }

    /// Coming back to the app: catch up without hammering anyone. Your own blygs are refreshed after 30 seconds,
    /// so a post made from the share sheet (which can't tell the app) shows up; the others after 10 minutes.
    func refreshStale(now: Date = .now) async {
        let own = Set(postingBlygs.map(\.origin))
        let stale = library.blygs.filter { blyg in
            guard let last = blyg.lastRefresh else { return true }
            return now.timeIntervalSince(last) > (own.contains(blyg.origin) ? 30 : 600)
        }
        await withTaskGroup(of: Void.self) { group in
            for blyg in stale {
                group.addTask { await self.refresh(blyg.origin) }
            }
        }
    }

    func refresh(_ origin: URL) async {
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
            save()
            return
        }
        guard let index = library.blygs.firstIndex(where: { $0.origin == origin }) else { return } // removed meanwhile
        library.blygs[index] = updated
        timeline = library.timeline()
        save()
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
        library.blygs.filter { $0.postingAPI != nil && tokens.token(for: $0.origin) != nil }
    }

    func isConnected(_ origin: URL) -> Bool { postingBlygs.contains { $0.origin == origin } }

    enum ConnectFailure: Error, Equatable {
        case empty
        case rejected
        case noOwnerAPI(URL)
        case other(String)
    }

    /// Checks the token against the blyg's owner API, then saves it to the Keychain.
    func connect(_ origin: URL, token rawToken: String) async throws(ConnectFailure) {
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw .empty }
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
        let advertised = URL(string: capabilities.endpoints.api) ?? api
        guard let index = library.blygs.firstIndex(where: { $0.origin == origin }) else { return }
        do {
            try tokens.save(token, for: origin, title: library.blygs[index].title, api: advertised)
        } catch {
            throw .other("Couldn't save the token to the Keychain.")
        }
        library.blygs[index].postingAPI = advertised
        save()
    }

    func disconnect(_ origin: URL) {
        tokens.remove(for: origin)
        guard let index = library.blygs.firstIndex(where: { $0.origin == origin }) else { return }
        library.blygs[index].postingAPI = nil
        save()
    }

    /// What following a Studio's subscriptions did, for the person to read.
    struct ImportResult: Equatable {
        var added = 0
        var alreadyFollowing = 0
        var failed: [String] = []
        var skippedFeeds = 0
    }

    /// Follows, in this app, the blygs the connected Studio subscribes to. Plain RSS subscriptions are skipped:
    /// this app reads blygs. Added one at a time, so a big list doesn't flood anyone's server.
    func importSubscriptions(from origin: URL, progress: (Int, Int) -> Void = { _, _ in }) async throws -> ImportResult {
        guard let blyg = blyg(origin), let api = blyg.postingAPI, let token = tokens.token(for: origin) else {
            throw ConnectFailure.other("Connect this blyg first.")
        }
        let subscriptions = try await StudioClient(api: api, token: token, transport: transport).listSubscriptions()
        var result = ImportResult()
        let blygs = subscriptions.filter { $0.kind == "blyg" }
        result.skippedFeeds = subscriptions.count - blygs.count
        let candidates = blygs.compactMap { $0.origin.flatMap { URL(string: $0.trimmingCharacters(in: .whitespaces)) } }
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

    func poster(for origin: URL) -> Poster? {
        guard let blyg = blyg(origin), let api = blyg.postingAPI, let token = tokens.token(for: origin) else { return nil }
        return Poster(client: StudioClient(api: api, token: token, transport: transport), origin: origin)
    }

    static func describe(_ failure: ConnectFailure) -> String {
        switch failure {
        case .empty: return "Paste the token first."
        case .rejected: return "The blyg didn't accept that token. Check you copied all of it, and that it's a REST API token."
        case .noOwnerAPI(let api): return "There's no Blygger Studio owner API at \(api.absoluteString), so this app can't post to this blyg. You can still read it."
        case .other(let message): return message
        }
    }

    private func save() {
        guard let store else { return }
        do { try store.save(library) } catch { Log.store.error("save failed: \(error.localizedDescription, privacy: .public)") }
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
