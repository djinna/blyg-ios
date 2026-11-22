import Foundation
import Testing
@testable import Blyg

@Suite("Protocol documents")
struct DocumentTests {
    @Test func manifestDecodesAndKeepsSelfAssertedSiteAsIs() throws {
        let manifest = try decode(Manifest.self, Fixtures.manifest)
        #expect(manifest.blyg == "0.4")
        #expect(manifest.title == "Sample Notes")
        #expect(manifest.site == " https://sample.example/") // display-only; never used for identity
        #expect(manifest.author?.name == "Sam Sample")
        #expect(manifest.items == "items/index.json")
    }

    @Test func aJSONObjectWithoutABlygKeyIsNotAManifest() {
        #expect(throws: (any Error).self) { try decode(Manifest.self, #"{"title":"x"}"#) }
    }

    @Test func oddAuthorAndUnknownMembersDontRejectTheDocument() throws {
        let manifest = try decode(Manifest.self, #"{"blyg":"0.9","title":7,"author":"just a string","future":{"a":1}}"#)
        #expect(manifest.blyg == "0.9")
        #expect(manifest.title == nil)
        #expect(manifest.author == nil)
    }

    @Test func indexSkipsAnEntryThatDoesntParse() throws {
        let index = try decode(ItemIndex.self, Fixtures.index)
        #expect(index.items.count == 5)
        #expect(index.items.map(\.kind).contains("poll"))
    }

    @Test func itemDocumentReadsChangelogAndPins() throws {
        let doc = try decode(ItemDocument.self, Fixtures.fragmentEditedDocument)
        #expect(doc.version == 2)
        #expect(doc.kind == "fragment")
        #expect(doc.changelog.count == 2)
        #expect(doc.pinnedVersions == [1])
        #expect(doc.author?.name == "Sam Sample") // the extra "sig" member is ignored
        #expect(doc.contentHTML.contains("print on demand"))
    }
}

@Suite("URLs")
struct URLTests {
    let origin = URL(string: "https://sample.example/notes/")!

    @Test func referencesWithStrayWhitespaceStillResolve() {
        #expect(BlygURL.resolve(" https://sample.example/", against: origin)?.absoluteString == "https://sample.example/")
        #expect(BlygURL.resolve("items/x.json", against: origin)?.absoluteString == "https://sample.example/notes/items/x.json")
        #expect(BlygURL.resolve("/media/a.png", against: origin)?.absoluteString == "https://sample.example/media/a.png")
        #expect(BlygURL.resolve("   ", against: origin) == nil)
    }

    @Test func itemTemplateFromTheManifestWins() {
        var manifest = Manifest(blyg: "0.4")
        #expect(BlygURL.itemDocument(id: "abc", origin: origin, manifest: manifest)?.absoluteString
                == "https://sample.example/notes/items/abc.json")
        manifest.item = "https://api.sample.example/blyg/v1/items/{id}?format=json"
        #expect(BlygURL.itemDocument(id: "abc", origin: origin, manifest: manifest)?.absoluteString
                == "https://api.sample.example/blyg/v1/items/abc?format=json")
    }

    @Test func identityIsTheFetchedManifestsDirectory() {
        let url = URL(string: "https://sample.example/notes/blyg.json?x=1")!
        #expect(BlygURL.identityOrigin(manifestURL: url)?.absoluteString == "https://sample.example/notes/")
        #expect(BlygURL.identityOrigin(manifestURL: URL(string: "https://sample.example/blyg.json")!)?.absoluteString
                == "https://sample.example/")
    }

    @Test func candidateOriginNormalizesInput() {
        #expect(BlygURL.candidateOrigin(from: "sample.example")?.absoluteString == "https://sample.example/")
        #expect(BlygURL.candidateOrigin(from: " https://sample.example/notes?ref=x#top ")?.absoluteString
                == "https://sample.example/notes/")
        #expect(BlygURL.candidateOrigin(from: "https://sample.example/notes/blyg.json")?.absoluteString
                == "https://sample.example/notes/")
        #expect(BlygURL.candidateOrigin(from: "ftp://sample.example/") == nil)
        #expect(BlygURL.candidateOrigin(from: "") == nil)
    }

    @Test func pageFallsBackToTheReferenceConvention() throws {
        var doc = try decode(ItemDocument.self, Fixtures.threadDocument)
        #expect(BlygURL.page(for: doc, origin: Fixtures.origin)?.absoluteString == "https://sample.example/t/\(Fixtures.thread)/")
        doc.page = nil
        #expect(BlygURL.page(for: doc, origin: Fixtures.origin)?.absoluteString == "https://sample.example/t/\(Fixtures.thread)/")
    }

    @Test func datesParseWithAndWithoutFractions() {
        #expect(BlygDate.parse("2026-11-19T10:00:00Z") != nil)
        #expect(BlygDate.parse("2026-11-19T10:00:00.250Z") != nil)
        #expect(BlygDate.parse("yesterday") == nil)
        #expect(BlygDate.parse(nil) == nil)
    }
}

