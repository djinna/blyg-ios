import Foundation

/// Plain text and first image from an item's `content_html`, for timeline rows.
/// A small scanner rather than an HTML parser: rows only need readable text.
nonisolated enum HTMLText {
    private static let blockTags: Set<String> = [
        "p", "br", "div", "li", "ul", "ol", "blockquote", "pre", "h1", "h2", "h3", "h4", "h5", "h6",
        "hr", "tr", "table", "figure", "figcaption", "section", "article", "math",
    ]
    private static let skippedTags: Set<String> = ["script", "style", "template", "annotation"]

    static func plainText(from html: String) -> String {
        var out = ""
        var index = html.startIndex
        while index < html.endIndex {
            let char = html[index]
            guard char == "<", let close = html[index...].firstIndex(of: ">") else {
                out.append(char)
                index = html.index(after: index)
                continue
            }
            let tag = html[html.index(after: index)..<close]
            let name = tagName(tag)
            index = html.index(after: close)
            if skippedTags.contains(name), !tag.hasPrefix("/") {
                // Skip to the matching close tag.
                if let end = html.range(of: "</\(name)", options: .caseInsensitive, range: index..<html.endIndex),
                   let gt = html[end.upperBound...].firstIndex(of: ">") {
                    index = html.index(after: gt)
                }
                continue
            }
            if blockTags.contains(name) { out.append("\n") }
        }
        let decoded = decodeEntities(out)
        let lines = decoded.split(separator: "\n", omittingEmptySubsequences: true).map { line in
            line.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\r" || $0 == "\u{00A0}" }).joined(separator: " ")
        }
        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// A thread's own words: its HTML without the other people's writing baked into it as
    /// `blockquote.blyg-transclusion` (§10), plus how many quotes were taken out. Nesting-aware, so a
    /// transclusion that itself contains blockquotes is removed whole. Studio does the same for every
    /// one-line summary (its `authorOwnHtml`), so a thread that opens with a quote isn't shown as the quoted words.
    static func withoutTransclusions(_ html: String) -> (html: String, quotes: Int) {
        guard html.range(of: "blyg-transclusion") != nil,
              let regex = try? NSRegularExpression(pattern: "<blockquote\\b[^>]*>|</blockquote\\s*>", options: [.caseInsensitive])
        else { return (html, 0) }
        let text = html as NSString
        var out = ""
        var kept = 0 // where the next kept run starts
        var stack: [Bool] = [] // is each open blockquote a transclusion?
        var quotes = 0
        for match in regex.matches(in: html, range: NSRange(location: 0, length: text.length)) {
            let tag = text.substring(with: match.range)
            let inside = stack.contains(true)
            if tag.hasPrefix("</") {
                guard let wasQuote = stack.popLast() else { continue }
                if wasQuote, !stack.contains(true) { kept = match.range.location + match.range.length }
            } else {
                let isQuote = HTMLText.attribute("class", in: Substring(tag.dropFirst("<blockquote".count)))?
                    .split(separator: " ").contains("blyg-transclusion") ?? false
                if isQuote, !inside {
                    out += text.substring(with: NSRange(location: kept, length: match.range.location - kept))
                    quotes += 1
                }
                stack.append(isQuote)
            }
        }
        // An unclosed transclusion swallows the rest, as a browser would put the rest inside it.
        if !stack.contains(true) { out += text.substring(from: kept) }
        return (out, quotes)
    }

    /// The first `<img src>` as an absolute URL, if any.
    static func firstImageURL(in html: String, origin: URL) -> URL? {
        guard let img = html.range(of: "<img", options: .caseInsensitive),
              let end = html[img.upperBound...].firstIndex(of: ">") else { return nil }
        let tag = html[img.upperBound..<end]
        guard let src = attribute("src", in: tag) else { return nil }
        return BlygURL.resolve(decodeEntities(src), against: origin)
    }

    static func attribute(_ name: String, in tag: Substring) -> String? {
        let pattern = "(?:^|\\s)" + name + "\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let text = String(tag)
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        for group in 1...3 {
            if let r = Range(match.range(at: group), in: text) { return String(text[r]) }
        }
        return nil
    }

    private static func tagName(_ tag: Substring) -> String {
        var body = tag.drop(while: { $0 == "/" || $0 == " " })
        if body.hasPrefix("!") { return "!" }
        body = body.prefix(while: { $0.isLetter || $0.isNumber })
        return body.lowercased()
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let named: [String: String] = [
            "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
            "mdash": "—", "ndash": "–", "hellip": "…", "rsquo": "’", "lsquo": "‘", "rdquo": "”", "ldquo": "“",
        ]
        var out = ""
        var rest = Substring(text)
        while let amp = rest.firstIndex(of: "&") {
            out += rest[..<amp]
            let after = rest[rest.index(after: amp)...]
            if let semi = after.prefix(12).firstIndex(of: ";") {
                let entity = after[..<semi]
                var replacement: String?
                if entity.hasPrefix("#x") || entity.hasPrefix("#X"), let code = UInt32(entity.dropFirst(2), radix: 16) {
                    replacement = Unicode.Scalar(code).map(String.init)
                } else if entity.hasPrefix("#"), let code = UInt32(entity.dropFirst()) {
                    replacement = Unicode.Scalar(code).map(String.init)
                } else {
                    replacement = named[String(entity)]
                }
                if let replacement {
                    out += replacement
                    rest = after[after.index(after: semi)...]
                    continue
                }
            }
            out += "&"
            rest = after
        }
        out += rest
        return out
    }

    /// Escapes text for safe insertion into the post page's HTML.
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
