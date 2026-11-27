import Foundation
import Testing
@testable import Blyg

/// "Now" for the main feed's window in tests: the fixture blyg's own, a day after its newest post. The fixture
/// posts are dated November 2026, and measured from the real date they'd leave the 14-day window for good.
let feedNow = Fixtures.now

extension LibraryModel {
    /// A model that keeps nothing on disk and measures the feed's window from `feedNow`.
    convenience init(inMemoryWith fetcher: any Fetching, tokens: any TokenStore = MemoryTokenStore(),
                     transport: any HTTPTransport = URLSessionTransport()) {
        self.init(store: nil, fetcher: fetcher, tokens: tokens, transport: transport, buildTimeline: { $0.timeline(now: feedNow) })
    }
}

/// Whether this is the main thread. A function of its own, because `Thread.isMainThread` can't be read in async code.
func onMainThread() -> Bool { Thread.isMainThread }

/// Lets the main actor's other work run until `condition` holds. Records a failure after 5 s rather than hanging.
@MainActor func until(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
    let deadline = ContinuousClock.now + .seconds(5)
    while !condition() {
        if ContinuousClock.now > deadline {
            Issue.record("timed out waiting", sourceLocation: sourceLocation)
            return
        }
        try? await Task.sleep(for: .milliseconds(2))
    }
}

/// Blocks the thread that reaches it until released, as slow decoding or a slow disk would. Only the first
/// caller is held. If nobody releases it within 3 s (because the code that would is stuck behind the blocked
/// thread: the main actor's), it gives up and says so.
final class Hold: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var reached = false
    private var timedOut = false

    var wasReached: Bool { lock.withLock { reached } }
    var gaveUp: Bool { lock.withLock { timedOut } }

    func wait() {
        let first = lock.withLock { () -> Bool in
            defer { reached = true }
            return !reached
        }
        guard first else { return }
        if semaphore.wait(timeout: .now() + 3) == .timedOut { lock.withLock { timedOut = true } }
    }

    func release() { semaphore.signal() }
}

/// Keeps whoever reaches it waiting until released, without blocking a thread: a slow server, for putting the
/// steps of a test in order. (`Hold` blocks its thread, which is the point where a test asks whether the main
/// actor is free; but Swift's pool has few threads, and a test that blocks several at once stalls every test.)
final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var open = false
    private var reached = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    var wasReached: Bool { lock.withLock { reached } }

    func wait() async {
        await withCheckedContinuation { continuation in
            let through = lock.withLock { () -> Bool in
                reached = true
                if !open { waiting.append(continuation) }
                return open
            }
            if through { continuation.resume() }
        }
    }

    func release() {
        let waiters = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            open = true
            defer { waiting = [] }
            return waiting
        }
        for waiter in waiters { waiter.resume() }
    }
}

/// A fetcher that answers from a table, records what was asked, and can redirect.
final class FakeFetcher: Fetching, @unchecked Sendable {
    struct Answer {
        var status: Int = 200
        var body: String
        var finalURL: String?
    }

    private let lock = NSLock()
    private var answers: [String: Answer]
    private(set) var requested: [String] = []
    private var holds: [String: Hold] = [:]
    private var gates: [String: Gate] = [:]
    private var onMain = false

    init(_ answers: [String: Answer] = [:]) { self.answers = answers }

    /// True if any request ran on the main thread: the caller's fetching and decoding were on the main actor.
    var askedOnMainThread: Bool { lock.withLock { onMain } }

    /// The next request for `url` blocks its thread until the returned hold is released.
    func hold(_ url: String) -> Hold {
        let hold = Hold()
        lock.withLock { holds[url] = hold }
        return hold
    }

    /// Requests for `url` wait, without blocking a thread, until the returned gate is released.
    func delay(_ url: String) -> Gate {
        let gate = Gate()
        lock.withLock { gates[url] = gate }
        return gate
    }

    /// The fictional blyg from the app's DEBUG fixtures.
    static func sample() -> FakeFetcher {
        FakeFetcher(Fixtures.responses.mapValues { Answer(status: $0.status, body: $0.body) })
    }

    func set(_ url: String, _ answer: Answer?) {
        lock.withLock { answers[url] = answer }
    }

    var requestCount: Int { lock.withLock { requested.count } }

