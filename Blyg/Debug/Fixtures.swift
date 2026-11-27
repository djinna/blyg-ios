#if DEBUG
import Foundation

/// A fictional blyg for tests and screenshots: https://sample.example/ (a reserved domain).
/// It reproduces the shapes met on live blygs, not their content: URLs with a leading space,
/// several versions of one item, a thread with a baked quote, a withdrawn item, an unknown kind,
/// and an index entry that doesn't parse. A second, unfollowed blyg at https://elsewhere.example/blyg/ (path-mounted)
/// holds one post the thread links to, for quote cards.
nonisolated enum Fixtures {
    static let origin = URL(string: "https://sample.example/")!
    /// "Now" for the fixture blyg, a day after its newest post: what the main feed's window is measured from
    /// when the app runs on fixtures, so every post here stays inside it whatever the real date.
    static let now = BlygDate.parse("2026-11-20T12:00:00Z")!

    static let fragmentEdited = "1f1f1f1f1f1f1f1f1f1f1f1f1f"
    static let fragmentPlain = "2f2f2f2f2f2f2f2f2f2f2f2f2f"
    static let thread = "3t3t3t3t3t3t3t3t3t3t3t3t3t"
    static let withdrawn = "4w4w4w4w4w4w4w4w4w4w4w4w4w"
    static let unknownKind = "5p5p5p5p5p5p5p5p5p5p5p5p5p"
    static let elsewhereOrigin = URL(string: "https://elsewhere.example/blyg/")!
    static let elsewherePost = "7e7e7e7e7e7e7e7e7e7e7e7e7e"
    static let hosts: Set<String> = ["sample.example", "elsewhere.example"]

    struct Response: Sendable {
        var status: Int
        var contentType: String
        var body: String
    }

    static let manifest = """
    {"blyg":"0.4","level":2,"generator":"sample-client/1.0","site":" https://sample.example/","title":"Sample Notes",\
    "author":{"name":"Sam Sample","bio":"A fictional blyg for tests.","links":[]},"feed":"feed.xml",\
    "items":"items/index.json","updated":"2026-11-19T10:00:00Z","webmention":"webmention"}
    """

    static let index = """
    {"updated":"2026-11-19T10:00:00Z","items":[
    {"id":"\(thread)","kind":"thread","created":"2026-11-19T09:58:00Z","updated":"2026-11-19T10:00:00Z","version":1},
    {"id":"\(fragmentEdited)","kind":"fragment","created":"2026-11-18T08:00:00Z","updated":"2026-11-18T09:00:00Z","version":2},
    {"id":"\(withdrawn)","kind":"withdrawn","created":"2026-11-10T08:00:00Z","updated":"2026-11-17T12:00:00Z","version":3},
    {"id":"\(unknownKind)","kind":"poll","created":"2026-11-16T08:00:00Z","updated":"2026-11-16T08:00:00Z","version":1},
    {"id":5,"kind":"fragment"},
    {"id":"\(fragmentPlain)","kind":"fragment","created":"2026-11-15T07:30:00Z","updated":"2026-11-15T07:30:00Z","version":1}
    ]}
    """

    static let fragmentEditedDocument = """
    {"blyg":"0.4","id":"\(fragmentEdited)","kind":"fragment","origin":" https://sample.example/","page":"f/\(fragmentEdited)/",\
    "author":{"name":"Sam Sample","url":" https://sample.example/","sig":{"alg":"none"}},\
    "created":"2026-11-18T08:00:00Z","updated":"2026-11-18T09:00:00Z","version":2,\
    "content_md":"Reading about [print on demand](https://example.org/print) again. Margins matter more than fonts.",\
    "content_html":"<p>Reading about <a href=\\"https://example.org/print\\">print on demand</a> again. Margins matter more than fonts.</p>\\n<p><img src=\\"https://sample.example/media/spread.png\\" alt=\\"a page spread\\"></p>\\n",\
    "content_hash":"sha256:0000000000000000000000000000000000000000000000000000000000000000",\
    "media":[{"url":"media/spread.png","mime":"image/png","alt":"a page spread"}],\
    "changelog":[{"version":1,"at":"2026-11-18T08:00:00Z","note":null,"pinned":true},{"version":2,"at":"2026-11-18T09:00:00Z","note":"added the link"}]}
    """

    static let fragmentPlainDocument = """
    {"blyg":"0.4","id":"\(fragmentPlain)","kind":"fragment","origin":"https://sample.example/","page":"f/\(fragmentPlain)/",\
    "created":"2026-11-15T07:30:00Z","updated":"2026-11-15T07:30:00Z","version":1,\
    "content_md":"First post. Does anyone still read RSS & does it matter?",\
    "content_html":"<p>First post. Does anyone still read RSS &amp; does it matter?</p>\\n",\
    "content_hash":"sha256:0000000000000000000000000000000000000000000000000000000000000000","media":[],\
    "changelog":[{"version":1,"at":"2026-11-15T07:30:00Z","note":null}]}
    """

    static let threadDocument = """
    {"blyg":"0.4","id":"\(thread)","kind":"thread","origin":"https://sample.example/","page":"t/\(thread)/",\
    "author":{"name":"Sam Sample"},"created":"2026-11-19T09:58:00Z","updated":"2026-11-19T10:00:00Z","version":1,\
    "content_md":"Two notes, one thought.\\n\\n![[\(fragmentEdited)]]\\n\\nBoth are about pace.",\
    "content_html":"<p>Two notes, one thought.</p>\\n<blockquote class=\\"blyg-transclusion\\" data-blyg-id=\\"\(fragmentEdited)\\"><p>Reading about print on demand again. Margins matter more than fonts.</p></blockquote>\\n<p>Both are about pace.</p>\\n<p>Elsewhere <a href=\\"https://elsewhere.example/blyg/f/\(elsewherePost)/\\">someone</a> said so too, and <a href=\\"https://sample.example/f/\(withdrawn)/\\">I took back</a> what I said <a href=\\"https://example.org/pace\\">here</a>.</p>\\n",\
    "content_hash":"sha256:0000000000000000000000000000000000000000000000000000000000000000","media":[],\
    "transclusions":[{"id":"\(fragmentEdited)","version":2}],\
    "stub_of":{"origin":"https://sample.example/","id":"\(fragmentPlain)","version":1,"cited":{"source":"Sample Notes","excerpt":"First post. Does anyone still read RSS & does it matter?","retrieved":"2026-11-19T09:58:00Z"}},\
    "changelog":[{"version":1,"at":"2026-11-19T10:00:00Z","note":null}]}
    """

    static let withdrawnDocument = """
    {"blyg":"0.4","id":"\(withdrawn)","kind":"withdrawn","origin":"https://sample.example/","page":"f/\(withdrawn)/",\
    "created":"2026-11-10T08:00:00Z","updated":"2026-11-17T12:00:00Z","version":3,"content_md":"","content_html":"",\
    "content_hash":"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855","media":[],\
    "changelog":[{"version":1,"at":"2026-11-10T08:00:00Z","note":null},{"version":2,"at":"2026-11-11T08:00:00Z","note":null},{"version":3,"at":"2026-11-17T12:00:00Z","note":"taking this back"}]}
    """

    static let unknownKindDocument = """
    {"blyg":"0.4","id":"\(unknownKind)","kind":"poll","origin":"https://sample.example/","created":"2026-11-16T08:00:00Z",\
    "updated":"2026-11-16T08:00:00Z","version":1,"content_md":"?","content_html":"<p>?</p>","media":[],"changelog":[]}
    """

    static let feed = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0" xmlns:blyg="https://blygger.org/ns/0.1"><channel><title>Sample Notes</title>
    <link> https://sample.example/</link><description>A fictional blyg for tests.</description>
    <blyg:manifest> https://sample.example/blyg.json</blyg:manifest></channel></rss>
    """

    static let elsewhereManifest = """
    {"blyg":"0.4","title":"Elsewhere Journal","author":{"name":"Eli Elsewhere"},"items":"items/index.json"}
    """

    static let elsewhereDocument = """
    {"blyg":"0.4","id":"\(elsewherePost)","kind":"fragment","origin":"https://elsewhere.example/blyg/","page":"f/\(elsewherePost)/",\
    "author":{"name":"Eli Elsewhere"},"created":"2026-11-17T14:00:00Z","updated":"2026-11-17T14:00:00Z","version":1,\
    "content_md":"Slow is a feature.","content_html":"<p>Slow is a feature. A feed you can finish is a feed you can trust.</p><p><img src=\\"media/x.png\\"></p>",\
    "media":[],"changelog":[{"version":1,"at":"2026-11-17T14:00:00Z","note":null}]}
    """

    static let elsewhereIndex = """
    {"items":[{"id":"\(elsewherePost)","kind":"fragment","created":"2026-11-17T14:00:00Z","updated":"2026-11-17T14:00:00Z","version":1}]}
    """

    static let responses: [String: Response] = [
        "https://elsewhere.example/blyg/blyg.json": Response(status: 200, contentType: "application/json", body: elsewhereManifest),
        "https://elsewhere.example/blyg/items/index.json": Response(status: 200, contentType: "application/json", body: elsewhereIndex),
        "https://elsewhere.example/blyg/items/\(elsewherePost).json": Response(status: 200, contentType: "application/json", body: elsewhereDocument),
        "https://sample.example/blyg.json": Response(status: 200, contentType: "application/json", body: manifest),
        "https://sample.example/feed.xml": Response(status: 200, contentType: "application/rss+xml", body: feed),
        "https://sample.example/items/index.json": Response(status: 200, contentType: "application/json", body: index),
        "https://sample.example/items/\(fragmentEdited).json": Response(status: 200, contentType: "application/json", body: fragmentEditedDocument),
        "https://sample.example/items/\(fragmentPlain).json": Response(status: 200, contentType: "application/json", body: fragmentPlainDocument),
        "https://sample.example/items/\(thread).json": Response(status: 200, contentType: "application/json", body: threadDocument),
        "https://sample.example/items/\(withdrawn).json": Response(status: 200, contentType: "application/json", body: withdrawnDocument),
        "https://sample.example/items/\(unknownKind).json": Response(status: 200, contentType: "application/json", body: unknownKindDocument),
    ]

    /// A pretend Studio owner API for sample.example, answering the calls the composer makes.
    /// Bodies follow the shapes the real API returned on the sandbox blyg (Studio 0.65.0).
    static let fixtureToken = "fixture-token"
    static let draftId = "6d6d6d6d6d6d6d6d6d6d6d6d6d"
    static let apiResponses: [String: Response] = [
        "GET https://sample.example/api/capabilities": Response(status: 200, contentType: "application/json", body: """
            {"contractVersion":"5.14.0","endpoints":{"publicBase":"https://sample.example","studio":"https://sample.example/studio","api":"https://sample.example/api"},"operations":["createItem"]}
            """),
        // The Studio follows the second fixture blyg, for the launch retry's UI test.
        "GET https://sample.example/api/subscriptions": Response(status: 200, contentType: "application/json", body: """
            {"items":[{"kind":"blyg","origin":"https://elsewhere.example/blyg/","title":"Elsewhere Journal"}],"page":{"limit":100,"nextCursor":null}}
            """),
        "POST https://sample.example/api/items": Response(status: 201, contentType: "application/json", body: """
            {"id":"\(draftId)","revision":1,"kind":"fragment","status":"draft","created":"2026-11-20T21:37:10Z","updated":"2026-11-20T21:37:10Z","version":0,"contentMd":"Hello","dirty":true,"stubOf":null,"forkedFrom":null,"forkCite":null,"provenance":[],"responses":"default","highlight":"default"}
            """),
        "POST https://sample.example/api/media": Response(status: 201, contentType: "application/json", body: """
            {"id":"m1m1m1m1","url":"https://sample.example/media/m1m1m1m1/0000.jpg","mime":"image/jpeg","revision":2}
            """),
        "PATCH https://sample.example/api/items/\(draftId)": Response(status: 200, contentType: "application/json", body: """
            {"id":"\(draftId)","revision":3,"kind":"fragment","status":"draft","created":"2026-11-20T21:37:10Z","updated":"2026-11-20T21:37:12Z","version":0,"contentMd":"Hello","dirty":true,"stubOf":null,"forkedFrom":null,"forkCite":null,"provenance":[],"responses":"default","highlight":"default"}
            """),
        "POST https://sample.example/api/items/\(draftId)/publish": Response(status: 200, contentType: "application/json", body: """
            {"ok":true,"version":1,"revision":4}
            """),
    ]

    static func response(for url: URL, method: String = "GET", authorization: String? = nil) -> Response {
        if url.path().hasPrefix("/api/") {
            guard authorization == "Bearer \(fixtureToken)" else {
                return Response(status: 401, contentType: "application/json", body: #"{"code":"unauthorized","message":"unauthorized"}"#)
            }
            return apiResponses["\(method) \(url.absoluteString)"]
                ?? Response(status: 404, contentType: "application/json", body: #"{"code":"not-found","message":"not found"}"#)
        }
        return responses[url.absoluteString] ?? Response(status: 404, contentType: "text/plain", body: "Not Found")
    }
}

/// Serves `Fixtures` to URLSession when the app runs with `-useFixtures`.
nonisolated final class FixtureURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        // Any other host behaves as if the phone were offline, for the offline-state screenshot.
        guard let host = url.host(), Fixtures.hosts.contains(host) else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let fixture = Fixtures.response(for: url, method: request.httpMethod ?? "GET",
                                        authorization: request.value(forHTTPHeaderField: "Authorization"))
        let response = HTTPURLResponse(url: url, statusCode: fixture.status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": fixture.contentType])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(fixture.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
#endif