@Suite("HTML to text")
struct HTMLTextTests {
    @Test func blocksBecomeLinesAndEntitiesDecode() {
        let html = "<p>One &amp; <em>two</em></p>\n<blockquote class=\"blyg-transclusion\"><p>Quoted&#8217;s   text</p></blockquote><p>a&nbsp;b &lt;tag&gt; &#x1F600; &bogus; & done</p>"
        #expect(HTMLText.plainText(from: html) == "One & two\nQuoted’s text\na b <tag> 😀 &bogus; & done")
    }

    @Test func scriptsAndStylesAreDropped() {
        #expect(HTMLText.plainText(from: "<p>Hi</p><script>alert(1)</script><style>p{}</style><p>there</p>") == "Hi\nthere")
    }

    @Test func firstImageResolvesAgainstTheOrigin() {
        let origin = URL(string: "https://sample.example/")!
        #expect(HTMLText.firstImageURL(in: "<p><img alt='x' src='media/a.png'></p>", origin: origin)?.absoluteString
                == "https://sample.example/media/a.png")
        #expect(HTMLText.firstImageURL(in: "<p>none</p>", origin: origin) == nil)
    }

    @Test func escapeMakesTextSafeForHTML() {
        #expect(HTMLText.escape("<b>\"Tom & Jerry\"</b>") == "&lt;b&gt;&quot;Tom &amp; Jerry&quot;&lt;/b&gt;")
    }

    @Test func quotedPostsAreNotTheAuthorsWords() {
        // A thread that opens with a quote, whose quote holds an ordinary blockquote and an image.
        let html = """
        <blockquote class="blyg-transclusion blyg-partial" data-blyg-id="a"><p>Their words</p>\
        <blockquote><p>nested</p></blockquote><img src="theirs.png"></blockquote>\
        <p>My words</p><blockquote><p>my own quotation</p></blockquote>\
        <BLOCKQUOTE class='blyg-transclusion' data-blyg-id="b"><p>More of theirs</p></BLOCKQUOTE><p>end</p>
        """
        let own = HTMLText.withoutTransclusions(html)
        #expect(own.quotes == 2)
        #expect(HTMLText.plainText(from: own.html) == "My words\nmy own quotation\nend")
        #expect(HTMLText.firstImageURL(in: own.html, origin: URL(string: "https://sample.example/")!) == nil)
        #expect(HTMLText.withoutTransclusions("<p>plain</p>") == ("<p>plain</p>", 0))
        // Unclosed: everything after the quote opens is the quote's, as in a browser.
        #expect(HTMLText.withoutTransclusions("<p>a</p><blockquote class=\"blyg-transclusion\"><p>b").html == "<p>a</p>")
    }

    @Test func eachQuoteSaysWhoseWordsTheyAre() {
        let own = URL(string: "https://sample.example/")!
        let html = """
        <blockquote class="blyg-transclusion" data-blyg-id="a"><p>mine, earlier</p></blockquote>\
        <blockquote class="blyg-transclusion blyg-partial" data-blyg-id="b" data-blyg-origin="https://other.example/blyg/">\
        <p>theirs</p></blockquote><blockquote><p>no source</p></blockquote>
        """
        var asked: [String] = []
        let out = QuoteSources.annotate(html, ownOrigin: own) { origin, id in
            asked.append("\(origin.absoluteString) \(id)")
            return .init(title: id == "a" ? "Sample <Notes>" : "Other", page: URL(string: "\(origin.absoluteString)f/\(id)/"))
        }
        #expect(asked == ["https://sample.example/ a", "https://other.example/blyg/ b"])
        #expect(out.contains("</blockquote><p class=\"quote-source\">From <a href=\"https://sample.example/f/a/\">Sample &lt;Notes&gt;</a></p>"))
        #expect(out.contains("<p class=\"quote-source\">Part of a post from <a href=\"https://other.example/blyg/f/b/\">Other</a></p>"))
        #expect(out.components(separatedBy: "quote-source").count == 3) // the plain blockquote gets none
        #expect(QuoteSources.annotate("<p>x</p>", ownOrigin: own) { _, _ in .init(title: "") } == "<p>x</p>")
    }

    @Test func aTimelineRowShowsOnlyTheThreadsOwnWords() throws {
        let doc = try decode(ItemDocument.self, Fixtures.threadDocument)
        var blyg = SavedBlyg(origin: URL(string: "https://sample.example/")!, manifest: Manifest(blyg: "0.4"), addedAt: .now)
        blyg.items[doc.id] = SavedItem(id: doc.id, kind: doc.kind, version: doc.version, versionSeenAt: .now, document: doc)
        let row = try #require(Library(blygs: [blyg]).timeline().first)
        #expect(row.excerpt == "Two notes, one thought.\nBoth are about pace.")
        #expect(row.quoteCount == 1)
    }
}

