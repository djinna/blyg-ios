import Foundation
import os

// A small hand-written client for the Blygger Studio owner API: only the calls this app makes.
// Names follow Studio's OpenAPI operationIds (contract 5.14.0, Studio 0.65.0). Checked against the
// sandbox with Studio's own JS SDK before being written here.

nonisolated struct StudioCapabilities: Decodable, Sendable, Equatable {
    var contractVersion: String
    var endpoints: Endpoints

    nonisolated struct Endpoints: Decodable, Sendable, Equatable {
        var api: String
        var publicBase: String?
    }
}

/// The parts of a Studio item (`createItem`, `updateItem`) this app reads.
nonisolated struct StudioItem: Decodable, Sendable, Equatable {
    var id: String
    var revision: Int
    var kind: String
    var status: String
    var version: Double
    var contentMd: String
}

nonisolated struct StudioMedia: Decodable, Sendable, Equatable {
    var id: String
    var url: String
    var mime: String
    /// The item's new revision when the upload was attached to an item.
    var revision: Int?
}

/// One of a Studio's subscriptions (`listSubscriptions`). Only blyg subscriptions are followed in the app.
nonisolated struct StudioSubscription: Decodable, Sendable, Equatable {
    var kind: String
    var origin: String?
    var title: String?
}

nonisolated struct StudioSubscriptionPage: Decodable, Sendable, Equatable {
    var items: [StudioSubscription]
    var page: Page
    nonisolated struct Page: Decodable, Sendable, Equatable { var nextCursor: String? }
}

/// The post a reply answers, as the composer needs it. Sent as `stubOf` (spec §10.6); replies are threads,
/// because Studio refuses a fragment with `stubOf` ("only threads can be stubs").
nonisolated struct ReplyTarget: Sendable, Equatable, Hashable {
    var origin: URL
    var id: String
    var version: Int
    var blygTitle: String
    var excerpt: String
    var page: URL?

    /// `{origin, id, version, cited}`. The citation is the label as seen now, frozen (§5.9); Studio may refine it.
    func stubOf(retrieved: Date = .now) -> [String: Any] {
        var cited: [String: Any] = ["source": blygTitle, "retrieved": retrieved.formatted(.iso8601)]
        let excerpt = excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !excerpt.isEmpty { cited["excerpt"] = excerpt.count > 200 ? String(excerpt.prefix(199)) + "…" : excerpt }
        if let page { cited["url"] = page.absoluteString }
        return ["origin": origin.absoluteString, "id": id, "version": version, "cited": cited]
    }
}

nonisolated struct StudioPublishResult: Decodable, Sendable, Equatable {
    var ok: Bool
    var version: Double
    var revision: Int
    var warning: String?
}

/// Studio's error body: `{ code, message, details }`.
nonisolated struct StudioError: Error, Decodable, Sendable, Equatable {
    var status: Int = 0
    var code: String
    var message: String

    enum CodingKeys: String, CodingKey { case code, message }

    init(status: Int, code: String, message: String) {
        self.status = status; self.code = code; self.message = message
    }

    var isRevisionConflict: Bool { code == "revision-conflict" }
}

nonisolated protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

nonisolated struct URLSessionTransport: HTTPTransport {
    let session: URLSession

    /// Shared by the app and the Share extension; the app passes a configuration that can serve DEBUG fixtures.
    init(configuration: URLSessionConfiguration = Self.defaultConfiguration()) {
        session = URLSession(configuration: configuration)
    }

    static func defaultConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.httpShouldSetCookies = false
        return config
    }

    struct NotHTTP: Error {}

    /// URLSession follows redirects by itself, after `StudioClient.send` has checked the first URL, so each
    /// request gets a `RedirectGuard`. A refused redirect is an error, whatever the redirecting answer held.
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let redirects = RedirectGuard()
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: redirects)
        } catch {
            throw redirects.refused ? StudioClient.redirectRefused : error
        }
        guard !redirects.refused else { throw StudioClient.redirectRefused }
        guard let http = response as? HTTPURLResponse else { throw NotHTTP() }
        return (data, http)
    }
}

