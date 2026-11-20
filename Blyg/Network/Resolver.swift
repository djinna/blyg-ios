import Foundation

/// Turns a URL someone typed or shared into a blyg (spec §12.1, steps 1–5).
/// Steps 6 (plain RSS feeds) and 7 (hopper feeds) aren't supported yet: they fail with the trail of URLs tried.
nonisolated struct Resolver: Sendable {
    let fetcher: any Fetching
    /// §12: resolution is bounded at six fetches.
    static let maxFetches = 6

    struct Resolved: Sendable, Equatable {
        var origin: URL
        var manifest: Manifest
    }

    enum Failure: Error, Equatable {
        case notAURL
        case notFound(tried: [URL])
    }

    func resolve(_ input: String) async throws -> Resolved {
        guard let candidate = BlygURL.candidateOrigin(from: input) else { throw Failure.notAURL }
        var tried: [URL] = []

        func probeManifest(_ url: URL) async -> Resolved? {
            guard tried.count < Self.maxFetches, !tried.contains(url) else { return nil }
            tried.append(url)
            guard let result = try? await fetcher.get(url), result.isOK,
                  let manifest = try? JSONDecoder().decode(Manifest.self, from: result.data),
                  let origin = BlygURL.identityOrigin(manifestURL: result.finalURL) else { return nil }
            return Resolved(origin: origin, manifest: manifest)
        }

        // Step 2: direct probe.
        if let found = await probeManifest(BlygURL.manifest(origin: candidate)) { return found }

        // Steps 3 and 4: what does the input URL itself serve? A feed with <blyg:manifest>, or HTML with <link rel="blyg">.
        let inputURL = Self.inputURL(input) ?? candidate
        if tried.count < Self.maxFetches, !tried.contains(inputURL) {
            tried.append(inputURL)
            if let result = try? await fetcher.get(inputURL), result.isOK {
                if let manifestRef = FeedManifestLink.find(in: result.data),
                   let url = BlygURL.resolve(manifestRef, against: result.finalURL),
                   let found = await probeManifest(url) {
                    return found
                }
                if let html = String(data: result.data, encoding: .utf8), let href = Self.relBlyg(in: html),
                   let url = BlygURL.resolve(HTMLText.decodeEntities(href), against: result.finalURL),
                   let found = await probeManifest(url) {
                    return found
                }
            }
        }

        // Step 5: conventional mounts at the host root.
        if var root = URLComponents(url: candidate, resolvingAgainstBaseURL: false) {
            for path in ["/blyg/blyg.json", "/blyg.json"] {
                root.path = path
                if let url = root.url, let found = await probeManifest(url) { return found }
            }
        }
        throw Failure.notFound(tried: tried)
    }

    /// The input as typed (scheme added, fragment dropped), for steps 3–4.
    static func inputURL(_ input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") { text = "https://" + text }
        guard var parts = URLComponents(string: text), parts.host != nil else { return nil }
        parts.fragment = nil
        if parts.path.isEmpty { parts.path = "/" }
        return parts.url
    }

    /// `<link rel="blyg" href="…">` in an HTML page (§12.1 step 4).
    static func relBlyg(in html: String) -> String? {
        var search = html[...]
        while let start = search.range(of: "<link", options: .caseInsensitive) {
            guard let end = search[start.upperBound...].firstIndex(of: ">") else { return nil }
            let tag = search[start.upperBound..<end]
            if let rel = HTMLText.attribute("rel", in: tag),
               rel.lowercased().split(separator: " ").contains("blyg"),
               let href = HTMLText.attribute("href", in: tag) {
                return href
            }
            search = search[end...]
        }
        return nil
    }
}

/// Finds `<blyg:manifest>` in an RSS feed (§7), by namespace, not by prefix.
nonisolated final class FeedManifestLink: NSObject, XMLParserDelegate {
    static let namespace = "https://blygger.org/ns/0.1"
    private var inManifest = false
    private var text = ""
    private(set) var value: String?

    static func find(in data: Data) -> String? {
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        let delegate = FeedManifestLink()
        parser.delegate = delegate
        parser.parse()
        return delegate.value
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if namespaceURI == Self.namespace, elementName == "manifest" { inManifest = true; text = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inManifest { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if inManifest, namespaceURI == Self.namespace, elementName == "manifest" {
            inManifest = false
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { value = trimmed; parser.abortParsing() }
        }
    }
}
