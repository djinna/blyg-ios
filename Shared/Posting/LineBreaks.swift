import Foundation

/// Keeps a single line break as typed. Studio's markdown (markdown-it) joins single newlines into one line,
/// which on a phone reads as a lost line break. Studio's own editor writes a hard break as a backslash at the
/// end of the line (its Shift+Enter, `format-shortcuts.ts`), so this writes the same, and only between two
/// lines of one paragraph: a backslash at the end of a block shows literally, so lists, headings, quotes'
/// edges, fences, math and tables are left alone. Studio's Edit shows the backslashes, as it would its own.
nonisolated enum LineBreaks {
    static func keep(_ text: String) -> String {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard lines.count > 1 else { return text }
        var fence: String? // "```", "~~~" or "$$" while inside one
        for i in 0..<(lines.count - 1) {
            let line = lines[i]
            if let open = fence {
                if closes(line, open) { fence = nil }
                continue
            }
            if let opened = opensFence(line) { fence = opened; continue }
            if breaks(between: line, and: lines[i + 1]) {
                lines[i] = String(line.reversed().drop(while: { $0 == " " || $0 == "\t" }).reversed()) + "\\"
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func breaks(between first: String, and second: String) -> Bool {
        var current = first, next = second
        // Two lines of the same block quote: look at what's inside the markers.
        while let a = withoutQuoteMarker(current), let b = withoutQuoteMarker(next) { current = a; next = b }
        if current.allSatisfy(\.isWhitespace) || next.allSatisfy(\.isWhitespace) { return false }
        if current.hasSuffix("\\") || current.hasSuffix("  ") { return false }
        if indent(current) >= 4 || current.contains("\t") { return false } // code, or deep list text: leave it
        if current.contains("|") || next.contains("|") { return false }    // table rows
        if matches(current, heading) || matches(current, rule) || opensFence(current) != nil { return false }
        for pattern in [listItem, heading, rule, quote] where matches(next, pattern) { return false }
        return opensFence(next) == nil
    }

    private static let listItem = #"^ {0,3}([-*+]|\d{1,9}[.)])( |$)"#
    private static let heading = #"^ {0,3}#{1,6}( |$)"#
    /// A thematic break, or a setext underline (`===`, `---`) that would make the line above a heading.
    private static let rule = #"^ {0,3}(([-*_])( *\2){2,}|=+|-+) *$"#
    private static let quote = #"^ {0,3}>"#

    private static func matches(_ line: String, _ pattern: String) -> Bool {
        line.range(of: pattern, options: .regularExpression) != nil
    }

    private static func indent(_ line: String) -> Int { line.prefix(while: { $0 == " " }).count }

    private static func withoutQuoteMarker(_ line: String) -> String? {
        guard let range = line.range(of: #"^ {0,3}> ?"#, options: .regularExpression) else { return nil }
        return String(line[range.upperBound...])
    }

    private static func opensFence(_ line: String) -> String? {
        let trimmed = line.drop(while: { $0 == " " })
        guard indent(line) <= 3 else { return nil }
        if trimmed.hasPrefix("```") { return "```" }
        if trimmed.hasPrefix("~~~") { return "~~~" }
        // Display math: "$$" opens a block unless it also closes on the same line.
        if trimmed.hasPrefix("$$") { return trimmed.dropFirst(2).contains("$$") ? nil : "$$" }
        return nil
    }

    private static func closes(_ line: String, _ fence: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return fence == "$$" ? trimmed.hasSuffix("$$") : trimmed.hasPrefix(fence)
    }
}
