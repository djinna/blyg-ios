import Foundation
import os

nonisolated struct FetchResult: Sendable {
    var data: Data
    /// The URL after redirects: what subscription identity is built from (§12.2).
    var finalURL: URL
    var status: Int
    var contentType: String?

    var isOK: Bool { (200..<300).contains(status) }
}

nonisolated protocol Fetching: Sendable {
    func get(_ url: URL) async throws -> FetchResult
}

nonisolated enum FetchError: Error, Equatable {
    case tooLarge
    case notHTTP
}

/// Plain GETs of public blyg files. No cookies, no credentials: reading needs none.
nonisolated struct URLSessionFetcher: Fetching {
    static let maxBytes = 8 * 1024 * 1024
    let session: URLSession

    init(configuration: URLSessionConfiguration = Self.defaultConfiguration()) {
        session = URLSession(configuration: configuration)
    }

    static func defaultConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        config.httpShouldSetCookies = false
        config.httpAdditionalHeaders = ["Accept": "application/json, application/rss+xml, text/xml, text/html;q=0.8, */*;q=0.5"]
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(LaunchFlags.useFixtures) {
            config.protocolClasses = [FixtureURLProtocol.self]
        }
        #endif
        return config
    }

    func get(_ url: URL) async throws -> FetchResult {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw FetchError.notHTTP }
        guard data.count <= Self.maxBytes else { throw FetchError.tooLarge }
        return FetchResult(data: data, finalURL: http.url ?? url, status: http.statusCode,
                           contentType: http.value(forHTTPHeaderField: "Content-Type"))
    }
}

nonisolated enum Log {
    static let network = Logger(subsystem: "net.jdbb.blyg", category: "network")
    static let store = Logger(subsystem: "net.jdbb.blyg", category: "store")
}