@Suite("Themes")
struct ThemeTests {
    @Test func studioUsesStudiosSerifAndPencilBlue() {
        let css = Theme(appearance: .studio).css
        #expect(css.contains("\"Iowan Old Style\""))
        #expect(css.contains("--pencil: #23608c"))
        #expect(css.contains("--pencil: #8cc0e4")) // dark
    }

    @Test func systemUsesSanFranciscoOnly() {
        let css = Theme(appearance: .system).css
        #expect(!css.contains("Iowan"))
        #expect(css.contains("font-family: -apple-system, sans-serif; line-height: 1.45"))
    }

    @Test func postPageEscapesWhatTheAppAddsAndKeepsTheBlygsHTML() throws {
        var document = try decode(ItemDocument.self, Fixtures.fragmentEditedDocument)
        document.author = Author(name: "<b>Sam</b>")
        document.changelog[1].note = "fixed <script>"
        let entry = TimelineEntry(origin: Fixtures.origin, blygTitle: "Notes & <Things>", document: document,
                                  sortDate: .now, excerpt: "", imageURL: nil)
        let html = PostPage.html(for: entry, pageURL: URL(string: "https://sample.example/f/x/"), theme: Theme(appearance: .studio))
        #expect(html.contains("Notes &amp; &lt;Things&gt;"))
        #expect(html.contains("&lt;b&gt;Sam&lt;/b&gt;"))
        #expect(html.contains("<em>fixed &lt;script&gt;</em>"))
        #expect(html.contains("<a href=\"https://example.org/print\">print on demand</a>")) // the post's own HTML, untouched
        #expect(html.contains("Version 2 of 2"))
        #expect(html.contains("v1 · ") && html.contains("· pinned"))
        #expect(html.contains("script-src 'none'"))
    }
}