    func get(_ url: URL) async throws -> FetchResult {
        let main = onMainThread()
        let (hold, gate) = lock.withLock { () -> (Hold?, Gate?) in
            requested.append(url.absoluteString)
            if main { onMain = true }
            return (holds[url.absoluteString], gates[url.absoluteString])
        }
        hold?.wait()
        await gate?.wait()
        let answer = lock.withLock { answers[url.absoluteString] } // as it is once the wait is over
        guard let answer else { return FetchResult(data: Data("Not Found".utf8), finalURL: url, status: 404, contentType: "text/plain") }
        let final = answer.finalURL.flatMap(URL.init(string:)) ?? url
        return FetchResult(data: Data(answer.body.utf8), finalURL: final, status: answer.status, contentType: nil)
    }
}

func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(type, from: Data(json.utf8))
}

extension SavedBlyg {
    static func sample() throws -> SavedBlyg {
        SavedBlyg(origin: Fixtures.origin, manifest: try decode(Manifest.self, Fixtures.manifest),
                  addedAt: Date(timeIntervalSince1970: 0))
    }
}

/// A real store in a temporary folder that counts its saves, notes the thread they ran on, and can hold or fail chosen ones.
final class CountingStore: LibraryPersisting, @unchecked Sendable {
    let store = LibraryStore(directory: FileManager.default.temporaryDirectory.appending(path: "blyg tests \(UUID().uuidString)"))
    private let lock = NSLock()
    private var count = 0
    private var onMain = false
    private var holds: [Int: Hold] = [:]
    private var failures: Set<Int> = []

    var saves: Int { lock.withLock { count } }
    var savedOnMainThread: Bool { lock.withLock { onMain } }

    /// The next save blocks its thread until the returned hold is released.
    func holdNextSave() -> Hold { holdSave(1) }

    /// The `n`th save from now blocks its thread until the returned hold is released.
    func holdSave(_ n: Int) -> Hold {
        let hold = Hold()
        lock.withLock { holds[count + n] = hold }
        return hold
    }

    /// The next save writes nothing and throws, as a full disk would.
    func failNextSave() { failSave(1) }

    /// The `n`th save from now writes nothing and throws.
    func failSave(_ n: Int) { lock.withLock { _ = failures.insert(count + n) } }

    func load() -> (Library, LibraryStore.LoadOutcome) { store.load() }

    func save(_ library: Library) throws {
        let main = onMainThread()
        let (hold, fail) = lock.withLock { () -> (Hold?, Bool) in
            count += 1
            if main { onMain = true }
            return (holds[count], failures.contains(count))
        }
        hold?.wait()
        if fail { throw CocoaError(.fileWriteOutOfSpace) }
        try store.save(library)
    }

    func removeFiles() { try? FileManager.default.removeItem(at: store.directory) }
}

/// Builds the timeline as the app does, counting the builds, noting their thread and their times, and able to hold one.
final class TimelineCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var onMain = false
    private var hold: Hold?
    private var times: [(start: ContinuousClock.Instant, end: ContinuousClock.Instant)] = []

    var builds: Int { lock.withLock { count } }
    var builtOnMainThread: Bool { lock.withLock { onMain } }
    /// When each finished build started and ended, in order.
    var spans: [(start: ContinuousClock.Instant, end: ContinuousClock.Instant)] { lock.withLock { times } }

    /// Forgets the build the model does on the main actor as it opens, which is meant to be there.
    func reset() { lock.withLock { count = 0; onMain = false; times = [] } }

    /// The next build blocks its thread until the returned hold is released.
    func holdNextBuild() -> Hold {
        let hold = Hold()
        lock.withLock { self.hold = hold }
        return hold
    }

    func build(_ library: Library) -> [TimelineEntry] {
        let main = onMainThread()
        let start = ContinuousClock.now
        let hold = lock.withLock { () -> Hold? in
            count += 1
            if main { onMain = true }
            return self.hold
        }
        hold?.wait()
        let built = library.timeline(now: feedNow)
        lock.withLock { times.append((start, .now)) }
        return built
    }
}

/// A token store in memory that counts how often a token is asked for (in the app, each is a call to the Keychain).
final class CountingTokens: TokenStore, @unchecked Sendable {
    private let tokens = MemoryTokenStore()
    private let lock = NSLock()
    private var count = 0

    var reads: Int { lock.withLock { count } }

    func token(for origin: URL) -> String? {
        lock.withLock { count += 1 }
        return tokens.token(for: origin)
    }
    func save(_ token: String, for origin: URL, title: String, api: URL) throws { try tokens.save(token, for: origin, title: title, api: api) }
    func remove(for origin: URL) { tokens.remove(for: origin) }
    func connections() -> [Connection] { tokens.connections() }
}
