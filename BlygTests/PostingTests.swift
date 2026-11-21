import Foundation
import Testing
@testable import Blyg

/// Answers Studio API requests from a table keyed by "METHOD URL", and records each request.
final class FakeTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [String: (Int, String)]
    private(set) var sent: [URLRequest] = []

    init(_ answers: [String: (Int, String)]) { self.answers = answers }

    var keys: [String] { lock.withLock { sent.map { "\($0.httpMethod ?? "") \($0.url!.absoluteString)" } } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let key = "\(request.httpMethod ?? "GET") \(request.url!.absoluteString)"
        let answer = lock.withLock { () -> (Int, String)? in
            sent.append(request)
            return answers[key]
        }
        let (status, body) = answer ?? (404, #"{"code":"not-found","message":"not found"}"#)
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

/// Real responses from the sandbox blyg (Studio 0.65.0, 2026-11-20), recorded with Studio's JS SDK.
enum SandboxResponses {
    static let api = URL(string: "https://blyg-sandbox.exe.xyz/api")!
    static let origin = URL(string: "https://blyg-sandbox.exe.xyz/")!
    static let id = "751gper24gax515bjszqjhjdd1"
    static let created = #"{"id":"751gper24gax515bjszqjhjdd1","revision":1,"kind":"fragment","status":"draft","created":"2026-11-20T21:37:10Z","updated":"2026-11-20T21:37:10Z","version":0,"contentMd":"Probe from the Blyg iOS build: [a link](https://example.org/)","dirty":true,"stubOf":null,"forkedFrom":null,"forkCite":null,"provenance":[],"responses":"default","highlight":"default"}"#
    static let media = #"{"id":"r1zx2ewh","url":"https://blyg-sandbox.exe.xyz/media/r1zx2ewh/c414cd0e204de974f73753c7e28d7638e7b3691bb8b1a2bab6b25bb7fed7ce77.png","mime":"image/png","revision":2}"#
    static let updated = created.replacingOccurrences(of: #""revision":1"#, with: #""revision":3"#)
    static let conflict = #"{"code":"revision-conflict","message":"item revision conflict; reload and try again","details":{"itemId":"751gper24gax515bjszqjhjdd1","expectedRevision":1}}"#
    static let published = #"{"ok":true,"version":1,"revision":4}"#
    static let capabilities = #"{"contractVersion":"5.14.0","endpoints":{"publicBase":"https://blyg-sandbox.exe.xyz","studio":"https://blyg-sandbox.exe.xyz/studio","api":"https://blyg-sandbox.exe.xyz/api","media":"https://blyg-sandbox.exe.xyz/media"},"operations":["createItem"]}"#

    static func happyPath() -> FakeTransport {
        FakeTransport([
            "POST https://blyg-sandbox.exe.xyz/api/items": (201, created),
            "POST https://blyg-sandbox.exe.xyz/api/media": (201, media),
            "PATCH https://blyg-sandbox.exe.xyz/api/items/\(id)": (200, updated),
            "POST https://blyg-sandbox.exe.xyz/api/items/\(id)/publish": (200, published),
            "GET https://blyg-sandbox.exe.xyz/api/capabilities": (200, capabilities),
        ])
    }
}

private func body(_ request: URLRequest) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
}

@Suite("Studio API requests")
struct StudioRequestTests {
    let api = SandboxResponses.api

    @Test func apiLivesUnderTheMount() {
        #expect(StudioClient.apiBase(forOrigin: URL(string: "https://example.com/blyg/")!).absoluteString == "https://example.com/blyg/api")
        #expect(StudioClient.apiBase(forOrigin: SandboxResponses.origin) == api)
    }

    @Test func createItemSendsABlankFragmentWithBearerAuth() {
        let req = Requests.createItem(api: api, token: "t0k", contentMd: "Hi", kind: "fragment")
        #expect(req.httpMethod == "POST")
        #expect(req.url?.absoluteString == "https://blyg-sandbox.exe.xyz/api/items")
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer t0k")
        #expect(req.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let json = body(req)
        #expect(json["mode"] as? String == "blank")
        #expect(json["kind"] as? String == "fragment")
        #expect(json["contentMd"] as? String == "Hi")
    }

    @Test func updateAndPublishCarryTheExpectedRevision() {
        let update = Requests.updateItem(api: api, token: "t", id: "abc", contentMd: "x", expectedRevision: 4)
        #expect(update.httpMethod == "PATCH")
        #expect(update.url?.path() == "/api/items/abc")
        #expect(body(update)["expectedRevision"] as? Int == 4)
        let publish = Requests.publishItem(api: api, token: "t", id: "abc", expectedRevision: 5, note: nil)
        #expect(publish.url?.path() == "/api/items/abc/publish")
        #expect(body(publish)["expectedRevision"] as? Int == 5)
        #expect(body(publish)["note"] == nil)
    }

    @Test func mediaUploadIsMultipartWithTheItemAndRevision() throws {
        let upload = MediaUpload(data: Data([0xFF, 0xD8, 0xFF]), filename: "photo.jpg", mimeType: "image/jpeg", alt: "a dot")
        let req = Requests.uploadMedia(api: api, token: "t", upload: upload, itemId: "abc", expectedRevision: 2, boundary: "B")
        #expect(req.value(forHTTPHeaderField: "Content-Type") == "multipart/form-data; boundary=B")
        let text = String(decoding: try #require(req.httpBody), as: UTF8.self)
        #expect(text.contains("name=\"itemId\"\r\n\r\nabc\r\n"))
        #expect(text.contains("name=\"expectedRevision\"\r\n\r\n2\r\n"))
        #expect(text.contains("name=\"alt\"\r\n\r\na dot\r\n"))
        #expect(text.contains("name=\"inline\"\r\n\r\ntrue\r\n"))
        #expect(text.contains("name=\"file\"; filename=\"photo.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n"))
        #expect(text.hasSuffix("\r\n--B--\r\n"))
    }

    @Test func responsesFromTheSandboxDecode() throws {
        let item = try decode(StudioItem.self, SandboxResponses.created)
        #expect(item.id == SandboxResponses.id && item.revision == 1 && item.status == "draft")
        let media = try decode(StudioMedia.self, SandboxResponses.media)
        #expect(media.revision == 2)
        let published = try decode(StudioPublishResult.self, SandboxResponses.published)
        #expect(published.ok && published.version == 1)
        let caps = try decode(StudioCapabilities.self, SandboxResponses.capabilities)
        #expect(caps.endpoints.api == "https://blyg-sandbox.exe.xyz/api")
    }

    @Test func aStaleRevisionIsAConflict() {
        let error = StudioClient.error(status: 409, data: Data(SandboxResponses.conflict.utf8))
        #expect(error.isRevisionConflict)
        #expect(error.status == 409)
        let unknown = StudioClient.error(status: 502, data: Data("<html>".utf8))
        #expect(unknown.code == "http-502")
    }
}

@Suite("Composing and posting")
struct PosterTests {
    let poster = { (transport: FakeTransport) in
        Poster(client: StudioClient(api: SandboxResponses.api, token: "t", transport: transport), origin: SandboxResponses.origin)
    }

    @Test func markdownPutsTheLinkOnItsOwnParagraph() {
        let link = URL(string: "https://example.org/a?b=1")!
        #expect(PostMarkdown.compose(PostDraft(text: "  Note  ", link: link, linkTitle: "A [title]")) == "Note\n\n[A \\[title\\]](https://example.org/a?b=1)")
        #expect(PostMarkdown.compose(PostDraft(text: "", link: link)) == "<https://example.org/a?b=1>")
        #expect(PostMarkdown.compose(PostDraft(text: "Just text")) == "Just text")
        #expect(!PostMarkdown.compose(PostDraft(text: "x", link: link)).contains("]()"))
    }

    @Test func imagesUnderTheBlygAreOriginRelative() {
        #expect(PostMarkdown.image(alt: "a dot", mediaURL: "https://blyg-sandbox.exe.xyz/media/r1/abc.png", origin: SandboxResponses.origin)
                == "![a dot](media/r1/abc.png)")
        #expect(PostMarkdown.image(alt: "", mediaURL: "https://cdn.example/x.png", origin: SandboxResponses.origin)
                == "![](https://cdn.example/x.png)")
    }

    @Test func aTextPostIsCreatedThenPublished() async throws {
        let transport = SandboxResponses.happyPath()
        let result = try await poster(transport).post(PostDraft(text: "Hello"))
        #expect(result == .init(id: SandboxResponses.id, version: 1))
        #expect(transport.keys == [
            "POST https://blyg-sandbox.exe.xyz/api/items",
            "POST https://blyg-sandbox.exe.xyz/api/items/\(SandboxResponses.id)/publish",
        ])
        #expect(body(transport.sent[1])["expectedRevision"] as? Int == 1)
    }

    @Test func aPhotoIsUploadedAddedToTheTextThenPublished() async throws {
        let transport = SandboxResponses.happyPath()
        let photo = MediaUpload(data: Data([1, 2, 3]), filename: "photo.jpg", mimeType: "image/jpeg", alt: "a dot")
        _ = try await poster(transport).post(PostDraft(text: "Hello", photo: photo))
        #expect(transport.keys.map { $0.split(separator: " ")[0] } == ["POST", "POST", "PATCH", "POST"])
        let patch = body(transport.sent[2])
        #expect(patch["expectedRevision"] as? Int == 2) // from the upload's response
        #expect((patch["contentMd"] as? String)?.hasSuffix("\n\n![a dot](media/r1zx2ewh/c414cd0e204de974f73753c7e28d7638e7b3691bb8b1a2bab6b25bb7fed7ce77.png)") == true)
        #expect(body(transport.sent[3])["expectedRevision"] as? Int == 3) // from the update's response
    }

    @Test func aFailureAfterCreatingLeavesADraft() async {
        let conflict = FakeTransport([
            "POST https://blyg-sandbox.exe.xyz/api/items": (201, SandboxResponses.created),
            "POST https://blyg-sandbox.exe.xyz/api/items/\(SandboxResponses.id)/publish": (409, SandboxResponses.conflict),
        ])
        await #expect(throws: PostFailure.draftSaved(id: SandboxResponses.id, StudioError(status: 409, code: "revision-conflict", message: "item revision conflict; reload and try again"))) {
            _ = try await poster(conflict).post(PostDraft(text: "Hello"))
        }
    }

    @Test func anExpiredTokenPostsNothingAndSaysWhy() async throws {
        let expired = FakeTransport(["POST https://blyg-sandbox.exe.xyz/api/items": (401, #"{"code":"unauthorized","message":"unauthorized"}"#)])
        do {
            _ = try await poster(expired).post(PostDraft(text: "Hello"))
            Issue.record("expected a failure")
        } catch {
            guard case .notPosted(let studio) = error else { Issue.record("wrong failure \(error)"); return }
            #expect(studio.status == 401)
            #expect(Poster.describe(error, blygTitle: "Sandbox").contains("30 days"))
        }
    }
}

@Suite("Connecting a blyg")
@MainActor
struct ConnectTests {
    func model(_ transport: FakeTransport, tokens: MemoryTokenStore = MemoryTokenStore()) async throws -> LibraryModel {
        let model = LibraryModel(store: nil, fetcher: FakeFetcher.sample(), tokens: tokens, transport: transport)
        try await model.add("sample.example")
        return model
    }

    @Test func aGoodTokenIsSavedAndTheBlygCanPost() async throws {
        let tokens = MemoryTokenStore()
        let transport = FakeTransport(["GET https://sample.example/api/capabilities": (200, SandboxResponses.capabilities.replacingOccurrences(of: "blyg-sandbox.exe.xyz", with: "sample.example"))])
        let model = try await model(transport, tokens: tokens)
        #expect(model.postingBlygs.isEmpty)
        try await model.connect(Fixtures.origin, token: "  secret \n")
        #expect(tokens.token(for: Fixtures.origin) == "secret")
        #expect(model.isConnected(Fixtures.origin))
        #expect(model.blyg(Fixtures.origin)?.postingAPI?.absoluteString == "https://sample.example/api")
        #expect(transport.sent.first?.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        #expect(model.poster(for: Fixtures.origin) != nil)
        #expect(tokens.connections() == [Connection(origin: Fixtures.origin, title: "Sample Notes", api: URL(string: "https://sample.example/api")!)])

        model.disconnect(Fixtures.origin)
        #expect(tokens.token(for: Fixtures.origin) == nil)
        #expect(!model.isConnected(Fixtures.origin))
    }

    @Test func aRejectedTokenIsNotSaved() async throws {
        let tokens = MemoryTokenStore()
        let transport = FakeTransport(["GET https://sample.example/api/capabilities": (401, #"{"code":"unauthorized","message":"no"}"#)])
        let model = try await model(transport, tokens: tokens)
        await #expect(throws: LibraryModel.ConnectFailure.rejected) { try await model.connect(Fixtures.origin, token: "bad") }
        #expect(tokens.token(for: Fixtures.origin) == nil)
    }

    @Test func aBlygWithoutStudioSaysSo() async throws {
        let model = try await model(FakeTransport([:]))
        await #expect(throws: LibraryModel.ConnectFailure.noOwnerAPI(URL(string: "https://sample.example/api")!)) {
            try await model.connect(Fixtures.origin, token: "x")
        }
    }

    @Test func unfollowingForgetsTheToken() async throws {
        let tokens = MemoryTokenStore()
        let transport = FakeTransport(["GET https://sample.example/api/capabilities": (200, SandboxResponses.capabilities)])
        let model = try await model(transport, tokens: tokens)
        try await model.connect(Fixtures.origin, token: "secret")
        model.remove(Fixtures.origin)
        #expect(tokens.token(for: Fixtures.origin) == nil)
    }
}

@Suite("Keychain")
struct KeychainTests {
    /// Uses the real Keychain with the shared access group, so it fails if the entitlement is missing.
    @Test func savesReadsReplacesAndRemovesATokenPerOrigin() throws {
        let store = KeychainTokenStore()
        let origin = URL(string: "https://keychain-test-\(UUID().uuidString.lowercased()).example/")!
        defer { store.remove(for: origin) }
        #expect(store.token(for: origin) == nil)
        try store.save("first", for: origin)
        #expect(store.token(for: origin) == "first")
        // Saved in the group the Share extension shares, whatever team built the app.
        #expect(store.accessGroup(for: origin)?.hasSuffix(".net.jdbb.blyg.shared") == true)
        try store.save("second", for: origin)
        #expect(store.token(for: origin) == "second")
        #expect(store.token(for: URL(string: "https://other.example/")!) == nil)
        try store.save("third", for: origin, title: "My blyg", api: URL(string: "https://x.example/api")!)
        let mine = store.connections().first { $0.origin == origin }
        #expect(mine == Connection(origin: origin, title: "My blyg", api: URL(string: "https://x.example/api")!))
        store.remove(for: origin)
        #expect(store.token(for: origin) == nil)
        #expect(!store.connections().contains { $0.origin == origin })
    }
}

@Suite("Link check")
struct LinkCheckTests {
    @Test(arguments: [
        ("https://chat.example/c/abc#RNf2yaQlLxzi73nSn4FeMsvIpj7nFXoHnRdDgMWzkSE", true),
        ("https://draw.example/#json=5550923,Xq3YbN7wPz0LmA4kRt9sVc", true),
        ("https://example.org/guide#section-2", false),
        ("https://example.org/docs#configuring-the-reader-on-ios", false),
        ("https://example.org/page", false),
        ("https://example.org/#top", false),
    ])
    func flagsKeysButNotAnchors(link: String, expected: Bool) {
        #expect(LinkCheck.fragmentLooksSecret(URL(string: link)) == expected)
    }
}
