import Foundation
import Testing
@testable import Blyg

/// Answers Studio API requests from a table keyed by "METHOD URL", and records each request.
final class FakeTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [String: (Int, String)]
    private(set) var sent: [URLRequest] = []
    private var onMain: [String] = []
    private var gates: [String: Gate] = [:]

    /// Requests for `key` ("METHOD URL") wait, without blocking a thread, until the returned gate is released.
    func delay(_ key: String) -> Gate {
        let gate = Gate()
        lock.withLock { gates[key] = gate }
        return gate
    }

    init(_ answers: [String: (Int, String)]) { self.answers = answers }

    /// The requests sent on the main thread: their caller, and its decoding of the answer, were on the main actor.
    var keysSentOnMainThread: [String] { lock.withLock { onMain } }

    func set(_ key: String, _ answer: (Int, String)) { lock.withLock { answers[key] = answer } }

    var keys: [String] { lock.withLock { sent.map { "\($0.httpMethod ?? "") \($0.url!.absoluteString)" } } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let key = "\(request.httpMethod ?? "GET") \(request.url!.absoluteString)"
        let main = onMainThread()
        let gate = lock.withLock { () -> Gate? in
            sent.append(request)
            if main { onMain.append(key) }
            return gates[key]
        }
        await gate?.wait()
        let answer = lock.withLock { answers[key] } // as it is once the wait is over
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

    @Test func theTokenOnlyGoesToTheBlygsOwnHostOverHTTPS() {
        let origin = URL(string: "https://example.com/blyg/")!
        let fallback = URL(string: "https://example.com/blyg/api")!
        func trusted(_ advertised: String) -> URL? { StudioClient.trustedAPI(URL(string: advertised), forOrigin: origin) }
        #expect(trusted("https://example.com/studio/api")?.absoluteString == "https://example.com/studio/api")
        #expect(trusted("https://EXAMPLE.com/studio/api")?.absoluteString == "https://EXAMPLE.com/studio/api")
        #expect(trusted("https://elsewhere.example/api") == fallback)
        #expect(trusted("http://example.com/studio/api") == fallback)
        #expect(trusted("https://example.com.elsewhere.example/api") == fallback)
        #expect(trusted("https://example.com@elsewhere.example/api") == fallback)
        #expect(trusted("/studio/api") == fallback)
        #expect(StudioClient.trustedAPI(nil, forOrigin: origin) == fallback)
    }

    @Test func theAPIMustBeOnTheBlygsOwnPort() {
        func trusted(_ advertised: String, origin: String) -> String? {
            StudioClient.trustedAPI(URL(string: advertised), forOrigin: URL(string: origin)!)?.absoluteString
        }
        // No port on https means 443, on either side.
        #expect(trusted("https://example.com:443/studio/api", origin: "https://example.com/") == "https://example.com:443/studio/api")
        #expect(trusted("https://example.com/studio/api", origin: "https://example.com:443/") == "https://example.com/studio/api")
        #expect(trusted("https://example.com:8443/studio/api", origin: "https://example.com:8443/") == "https://example.com:8443/studio/api")
        // Another port is another server: fall back to the blyg's own.
        #expect(trusted("https://example.com:8443/studio/api", origin: "https://example.com/") == "https://example.com/api")
        #expect(trusted("https://example.com/studio/api", origin: "https://example.com:8443/") == "https://example.com:8443/api")
    }

    @Test func aBlygThatIsntHTTPSHasNoAPIForItsToken() {
        let origin = URL(string: "http://example.com/")!
        #expect(StudioClient.trustedAPI(URL(string: "https://example.com/api"), forOrigin: origin) == nil)
        #expect(StudioClient.trustedAPI(URL(string: "http://example.com/api"), forOrigin: origin) == nil)
        #expect(StudioClient.trustedAPI(nil, forOrigin: origin) == nil)
    }

    @Test func theClientSendsNothingToAnAPIThatIsntHTTPS() async {
        let transport = FakeTransport(["GET http://example.com/api/capabilities": (200, SandboxResponses.capabilities)])
        let client = StudioClient(api: URL(string: "http://example.com/api")!, token: "t", transport: transport)
        await #expect(throws: StudioClient.needsHTTPS) { _ = try await client.getCapabilities() }
        await #expect(throws: StudioClient.needsHTTPS) { _ = try await client.createItem(contentMd: "Hello") }
        await #expect(throws: StudioClient.needsHTTPS) { _ = try await client.listSubscriptions() }
        #expect(transport.sent.isEmpty)
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

    /// Each case was rendered with Studio 0.65's own `renderMarkdown` on the sandbox (2026-11-22): changed cases gain a
    /// `<br>`, and no case shows a literal backslash.
    @Test(arguments: [
        ("Roses are red\nviolets are blue", "Roses are red\\\nviolets are blue"),
        ("One\ntwo\n\nNew para", "One\\\ntwo\n\nNew para"),
        ("- a\n- b\n  continued", "- a\n- b\\\n  continued"),
        ("# Heading\nbody", "# Heading\nbody"),
        ("Title\n===\nafter", "Title\n===\nafter"),
        ("> quoted\n> lines", "> quoted\\\n> lines"),
        ("plain\n> quote", "plain\n> quote"),
        ("```\ncode\nmore\n```\nafter\nend", "```\ncode\nmore\n```\nafter\\\nend"),
        ("$$\na=b\nc=d\n$$", "$$\na=b\nc=d\n$$"),
        ("a | b\n--- | ---\nc | d", "a | b\n--- | ---\nc | d"),
        ("already\\\nbroken", "already\\\nbroken"),
        ("trailing   \nspaces", "trailing   \nspaces"),
        ("    code\n    more", "    code\n    more"),
        ("* * *\nnext", "* * *\nnext"),
        // Transclusion directives and the quote attached to one (§10.1) are never touched (Studio's DIRECTIVE_LINE: ^\s*![[).
        ("Look:\n![[abc]]\nmore", "Look:\n![[abc]]\nmore"),
        ("Look:\n\t![[abc]]", "Look:\n\t![[abc]]"),
        ("![[abc]]\n> their words\n> exactly\n\nmine\nhere", "![[abc]]\n> their words\n> exactly\n\nmine\\\nhere"),
    ])
    func singleLineBreaksAreKept(typed: String, posted: String) {
        #expect(LineBreaks.keep(typed) == posted)
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

    /// Connects to sample.example with a Studio that advertises `advertised` as its API, then makes one more
    /// call with the token. Returns the model, the token store and every request sent.
    func connected(advertising advertised: String) async throws -> (LibraryModel, MemoryTokenStore, FakeTransport) {
        let tokens = MemoryTokenStore()
        let capabilities = SandboxResponses.capabilities.replacingOccurrences(of: "https://blyg-sandbox.exe.xyz/api", with: advertised)
        let transport = FakeTransport(["GET https://sample.example/api/capabilities": (200, capabilities)])
        let model = try await model(transport, tokens: tokens)
        try await model.connect(Fixtures.origin, token: "secret")
        _ = try? await model.importSubscriptions(from: Fixtures.origin)
        return (model, tokens, transport)
    }

    @Test func anAdvertisedAPIOnTheSameHostIsUsed() async throws {
        let (model, tokens, transport) = try await connected(advertising: "https://sample.example/studio/api")
        #expect(model.blyg(Fixtures.origin)?.postingAPI?.absoluteString == "https://sample.example/studio/api")
        #expect(tokens.connections().first?.api.absoluteString == "https://sample.example/studio/api")
        #expect(transport.keys.last == "GET https://sample.example/studio/api/subscriptions")
    }

    @Test(arguments: ["https://elsewhere.example/api", "http://sample.example/studio/api"])
    func anAdvertisedAPIOnAnotherHostOrOverHTTPIsIgnored(_ advertised: String) async throws {
        let (model, tokens, transport) = try await connected(advertising: advertised)
        #expect(model.blyg(Fixtures.origin)?.postingAPI?.absoluteString == "https://sample.example/api")
        #expect(tokens.connections().first?.api.absoluteString == "https://sample.example/api")
        // The token went nowhere but the blyg itself.
        #expect(transport.keys == ["GET https://sample.example/api/capabilities", "GET https://sample.example/api/subscriptions"])
        #expect(transport.sent.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer secret" })
    }

    @Test func aSavedAPIOnAnotherHostIsNotUsed() throws {
        let store = LibraryStore(directory: FileManager.default.temporaryDirectory.appending(path: "blyg tests \(UUID().uuidString)"))
        defer { try? FileManager.default.removeItem(at: store.directory) }
        var blyg = try SavedBlyg.sample()
        blyg.postingAPI = URL(string: "https://elsewhere.example/api")
        try store.save(Library(blygs: [blyg]))
        let model = LibraryModel(store: store, fetcher: FakeFetcher.sample(), tokens: MemoryTokenStore(), transport: FakeTransport([:]))
        #expect(model.blyg(Fixtures.origin)?.postingAPI?.absoluteString == "https://sample.example/api")
    }

    /// The fixture blyg served over http: every fixture URL with its scheme changed.
    static let httpOrigin = URL(string: "http://sample.example/")!
    static func httpFetcher() -> FakeFetcher {
        FakeFetcher(Dictionary(uniqueKeysWithValues: Fixtures.responses.map { url, response in
            (url.replacingOccurrences(of: "https://", with: "http://"), FakeFetcher.Answer(status: response.status, body: response.body))
        }))
    }

    @Test func anHTTPBlygCanBeFollowedAndReadButNeverGetsTheToken() async throws {
        let tokens = MemoryTokenStore()
        let transport = FakeTransport(["GET http://sample.example/api/capabilities": (200, SandboxResponses.capabilities)])
        let model = LibraryModel(inMemoryWith: Self.httpFetcher(), tokens: tokens, transport: transport)
        // Reading is untouched: the blyg is added under its http origin, with its posts.
        #expect(try await model.add("http://sample.example/") == Self.httpOrigin)
        #expect(model.blyg(Self.httpOrigin)?.items.isEmpty == false)
        #expect(!model.timeline.isEmpty)

        await #expect(throws: LibraryModel.ConnectFailure.needsHTTPS) { try await model.connect(Self.httpOrigin, token: "secret") }
        // Says why, and doesn't promise reading: iOS blocks plain-http loads to public hosts.
        #expect(LibraryModel.describe(.needsHTTPS).contains("https"))
        #expect(!LibraryModel.describe(.needsHTTPS).localizedCaseInsensitiveContains("read"))
        #expect(tokens.token(for: Self.httpOrigin) == nil)
        #expect(!model.isConnected(Self.httpOrigin))
        #expect(transport.sent.isEmpty)
    }

    @Test func aSavedConnectionToAnHTTPBlygIsNeverUsed() async throws {
        let store = LibraryStore(directory: FileManager.default.temporaryDirectory.appending(path: "blyg tests \(UUID().uuidString)"))
        defer { try? FileManager.default.removeItem(at: store.directory) }
        var blyg = try SavedBlyg.sample()
        blyg.origin = Self.httpOrigin
        blyg.postingAPI = URL(string: "http://sample.example/api")
        blyg.studioFollows = []
        try store.save(Library(blygs: [blyg]))
        let tokens = MemoryTokenStore()
        try tokens.save("secret", for: Self.httpOrigin)
        let transport = FakeTransport(["GET http://sample.example/api/subscriptions": (200, #"{"items":[],"page":{"nextCursor":null}}"#)])
        let model = LibraryModel(store: store, fetcher: Self.httpFetcher(), tokens: tokens, transport: transport)

        #expect(model.blyg(Self.httpOrigin)?.postingAPI == nil)
        #expect(model.postingBlygs.isEmpty)
        #expect(model.poster(for: Self.httpOrigin) == nil)
        await #expect(throws: LibraryModel.ConnectFailure.self) { _ = try await model.importSubscriptions(from: Self.httpOrigin) }
        await model.followStudiosNewSubscriptions(Self.httpOrigin)
        await model.refresh(Self.httpOrigin)
        #expect(model.blyg(Self.httpOrigin)?.lastError == nil) // still read
        #expect(transport.sent.isEmpty)
        await model.saveFinished() // before the folder is removed
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
        let studioAPI = origin.appending(path: "studio/api")
        try store.save("third", for: origin, title: "My blyg", api: studioAPI)
        let mine = store.connections().first { $0.origin == origin }
        #expect(mine == Connection(origin: origin, title: "My blyg", api: studioAPI))
        // An API on another host, as an earlier build could have saved, is never handed back: the token would follow it.
        try store.save("fourth", for: origin, title: "My blyg", api: URL(string: "https://x.example/api")!)
        #expect(store.connections().first { $0.origin == origin }?.api == StudioClient.apiBase(forOrigin: origin))
        // A token saved for an http blyg is no connection: the Share extension never sees it.
        let insecure = URL(string: "http://keychain-test-\(UUID().uuidString.lowercased()).example/")!
        defer { store.remove(for: insecure) }
        try store.save("fifth", for: insecure)
        #expect(!store.connections().contains { $0.origin == insecure })
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

@Suite("Replies and subscriptions")
@MainActor
struct ReplyTests {
    let target = ReplyTarget(origin: URL(string: "https://other.example/")!, id: "abc123", version: 3,
                             blygTitle: "Other Notes", excerpt: String(repeating: "x", count: 250),
                             page: URL(string: "https://other.example/f/abc123/"))

    @Test func aReplyIsAThreadWithStubOf() throws {
        let stub = target.stubOf(retrieved: Date(timeIntervalSince1970: 1_800_000_000))
        let req = Requests.createItem(api: SandboxResponses.api, token: "t", contentMd: "Yes, and", kind: "thread", stubOf: stub)
        let data = try #require(req.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["kind"] as? String == "thread")
        let sent = try #require(json["stubOf"] as? [String: Any])
        #expect(sent["origin"] as? String == "https://other.example/") // absolute, trailing slash
        #expect(sent["id"] as? String == "abc123")
        #expect(sent["version"] as? Int == 3)
        let cited = try #require(sent["cited"] as? [String: Any])
        #expect(cited["source"] as? String == "Other Notes")
        #expect((cited["excerpt"] as? String)?.count == 200) // a caption, capped near 200 (§5.9)
        #expect(cited["retrieved"] as? String == "2027-01-15T08:00:00Z")
        #expect(cited["url"] as? String == "https://other.example/f/abc123/")
    }

    @Test func posterSendsRepliesAsThreads() async throws {
        let transport = SandboxResponses.happyPath()
        let poster = Poster(client: StudioClient(api: SandboxResponses.api, token: "t", transport: transport), origin: SandboxResponses.origin)
        _ = try await poster.post(PostDraft(text: "Yes, and"), replyTo: target)
        let first = try #require(transport.sent.first?.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: first) as? [String: Any])
        #expect(body["kind"] as? String == "thread")
        #expect(body["stubOf"] != nil)
        _ = try await poster.post(PostDraft(text: "Plain"))
        let third = try #require(transport.sent[2].httpBody)
        let plain = try #require(JSONSerialization.jsonObject(with: third) as? [String: Any])
        #expect(plain["kind"] as? String == "fragment")
        #expect(plain["stubOf"] == nil)
    }

    @Test func stubOfDecodesAsTheSandboxPublishedIt() throws {
        // The public item document of a reply published on the sandbox, 2026-11-22.
        let doc = try decode(ItemDocument.self, #"{"id":"r1","kind":"thread","version":1,"created":"2026-11-22T14:17:30Z","updated":"2026-11-22T14:17:30Z","content_html":"<p>Probe reply.</p>","stub_of":{"origin":"https://blyg-sandbox.exe.xyz/","id":"1k2q07a2hvx3z3pq8dr82h4mfg","version":1,"cited":{"source":"Blyg sandbox","excerpt":"sandbox post tap tap tap","url":"https://blyg-sandbox.exe.xyz/f/1k2q07a2hvx3z3pq8dr82h4mfg/","retrieved":"2026-11-22T14:17:30Z"}}}"#)
        let stub = try #require(doc.stubOf)
        #expect(stub.label == "Blyg sandbox")
        #expect(stub.link?.absoluteString == "https://blyg-sandbox.exe.xyz/f/1k2q07a2hvx3z3pq8dr82h4mfg/")
        let entry = TimelineEntry(origin: SandboxResponses.origin, blygTitle: "Blyg sandbox", document: doc, sortDate: .now, excerpt: "", imageURL: nil)
        let html = PostPage.html(for: entry, pageURL: nil, theme: Theme(appearance: .studio))
        #expect(html.contains("Replying to <a href=\"https://blyg-sandbox.exe.xyz/f/1k2q07a2hvx3z3pq8dr82h4mfg/\">Blyg sandbox</a>"))
        // A bare {url} stub with no citation still has something to show.
        let web = try decode(ItemDocument.StubOf.self, #"{"url":"https://news.example/story"}"#)
        #expect(web.label == "news.example")
    }

    @Test func followingAStudiosSubscriptionsAddsBlygsOnly() async throws {
        let tokens = MemoryTokenStore()
        let fetcher = FakeFetcher.sample()
        fetcher.set("https://second.example/blyg.json", .init(body: #"{"blyg":"0.4","title":"Second"}"#))
        fetcher.set("https://second.example/items/index.json", .init(body: #"{"items":[]}"#))
        let transport = FakeTransport([
            "GET https://sample.example/api/capabilities": (200, SandboxResponses.capabilities.replacingOccurrences(of: "blyg-sandbox.exe.xyz", with: "sample.example")),
            "GET https://sample.example/api/subscriptions": (200, #"{"items":[{"kind":"blyg","origin":"https://second.example/","title":"Second"},{"kind":"blyg","origin":"https://sample.example/","title":"Sample"},{"kind":"rss","feedUrl":"https://feeds.example/x.xml","title":"A feed"},{"kind":"blyg","origin":"https://gone.example/","title":"Gone"}],"page":{"limit":100,"nextCursor":null}}"#),
        ])
        let model = LibraryModel(store: nil, fetcher: fetcher, tokens: tokens, transport: transport)
        try await model.add("sample.example")
        try await model.connect(Fixtures.origin, token: "secret")
        let result = try await model.importSubscriptions(from: Fixtures.origin)
        #expect(result.added == 1)
        #expect(result.alreadyFollowing == 1)
        #expect(result.skippedFeeds == 1)
        #expect(result.failed == ["gone.example"])
        #expect(result.retrying == 1)
        #expect(model.library.blygs.map(\.origin.absoluteString) == ["https://sample.example/", "https://second.example/"])
        // Keeping in step from now on. The two it could reach are remembered as dealt with; the one it couldn't
        // isn't, and waits to be tried again when the app next opens (see PendingFollowTests).
        #expect(model.blyg(Fixtures.origin)?.studioFollows?.map(\.absoluteString) == ["https://second.example/", "https://sample.example/"])
        #expect(model.blyg(Fixtures.origin)?.pendingFollows == [PendingFollow(origin: URL(string: "https://gone.example/")!, attempts: 1)])
    }

    @Test func keepingInStepFollowsOnlyBlygsNewToTheStudio() async throws {
        let fetcher = FakeFetcher.sample()
        for host in ["second", "third"] {
            fetcher.set("https://\(host).example/blyg.json", .init(body: #"{"blyg":"0.4","title":"T"}"#))
            fetcher.set("https://\(host).example/items/index.json", .init(body: #"{"items":[]}"#))
        }
        let list = { (hosts: [String]) in
            #"{"items":["# + hosts.map { #"{"kind":"blyg","origin":"https://\#($0).example/","title":"T"}"# }.joined(separator: ",")
                + #"],"page":{"limit":100,"nextCursor":null}}"#
        }
        let transport = FakeTransport([
            "GET https://sample.example/api/capabilities": (200, SandboxResponses.capabilities.replacingOccurrences(of: "blyg-sandbox.exe.xyz", with: "sample.example")),
            "GET https://sample.example/api/subscriptions": (200, list(["second"])),
        ])
        let model = LibraryModel(store: nil, fetcher: fetcher, tokens: MemoryTokenStore(), transport: transport)
        try await model.add("sample.example")
        try await model.connect(Fixtures.origin, token: "secret")
        _ = try await model.importSubscriptions(from: Fixtures.origin)
        model.remove(URL(string: "https://second.example/")!) // unfollowed here, still followed in Studio

        transport.set("GET https://sample.example/api/subscriptions", (200, list(["second", "third"])))
        await model.refresh(Fixtures.origin)
        #expect(model.library.blygs.map(\.origin.absoluteString) == ["https://sample.example/", "https://third.example/"])

        model.stopKeepingInStep(Fixtures.origin)
        transport.set("GET https://sample.example/api/subscriptions", (200, list(["second", "third", "fourth"])))
        await model.refresh(Fixtures.origin)
        #expect(model.library.blygs.count == 2) // off: nothing new is followed
    }

    @Test func comingBackRefreshesYourOwnBlygSoonerThanOthers() async throws {
        let fetcher = FakeFetcher.sample()
        fetcher.set("https://second.example/blyg.json", .init(body: #"{"blyg":"0.4","title":"Second"}"#))
        fetcher.set("https://second.example/items/index.json", .init(body: #"{"items":[]}"#))
        let transport = FakeTransport([
            "GET https://sample.example/api/capabilities": (200, SandboxResponses.capabilities.replacingOccurrences(of: "blyg-sandbox.exe.xyz", with: "sample.example")),
        ])
        let model = LibraryModel(store: nil, fetcher: fetcher, tokens: MemoryTokenStore(), transport: transport)
        try await model.add("sample.example")
        try await model.add("second.example")
        try await model.connect(Fixtures.origin, token: "secret")
        func manifestFetches() -> [String] { fetcher.requested.filter { $0.hasSuffix("blyg.json") } }
        let before = manifestFetches()
        await model.refreshStale(now: .now.addingTimeInterval(60)) // a minute on: only the connected one
        #expect(manifestFetches().count == before.count + 1)
        #expect(manifestFetches().last == "https://sample.example/blyg.json")
        await model.refreshStale(now: .now.addingTimeInterval(20 * 60)) // much later: both
        #expect(manifestFetches().count == before.count + 3)
    }
}

@Suite("Where a post goes by default")
struct PostTargetTests {
    let live = URL(string: "https://live.example/")!
    let sandbox = URL(string: "https://sandbox.example/")!
    let other = URL(string: "https://someone-else.example/")!

    @Test func aReplyToYourOwnBlygGoesOutFromThatBlyg() {
        #expect(PostTarget.choose(replyingTo: sandbox, connected: [live, sandbox], lastUsed: live) == sandbox)
    }

    @Test func otherwiseTheLastBlygUsedWins() {
        #expect(PostTarget.choose(replyingTo: other, connected: [live, sandbox], lastUsed: sandbox) == sandbox)
        #expect(PostTarget.choose(replyingTo: nil, connected: [live, sandbox], lastUsed: sandbox) == sandbox)
    }

    @Test func aForgottenOrDisconnectedLastUseFallsBackToTheFirst() {
        #expect(PostTarget.choose(replyingTo: nil, connected: [live, sandbox], lastUsed: other) == live)
        #expect(PostTarget.choose(replyingTo: nil, connected: [live, sandbox], lastUsed: nil) == live)
        #expect(PostTarget.choose(replyingTo: nil, connected: [], lastUsed: live) == nil)
    }
}
