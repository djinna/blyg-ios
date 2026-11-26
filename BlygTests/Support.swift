import Foundation
import Testing
@testable import Blyg

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
        let (answer, hold) = lock.withLock { () -> (Answer?, Hold?) in
            requested.append(url.absoluteString)
            if main { onMain = true }
            return (answers[url.absoluteString], holds[url.absoluteString])
        }
        hold?.wait()
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

/// A real store in a temporary folder that counts its saves, notes the thread they ran on, and can hold one.
final class CountingStore: LibraryPersisting, @unchecked Sendable {
    let store = LibraryStore(directory: FileManager.default.temporaryDirectory.appending(path: "blyg tests \(UUID().uuidString)"))
    private let lock = NSLock()
    private var count = 0
    private var onMain = false
    private var hold: Hold?

    var saves: Int { lock.withLock { count } }
    var savedOnMainThread: Bool { lock.withLock { onMain } }

    /// The next save blocks its thread until the returned hold is released.
    func holdNextSave() -> Hold {
        let hold = Hold()
        lock.withLock { self.hold = hold }
        return hold
    }

    func load() -> (Library, LibraryStore.LoadOutcome) { store.load() }

    func save(_ library: Library) throws {
        let main = onMainThread()
        let hold = lock.withLock { () -> Hold? in
            count += 1
            if main { onMain = true }
            return self.hold
        }
        hold?.wait()
        try store.save(library)
    }

    func removeFiles() { try? FileManager.default.removeItem(at: store.directory) }
}

/// Builds the timeline as the app does, counting the builds, noting their thread, and able to hold one.
final class TimelineCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var onMain = false
    private var hold: Hold?

    var builds: Int { lock.withLock { count } }
    var builtOnMainThread: Bool { lock.withLock { onMain } }

    /// Forgets the build the model does on the main actor as it opens, which is meant to be there.
    func reset() { lock.withLock { count = 0; onMain = false } }

    /// The next build blocks its thread until the returned hold is released.
    func holdNextBuild() -> Hold {
        let hold = Hold()
        lock.withLock { self.hold = hold }
        return hold
    }

    func build(_ library: Library) -> [TimelineEntry] {
        let main = onMainThread()
        let hold = lock.withLock { () -> Hold? in
            count += 1
            if main { onMain = true }
            return self.hold
        }
        hold?.wait()
        return library.timeline()
    }
}
