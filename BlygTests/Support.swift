import Foundation
@testable import Blyg

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

    init(_ answers: [String: Answer] = [:]) { self.answers = answers }

    /// The fictional blyg from the app's DEBUG fixtures.
    static func sample() -> FakeFetcher {
        FakeFetcher(Fixtures.responses.mapValues { Answer(status: $0.status, body: $0.body) })
    }

    func set(_ url: String, _ answer: Answer?) {
        lock.withLock { answers[url] = answer }
    }

    var requestCount: Int { lock.withLock { requested.count } }

    func get(_ url: URL) async throws -> FetchResult {
        let answer = lock.withLock { () -> Answer? in
            requested.append(url.absoluteString)
            return answers[url.absoluteString]
        }
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
