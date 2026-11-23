import Foundation
import SwiftUI
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
        #expect(row.excerpt.hasPrefix("Two notes, one thought.\nBoth are about pace.\nElsewhere someone"))
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

    /// WCAG contrast ratio between two sRGB colours.
    static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        func luminance(_ v: UInt32) -> Double {
            let c = [16, 8, 0].map { Double((v >> UInt32($0)) & 0xFF) / 255 }
                .map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
        }
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    @Test(arguments: ColorTheme.allCases)
    func everyThemesTextPassesAA(_ colors: ColorTheme) {
        for p in [colors.light, colors.dark] {
            for (name, text) in [("ink", p.ink), ("soft", p.soft), ("pencil", p.pencil)] {
                for ground in [p.page, p.sunk] {
                    #expect(Self.contrast(text, ground) >= 4.5, "\(colors) \(name) on \(String(ground, radix: 16))")
                }
            }
            #expect(Self.contrast(p.onPencil, p.pencil) >= 4.5, "\(colors) text on a pencil button")
        }
        // The System look puts the theme's pencil on iOS's own backgrounds, in the modes the theme can show
        // (Paper is always light and Ink always dark).
        if colors.scheme != .dark {
            for ground: UInt32 in [0xFFFFFF, 0xF2F2F7] { #expect(Self.contrast(colors.light.pencil, ground) >= 4.5, "\(colors) System light") }
        }
        if colors.scheme != .light {
            for ground: UInt32 in [0x000000, 0x1C1C1E] { #expect(Self.contrast(colors.dark.pencil, ground) >= 4.5, "\(colors) System dark") }
        }
    }

    @Test func aThemeColoursThePostPage() {
        let css = Theme(appearance: .studio, colors: .moss).css
        #expect(css.contains("--pencil: #3a6b3f"))
        #expect(css.contains("--page: #141a14")) // dark
        #expect(Theme(appearance: .system, colors: .moss).css.contains("--pencil: #3a6b3f"))
        #expect(Theme(appearance: .system).css.contains("--pencil: #0a66d6")) // the default keeps iOS's blue
    }

    /// Every alternate icon the picker offers is in the built app's Info.plist (the asset catalog puts it there).
    @Test func everyIconChoiceIsInTheApp() throws {
        let icons = try #require(Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any])
        let alternates = try #require(icons["CFBundleAlternateIcons"] as? [String: Any])
        for choice in AppIconChoice.allCases {
            guard let name = choice.iconName else { continue }
            #expect(alternates[name] != nil, "\(name) missing from CFBundleAlternateIcons")
        }
        #expect(alternates.count == AppIconChoice.allCases.count - 1)
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

@Suite("Quote cards") @MainActor
struct LinkedPostTests {
    let origin = Fixtures.origin

    @Test func onlyLinksShapedLikeBlygPostsAreCandidates() throws {
        let thread = try decode(ItemDocument.self, Fixtures.threadDocument)
        let found = LinkedPosts.candidates(in: thread, origin: origin)
        // Not example.org (an ordinary site), not the quoted post's own link, not the post it replies to.
        #expect(found.map(\.id) == [Fixtures.elsewherePost, Fixtures.withdrawn])
        #expect(found.first?.origin == Fixtures.elsewhereOrigin)
    }

    @Test func linksEntriesAreScopedToTheirOrigin() {
        let doc = ItemDocument(id: "me", kind: "fragment", version: 1, created: "", updated: "",
                               contentHTML: "<p><a href=\"f/me/\">myself</a></p>",
                               links: [.init(id: "x1", origin: nil), .init(id: "x2", origin: "https://other.example/")])
        let found = LinkedPosts.candidates(in: doc, origin: origin)
        #expect(found.map { "\($0.origin.absoluteString)\($0.id)" } == ["https://sample.example/x1", "https://other.example/x2"])
    }

    @Test func itemPagesAreRecognisedAtAnyMount() throws {
        let (mount, id) = try #require(LinkedPosts.itemPage(URL(string: "https://host.example/a/b/t/abc123/?x=1#y")!))
        #expect(mount.absoluteString == "https://host.example/a/b/")
        #expect(id == "abc123")
        #expect(LinkedPosts.itemPage(URL(string: "https://host.example/about/")!) == nil)
        #expect(LinkedPosts.itemPage(URL(string: "mailto:f/x/")!) == nil)
        #expect(LinkedPosts.samePage(URL(string: "https://HOST.example/f/a")!, URL(string: "https://host.example/f/a/#top")!))
    }

    @Test func aCardFromABlygYouDontFollowTakesTwoFetches() async throws {
        let fetcher = FakeFetcher.sample()
        let card = try #require(await LinkedPostLoader(fetcher: fetcher).load(
            .init(origin: Fixtures.elsewhereOrigin, id: Fixtures.elsewherePost,
                  href: URL(string: "https://elsewhere.example/blyg/f/\(Fixtures.elsewherePost)/"))))
        #expect(card.blygTitle == "Elsewhere Journal")
        #expect(card.author == "Eli Elsewhere")
        #expect(card.excerpt == "Slow is a feature. A feed you can finish is a feed you can trust.")
        #expect(card.link.absoluteString == "https://elsewhere.example/blyg/f/\(Fixtures.elsewherePost)/")
        #expect(fetcher.requested.count == 2)
    }

    @Test func aGuessedAddressMustBeThePostsRealPage() async {
        let fetcher = FakeFetcher.sample()
        // The id is real, but the post's page is f/…, not t/…: not believed.
        let card = await LinkedPostLoader(fetcher: fetcher).load(
            .init(origin: Fixtures.elsewhereOrigin, id: Fixtures.elsewherePost,
                  href: URL(string: "https://elsewhere.example/blyg/t/\(Fixtures.elsewherePost)/")))
        #expect(card == nil)
        #expect(await LinkedPostLoader(fetcher: fetcher).load(.init(origin: URL(string: "https://nothing.example/")!, id: "x")) == nil)
    }

    @Test func savedPostsNeedNoFetchAndWithdrawnOnesSaySo() async throws {
        let fetcher = FakeFetcher.sample()
        let model = LibraryModel(store: nil, fetcher: fetcher)
        try await model.add("sample.example")
        let thread = try #require(model.timeline.first { $0.document.id == Fixtures.thread })
        let saved = model.savedLinkedPosts(for: thread.document, origin: origin)
        #expect(saved.map(\.itemID) == [Fixtures.withdrawn])
        #expect(saved.first?.withdrawn == true)
        let before = fetcher.requestCount
        let all = await model.linkedPosts(for: thread.document, origin: origin)
        #expect(all.map(\.itemID) == [Fixtures.elsewherePost, Fixtures.withdrawn])
        #expect(fetcher.requestCount == before + 2)
        _ = await model.linkedPosts(for: thread.document, origin: origin) // cached for the session
        #expect(fetcher.requestCount == before + 2)
        let html = PostPage.cards(all)
        #expect(html.contains("Elsewhere Journal · Eli Elsewhere"))
        #expect(html.contains("Withdrawn by its author."))
        #expect(!html.contains("<img"))
    }

    @Test func aLinkToAFollowedPostOpensInTheApp() async throws {
        let model = LibraryModel(store: nil, fetcher: FakeFetcher.sample())
        try await model.add("sample.example")
        #expect(model.entry(forPage: URL(string: "https://sample.example/f/\(Fixtures.fragmentPlain)/")!)?.document.id == Fixtures.fragmentPlain)
        #expect(model.entry(forPage: URL(string: "https://elsewhere.example/blyg/f/\(Fixtures.elsewherePost)/")!) == nil)
    }
}
