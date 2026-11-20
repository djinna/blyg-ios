import Foundation
import Testing
@testable import Blyg

@Suite("Resolution (§12.1)")
struct ResolverTests {
    @Test func directProbeFindsTheManifest() async throws {
        let resolved = try await Resolver(fetcher: FakeFetcher.sample()).resolve("sample.example")
        #expect(resolved.origin == Fixtures.origin)
        #expect(resolved.manifest.title == "Sample Notes")
    }

    @Test func aPostLinkFallsBackToTheConventionalRootMount() async throws {
        let fetcher = FakeFetcher.sample()
        let resolved = try await Resolver(fetcher: fetcher).resolve("https://sample.example/f/\(Fixtures.fragmentEdited)/")
        #expect(resolved.origin == Fixtures.origin)
        #expect(fetcher.requestCount <= Resolver.maxFetches)
    }

    @Test func aFeedURLUpgradesThroughBlygManifest() async throws {
        let fetcher = FakeFetcher([
            "https://feeds.example/sample.xml": .init(body: Fixtures.feed),
            "https://sample.example/blyg.json": .init(body: Fixtures.manifest),
        ])
        let resolved = try await Resolver(fetcher: fetcher).resolve("https://feeds.example/sample.xml")
        #expect(resolved.origin == Fixtures.origin)
    }

    @Test func anHTMLPageWithRelBlygResolves() async throws {
        let fetcher = FakeFetcher([
            "https://www.example.com/about": .init(body: #"<html><head><link href="/notes/blyg.json" rel="blyg"></head></html>"#),
            "https://www.example.com/notes/blyg.json": .init(body: Fixtures.manifest),
        ])
        let resolved = try await Resolver(fetcher: fetcher).resolve("www.example.com/about")
        #expect(resolved.origin.absoluteString == "https://www.example.com/notes/")
    }

    @Test func identityFollowsRedirectsNotTheSiteKey() async throws {
        let fetcher = FakeFetcher([
            "https://old.example/blyg.json": .init(body: Fixtures.manifest, finalURL: "https://new.example/b/blyg.json"),
        ])
        let resolved = try await Resolver(fetcher: fetcher).resolve("old.example")
        #expect(resolved.origin.absoluteString == "https://new.example/b/")
    }

    @Test func failureReportsTheURLsTriedWithinTheBound() async throws {
        let fetcher = FakeFetcher()
        await #expect {
            try await Resolver(fetcher: fetcher).resolve("https://nothing.example/a/b")
        } throws: { error in
            guard case Resolver.Failure.notFound(let tried) = error else { return false }
            return tried.map(\.absoluteString) == [
                "https://nothing.example/a/b/blyg.json",
                "https://nothing.example/a/b",
                "https://nothing.example/blyg/blyg.json",
                "https://nothing.example/blyg.json",
            ]
        }
        #expect(fetcher.requestCount <= Resolver.maxFetches)
    }

    @Test func garbageInputIsNotAURL() async {
        await #expect(throws: Resolver.Failure.notAURL) { try await Resolver(fetcher: FakeFetcher()).resolve("   ") }
    }
}