/// Lets one request follow a redirect only while it stays on the server it was first sent to: https, the same
/// host and the same port (`StudioClient.sameHTTPSServer`). Anything else is refused before the next request
/// is made, so neither the token nor the post leaves the blyg's own server.
nonisolated final class RedirectGuard: NSObject, URLSessionTaskDelegate {
    private let state = OSAllocatedUnfairLock(initialState: false)

    /// True once a redirect has been refused.
    var refused: Bool { state.withLock { $0 } }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        // Each hop is held to the first URL, not the one before it, so a chain can't walk away a step at a time.
        if let first = task.originalRequest?.url, let next = request.url, StudioClient.sameHTTPSServer(next, first) {
            completionHandler(request)
        } else {
            state.withLock { $0 = true }
            completionHandler(nil)
        }
    }
}

nonisolated struct StudioClient: Sendable {
    /// The REST API base, `{mount}/api` (Studio docs, docs/client-access.md).
    let api: URL
    let token: String
    let transport: any HTTPTransport

    /// Where a blyg's owner API lives: `{origin}api`, the origin being the blyg's mount.
    static func apiBase(forOrigin origin: URL) -> URL { origin.appending(path: "api") }

    /// A token only ever travels over https, so it's never sent in the clear.
    static func isHTTPS(_ url: URL) -> Bool { url.scheme?.lowercased() == "https" }

    static let needsHTTPS = StudioError(status: 0, code: "needs-https",
                                        message: "Posting needs an https blyg, so the token is never sent in the clear.")

    /// The API a blyg's token may be sent to, or nil when the blyg isn't https: then nothing may carry its token.
    /// What a Studio advertises (or a copy of that saved earlier) is used only when it's https on the blyg's own
    /// host and port (no port means 443); anything else gets `{origin}api`, where the token was checked.
    static func trustedAPI(_ advertised: URL?, forOrigin origin: URL) -> URL? {
        guard isHTTPS(origin) else { return nil }
        guard let advertised, sameHTTPSServer(advertised, origin) else { return apiBase(forOrigin: origin) }
        return advertised
    }

    /// True when both URLs are https on the same host and port (no port means 443): the one server a token,
    /// or a redirect of a request carrying it, may go to.
    static func sameHTTPSServer(_ a: URL, _ b: URL) -> Bool {
        guard isHTTPS(a), isHTTPS(b),
              let host = a.host()?.lowercased(), !host.isEmpty, host == b.host()?.lowercased()
        else { return false }
        return (a.port ?? 443) == (b.port ?? 443)
    }

    static let redirectRefused = StudioError(status: 0, code: "redirect-refused",
                                             message: "The blyg redirected this request to another address, and the app didn't follow: the token only goes to the blyg's own https address.")

    func getCapabilities() async throws -> StudioCapabilities {
        try await send(Requests.getCapabilities(api: api, token: token))
    }

    func createItem(contentMd: String, kind: String = "fragment", replyTo: ReplyTarget? = nil) async throws -> StudioItem {
        try await send(Requests.createItem(api: api, token: token, contentMd: contentMd, kind: kind, stubOf: replyTo?.stubOf()))
    }

    /// Every blyg subscription, following the cursor through each page.
    func listSubscriptions() async throws -> [StudioSubscription] {
        var all: [StudioSubscription] = []
        var cursor: String?
        repeat {
            let page: StudioSubscriptionPage = try await send(Requests.listSubscriptions(api: api, token: token, cursor: cursor))
            all += page.items
            cursor = page.page.nextCursor
        } while cursor != nil && all.count < 2000
        return all
    }

    func updateItem(id: String, contentMd: String, expectedRevision: Int) async throws -> StudioItem {
        try await send(Requests.updateItem(api: api, token: token, id: id, contentMd: contentMd, expectedRevision: expectedRevision))
    }

    func uploadMedia(_ upload: MediaUpload, itemId: String, expectedRevision: Int) async throws -> StudioMedia {
        try await send(Requests.uploadMedia(api: api, token: token, upload: upload, itemId: itemId,
                                            expectedRevision: expectedRevision, boundary: "blyg-\(UUID().uuidString)"))
    }

    func publishItem(id: String, expectedRevision: Int, note: String? = nil) async throws -> StudioPublishResult {
        try await send(Requests.publishItem(api: api, token: token, id: id, expectedRevision: expectedRevision, note: note))
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        // Every request made here carries the token, so none leaves over anything but https.
        guard let url = request.url, Self.isHTTPS(url) else { throw Self.needsHTTPS }
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw Self.error(status: response.statusCode, data: data)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func error(status: Int, data: Data) -> StudioError {
        if var error = try? JSONDecoder().decode(StudioError.self, from: data) {
            error.status = status
            return error
        }
        return StudioError(status: status, code: "http-\(status)", message: HTTPURLResponse.localizedString(forStatusCode: status))
    }
}

nonisolated struct MediaUpload: Sendable, Equatable {
    var data: Data
    var filename: String
    var mimeType: String
    var alt: String
}

/// Request builders, kept pure so tests can check exactly what goes on the wire.
nonisolated enum Requests {
    static func getCapabilities(api: URL, token: String) -> URLRequest {
        request("GET", api.appending(path: "capabilities"), token: token)
    }

    static func createItem(api: URL, token: String, contentMd: String, kind: String, stubOf: [String: Any]? = nil) -> URLRequest {
        var body: [String: Any] = ["mode": "blank", "kind": kind, "contentMd": contentMd]
        if let stubOf { body["stubOf"] = stubOf }
        return json("POST", api.appending(path: "items"), token: token, body)
    }

    static func listSubscriptions(api: URL, token: String, cursor: String?) -> URLRequest {
        var url = api.appending(path: "subscriptions")
        if let cursor { url.append(queryItems: [URLQueryItem(name: "cursor", value: cursor)]) }
        return request("GET", url, token: token)
    }

    static func updateItem(api: URL, token: String, id: String, contentMd: String, expectedRevision: Int) -> URLRequest {
        json("PATCH", api.appending(path: "items").appending(path: id), token: token,
             ["contentMd": contentMd, "expectedRevision": expectedRevision])
    }

    static func publishItem(api: URL, token: String, id: String, expectedRevision: Int, note: String?) -> URLRequest {
        var body: [String: Any] = ["expectedRevision": expectedRevision]
        if let note, !note.isEmpty { body["note"] = note }
        return json("POST", api.appending(path: "items").appending(path: id).appending(path: "publish"), token: token, body)
    }

    static func uploadMedia(api: URL, token: String, upload: MediaUpload, itemId: String, expectedRevision: Int, boundary: String) -> URLRequest {
        var req = request("POST", api.appending(path: "media"), token: token)
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        field("itemId", itemId)
        field("expectedRevision", String(expectedRevision))
        if !upload.alt.isEmpty { field("alt", upload.alt) }
        field("inline", "true")
        let filename = upload.filename.replacingOccurrences(of: "\"", with: "")
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\nContent-Type: \(upload.mimeType)\r\n\r\n")
        body.append(upload.data)
        body.append("\r\n--\(boundary)--\r\n")
        req.httpBody = body
        return req
    }

    private static func request(_ method: String, _ url: URL, token: String) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }

    private static func json(_ method: String, _ url: URL, token: String, _ body: [String: Any]) -> URLRequest {
        var req = request(method, url, token: token)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return req
    }
}

private extension Data {
    nonisolated mutating func append(_ string: String) { append(Data(string.utf8)) }
}
