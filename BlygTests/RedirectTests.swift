import Foundation
import os
import Testing
@testable import Blyg

/// A stand-in network under the real `URLSessionTransport`, so the transport's own redirect handling runs.
/// Answers from a table keyed by URL, where an answer can be a redirect, and records every request that
/// reaches it. Tests run side by side, so each one uses hosts of its own.
final class RedirectingNetwork: URLProtocol, @unchecked Sendable {
    enum Answer {
        /// `droppingToken` proposes the next request without its Authorization header, as URLSession can.
        case redirect(Int, to: String, droppingToken: Bool = false)
        case body(Int, String)
    }

    private struct State {
        var answers: [String: Answer] = [:]
        var seen: [URLRequest] = []
    }
    private static let state = OSAllocatedUnfairLock(initialState: State())

    static func set(_ answers: [String: Answer]) {
        state.withLock { $0.answers.merge(answers) { _, new in new } }
    }

    /// "METHOD URL" for each request that reached a host ending in `suffix`, in order.
    static func requests(toHostsEnding suffix: String) -> [String] {
        seen(suffix).map { "\($0.httpMethod ?? "") \($0.url!.absoluteString)" }
    }

    static func seen(_ suffix: String) -> [URLRequest] {
        state.withLock { $0.seen.filter { $0.url?.host()?.hasSuffix(suffix) == true } }
    }

    /// "METHOD URL" for each request that carried `token`, in order, whatever its host.
    static func requests(carrying token: String) -> [String] {
        state.withLock { $0.seen.filter { $0.value(forHTTPHeaderField: "Authorization") == "Bearer \(token)" } }
            .map { "\($0.httpMethod ?? "") \($0.url!.absoluteString)" }
    }

