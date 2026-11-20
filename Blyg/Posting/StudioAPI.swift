import Foundation

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

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.httpShouldSetCookies = false
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(LaunchFlags.useFixtures) {
            config.protocolClasses = [FixtureURLProtocol.self]
        }
        #endif
        session = URLSession(configuration: config)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FetchError.notHTTP }
        return (data, http)
    }
}

nonisolated struct StudioClient: Sendable {
    /// The REST API base, `{mount}/api` (Studio docs, docs/client-access.md).
    let api: URL
    let token: String
    let transport: any HTTPTransport

    /// Where a blyg's owner API lives: `{origin}api`, the origin being the blyg's mount.
    static func apiBase(forOrigin origin: URL) -> URL { origin.appending(path: "api") }

    func getCapabilities() async throws -> StudioCapabilities {
        try await send(Requests.getCapabilities(api: api, token: token))
    }

    func createItem(contentMd: String, kind: String = "fragment") async throws -> StudioItem {
        try await send(Requests.createItem(api: api, token: token, contentMd: contentMd, kind: kind))
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

    static func createItem(api: URL, token: String, contentMd: String, kind: String) -> URLRequest {
        json("POST", api.appending(path: "items"), token: token,
             ["mode": "blank", "kind": kind, "contentMd": contentMd])
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
