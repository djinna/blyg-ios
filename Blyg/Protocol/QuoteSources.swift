import Foundation

/// Says whose words a baked quote is. A thread's `content_html` carries other people's posts as
/// `blockquote.blyg-transclusion` with `data-blyg-id` and, for another blyg, `data-blyg-origin` (§10.1–§10.3).
/// Readers display that baked HTML and never re-fetch it (§10.3); this only adds a line under each quote naming
/// its source and linking to it, as Studio's own item page does.
nonisolated enum QuoteSources {
    struct Source: Sendable, Equatable {
        var title: String
        var page: URL?
    }

    /// `describe` names a quoted item, given its origin (already scoped: the document's own when absent, §10.3) and id.
    static func annotate(_ html: String, ownOrigin: URL, describe: (URL, String) -> Source) -> String {
        guard html.range(of: "blyg-transclusion") != nil,
              let regex = try? NSRegularExpression(pattern: "<blockquote\\b[^>]*>|</blockquote\\s*>", options: [.caseInsensitive])
        else { return html }
        struct Layer { var quote: Bool; var id: String?; var origin: URL; var partial: Bool }
        let text = html as NSString
        var out = ""
        var copied = 0
        var stack: [Layer] = []
        for match in regex.matches(in: html, range: NSRange(location: 0, length: text.length)) {
            let tag = text.substring(with: match.range)
            if tag.hasPrefix("</") {
                guard let layer = stack.popLast() else { continue }
                guard layer.quote, let id = layer.id, !id.isEmpty else { continue }
                let end = match.range.location + match.range.length
                out += text.substring(with: NSRange(location: copied, length: end - copied))
                copied = end
                out += line(for: describe(layer.origin, id), partial: layer.partial)
            } else {
                let attributes = Substring(tag.dropFirst("<blockquote".count))
                let classes = HTMLText.attribute("class", in: attributes)?.split(separator: " ") ?? []
                let enclosing = stack.last(where: \.quote)?.origin ?? ownOrigin
                let origin = HTMLText.attribute("data-blyg-origin", in: attributes)
                    .flatMap { BlygURL.resolve(HTMLText.decodeEntities($0), against: ownOrigin) } ?? enclosing
                stack.append(Layer(quote: classes.contains("blyg-transclusion"),
                                   id: HTMLText.attribute("data-blyg-id", in: attributes).map(HTMLText.decodeEntities),
                                   origin: origin, partial: classes.contains("blyg-partial")))
            }
        }
        out += text.substring(from: copied)
        return out
    }

    private static func line(for source: Source, partial: Bool) -> String {
        let title = HTMLText.escape(source.title)
        let named = source.page.map { "<a href=\"\(HTMLText.escape($0.absoluteString))\">\(title)</a>" } ?? title
        return "<p class=\"quote-source\">\(partial ? "Part of a post from" : "From") \(named)</p>"
    }
}