    /// The real posting transport, with this network under it.
    static func transport() -> URLSessionTransport {
        let config = URLSessionTransport.defaultConfiguration()
        config.protocolClasses = [RedirectingNetwork.self]
        return URLSessionTransport(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let answer = Self.state.withLock { state -> Answer? in
            state.seen.append(request)
            return state.answers[url.absoluteString]
        }
        switch answer {
        case .redirect(let status, let location, let droppingToken):
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Location": location])!
            // As a server's 307 or 308 would have it: the same method, headers (the token among them) and body.
            var next = request
            next.url = URL(string: location)
            if droppingToken { next.setValue(nil, forHTTPHeaderField: "Authorization") }
            client?.urlProtocol(self, wasRedirectedTo: next, redirectResponse: response)
            // When the redirect isn't followed, the redirecting answer is the answer, as on the real network.
            finish(response, body: "")
        case .body(let status, let body):
            finish(HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!, body: body)
        case nil:
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
        }
    }

    private func finish(_ response: HTTPURLResponse, body: String) {
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("Redirects while posting")
struct RedirectTests {
    /// Hosts for one test: `blyg.<id>.example` is the blyg, anything else under `<id>.example` is not.
    let zone = "\(UUID().uuidString.lowercased()).example"
    var api: URL { URL(string: "https://blyg.\(zone)/api")! }
    func client() -> StudioClient { StudioClient(api: api, token: "secret", transport: RedirectingNetwork.transport()) }

    /// Where a redirect off the blyg's server might point, with `ZONE` standing for this test's hosts.
    static let offTheServer = [
        "https://elsewhere.ZONE/api/capabilities",      // another host
        "http://blyg.ZONE/api/capabilities",            // the same host, no longer https
        "https://blyg.ZONE:8443/api/capabilities",      // the same host, another port
        "https://blyg.ZONE.elsewhere.ZONE/api/capabilities",
    ]

    @Test(arguments: offTheServer)
    func aRedirectOffTheBlygsServerIsRefused(_ pattern: String) async {
        let target = pattern.replacingOccurrences(of: "ZONE", with: zone)
        RedirectingNetwork.set([
            "https://blyg.\(zone)/api/capabilities": .redirect(307, to: target),
            target: .body(200, SandboxResponses.capabilities),
        ])
        await #expect(throws: StudioClient.redirectRefused) { _ = try await client().getCapabilities() }
        // Only the blyg itself was asked: nothing, so no token, went to the redirect's target.
        #expect(RedirectingNetwork.requests(toHostsEnding: zone) == ["GET https://blyg.\(zone)/api/capabilities"])
    }

    @Test func aPostRedirectedElsewhereIsNotSentOn() async {
        let target = "https://elsewhere.\(zone)/api/items"
        RedirectingNetwork.set([
            "https://blyg.\(zone)/api/items": .redirect(308, to: target),
            target: .body(201, SandboxResponses.created),
        ])
        await #expect(throws: StudioClient.redirectRefused) { _ = try await client().createItem(contentMd: "Hello") }
        #expect(RedirectingNetwork.requests(toHostsEnding: zone) == ["POST https://blyg.\(zone)/api/items"])
    }

    /// Followed, and with the token: once when the proposed request still has it, once when it arrives without.
    @Test(arguments: ["https://blyg.ZONE/studio/api/capabilities", "https://BLYG.ZONE:443/studio/api/capabilities"], [false, true])
    func aRedirectOnTheBlygsOwnServerIsFollowedWithTheToken(_ pattern: String, droppingToken: Bool) async throws {
        let target = pattern.replacingOccurrences(of: "ZONE", with: zone)
        RedirectingNetwork.set([
            "https://blyg.\(zone)/api/capabilities": .redirect(307, to: target, droppingToken: droppingToken),
            target: .body(200, SandboxResponses.capabilities),
        ])
        let capabilities = try await client().getCapabilities()
        #expect(capabilities.contractVersion == "5.14.0")
        #expect(RedirectingNetwork.requests(toHostsEnding: zone) == ["GET https://blyg.\(zone)/api/capabilities", "GET \(target)"])
        #expect(RedirectingNetwork.seen(zone).map { $0.value(forHTTPHeaderField: "Authorization") } == ["Bearer secret", "Bearer secret"])
    }

    /// The token is put back only on the blyg's own server: a redirect elsewhere that arrives without it is refused all the same.
    @Test func aRedirectElsewhereWithoutTheTokenIsStillRefused() async {
        let target = "https://elsewhere.\(zone)/api/capabilities"
        RedirectingNetwork.set([
            "https://blyg.\(zone)/api/capabilities": .redirect(307, to: target, droppingToken: true),
            target: .body(200, SandboxResponses.capabilities),
        ])
        await #expect(throws: StudioClient.redirectRefused) { _ = try await client().getCapabilities() }
        #expect(RedirectingNetwork.requests(toHostsEnding: zone) == ["GET https://blyg.\(zone)/api/capabilities"])
    }

    @Test func aChainThatLeavesTheServerLaterIsRefusedThere() async {
        let onward = "https://blyg.\(zone)/studio/api/capabilities"
        let away = "https://elsewhere.\(zone)/api/capabilities"
        RedirectingNetwork.set([
            "https://blyg.\(zone)/api/capabilities": .redirect(307, to: onward),
            onward: .redirect(307, to: away),
            away: .body(200, SandboxResponses.capabilities),
        ])
        await #expect(throws: StudioClient.redirectRefused) { _ = try await client().getCapabilities() }
        #expect(RedirectingNetwork.requests(toHostsEnding: zone) == ["GET https://blyg.\(zone)/api/capabilities", "GET \(onward)"])
    }

    /// Connecting sends the token for the first time; a redirect elsewhere must end it, with nothing saved.
    @Test @MainActor func connectingStopsAtARedirectElsewhereAndSavesNothing() async throws {
        let away = "https://elsewhere.\(zone)/api/capabilities"
        RedirectingNetwork.set([
            "https://sample.example/api/capabilities": .redirect(307, to: away),
            away: .body(200, SandboxResponses.capabilities),
        ])
        let tokens = MemoryTokenStore()
        let model = LibraryModel(store: nil, fetcher: FakeFetcher.sample(), tokens: tokens, transport: RedirectingNetwork.transport())
        try await model.add("sample.example")
        // The fixture blyg's host is the same on every run, so this run's requests are picked out by its token.
        let token = "secret-\(zone)"
        await #expect(throws: LibraryModel.ConnectFailure.other(StudioClient.redirectRefused.message)) {
            try await model.connect(Fixtures.origin, token: token)
        }
        #expect(tokens.token(for: Fixtures.origin) == nil)
        #expect(!model.isConnected(Fixtures.origin))
        #expect(RedirectingNetwork.requests(toHostsEnding: zone).isEmpty)
        #expect(RedirectingNetwork.requests(carrying: token) == ["GET https://sample.example/api/capabilities"])
    }

    @Test func theSameServerMeansHTTPSTheSameHostAndTheSamePort() {
        func same(_ a: String, _ b: String) -> Bool { StudioClient.sameHTTPSServer(URL(string: a)!, URL(string: b)!) }
        #expect(same("https://example.com/a", "https://example.com/b?c"))
        #expect(same("https://example.com:443/a", "https://EXAMPLE.com/b"))
        #expect(!same("http://example.com/a", "https://example.com/a"))
        #expect(!same("https://example.com/a", "http://example.com/a"))
        #expect(!same("http://example.com/a", "http://example.com/a"))
        #expect(!same("https://example.com:8443/a", "https://example.com/a"))
        #expect(!same("https://www.example.com/a", "https://example.com/a"))
        #expect(!same("https://example.com@elsewhere.example/a", "https://example.com/a"))
        #expect(!same("/a", "https://example.com/a"))
    }
}
