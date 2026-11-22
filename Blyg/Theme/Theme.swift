import SwiftUI
import UIKit

/// The app's two looks. Same layout; only type and colour change.
/// Studio follows Blygger Studio's own stylesheet (studio 0.65.0 `style.css`): serif prose, a small sans
/// "apparatus" for metadata, and an editor's blue pencil for every editorial mark. System is San Francisco
/// and iOS's own colours. Chosen in Settings (Your blygs → Appearance); stored as `appearance` in UserDefaults.
nonisolated enum Appearance: String, CaseIterable, Identifiable, Sendable {
    case studio, system

    var id: String { rawValue }
    var title: String { self == .studio ? "Studio" : "System" }
    var summary: String {
        self == .studio
            ? "Blygger Studio's look: a serif for posts, blue for links and marks."
            : "iPhone's own look: San Francisco and system colours."
    }

    static let storageKey = "appearance"
}

nonisolated struct Theme: Sendable {
    let appearance: Appearance

    // MARK: Type

    /// Post text: Studio's serif (Iowan Old Style ships with iOS), or San Francisco. Scales with Dynamic Type.
    func prose(_ style: Font.TextStyle = .body) -> Font {
        switch appearance {
        case .studio: .custom("Iowan Old Style", size: Self.size(style), relativeTo: style)
        case .system: .system(style)
        }
    }

    /// The masthead ("Blyg"): display size, regular weight in the serif, bold in San Francisco.
    var masthead: Font {
        switch appearance {
        case .studio: .custom("Iowan Old Style", size: 34, relativeTo: .largeTitle)
        case .system: .largeTitle.bold()
        }
    }

    /// Metadata about a post rather than the post: one face, one size, one colour in both looks.
    var apparatus: Font { .footnote }
    /// Small capitals-style labels (THREAD, LINK, PHOTO).
    var label: Font { .caption.weight(.medium) }

    /// Studio's prose is 1.65 line height; San Francisco reads well a little tighter.
    var proseLineSpacing: CGFloat { appearance == .studio ? 6 : 3 }

    // MARK: Colour

    var page: Color { pick(studio: (0xFAFBFB, 0x14191A), system: Color(.systemBackground)) }
    var ink: Color { pick(studio: (0x1B2426, 0xE3E7E7), system: Color(.label)) }
    var soft: Color { pick(studio: (0x5C686B, 0x95A2A5), system: Color(.secondaryLabel)) }
    var rule: Color { pick(studio: (0xDDE3E5, 0x2B3436), system: Color(.separator)) }
    var sunk: Color { pick(studio: (0xEEF1F3, 0x1D2426), system: Color(.secondarySystemBackground)) }
    /// Links and editorial marks. In dark mode Studio's pencil is the icon's light blue.
    var pencil: Color { pick(studio: (0x23608C, 0x8CC0E4), system: Color(.link)) }
    /// Text on a pencil-blue button. In dark mode the blue is light, so white text on it fails contrast:
    /// use the dark page colour there instead (about 9:1 on #8CC0E4).
    var onPencil: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: 0x14191A) : .white
        })
    }

    private func pick(studio: (UInt32, UInt32), system: Color) -> Color {
        guard appearance == .studio else { return system }
        return Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? studio.1 : studio.0)
        })
    }

    private static func size(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        @unknown default: 17
        }
    }

    // MARK: Post page

    /// CSS for the post page's web view. Fonts follow Dynamic Type through `-apple-system-body`.
    var css: String {
        let fonts: (prose: String, apparatus: String)
        let light: (page: String, ink: String, soft: String, rule: String, pencil: String, sunk: String)
        let dark: (page: String, ink: String, soft: String, rule: String, pencil: String, sunk: String)
        switch appearance {
        case .studio:
            fonts = ("\"Iowan Old Style\", \"Palatino Linotype\", Palatino, Charter, Georgia, serif", "-apple-system, sans-serif")
            light = ("#fafbfb", "#1b2426", "#5c686b", "#dde3e5", "#23608c", "#eef1f3")
            dark = ("#14191a", "#e3e7e7", "#95a2a5", "#2b3436", "#8cc0e4", "#1d2426")
        case .system:
            fonts = ("-apple-system, sans-serif", "-apple-system, sans-serif")
            light = ("#ffffff", "#000000", "#6b6b70", "#d1d1d6", "#0a66d6", "#f2f2f7")
            dark = ("#000000", "#ffffff", "#98989f", "#38383a", "#4ea1ff", "#1c1c1e")
        }
        let lineHeight = appearance == .studio ? "1.65" : "1.45"
        return """
        :root { color-scheme: light dark;
          --page: \(light.page); --ink: \(light.ink); --soft: \(light.soft); --rule: \(light.rule); --pencil: \(light.pencil); --sunk: \(light.sunk); }
        @media (prefers-color-scheme: dark) { :root {
          --page: \(dark.page); --ink: \(dark.ink); --soft: \(dark.soft); --rule: \(dark.rule); --pencil: \(dark.pencil); --sunk: \(dark.sunk); } }
        html { -webkit-text-size-adjust: 100%; }
        body { font: -apple-system-body; font-family: \(fonts.prose); line-height: \(lineHeight);
          margin: 12px 24px 48px; background: var(--page); color: var(--ink); overflow-wrap: anywhere; }
        a { color: var(--pencil); text-underline-offset: 0.15em; }
        img, video { max-width: 100%; height: auto; border-radius: 2px; }
        pre, code { font-family: ui-monospace, monospace; font-size: 0.88em; }
        pre { white-space: pre-wrap; padding: 10px 12px; border-radius: 4px; background: var(--sunk); }
        blockquote { margin: 1em 0; padding: 0.1em 0 0.1em 1em; border-left: 2px solid var(--rule); }
        blockquote.blyg-transclusion { border-left-color: var(--pencil); }
        .quote-source { font: -apple-system-footnote; font-family: \(fonts.apparatus); color: var(--soft); margin: -0.5em 0 1.2em 1.1em; }
        .quote-source a { color: var(--soft); }
        table { border-collapse: collapse; display: block; overflow-x: auto; }
        td, th { border: 1px solid var(--rule); padding: 4px 8px; }
        hr { border: none; border-top: 1px solid var(--rule); }
        .apparatus, .history, .permalink { font: -apple-system-footnote; font-family: \(fonts.apparatus); color: var(--soft); }
        .apparatus p { margin: 0; }
        .apparatus .blyg { color: var(--ink); }
        .apparatus { margin-bottom: 1.4em; }
        .apparatus .replying { margin-top: 0.5em; font-style: italic; }
        .apparatus .cited { margin: 0.2em 0 0; padding-left: 0.7em; border-left: 2px solid var(--pencil); }
        .kind { color: var(--pencil); text-transform: uppercase; letter-spacing: 0.06em; font-size: 0.92em; }
        .history { margin-top: 1.6em; padding-top: 1em; border-top: 1px solid var(--rule); }
        .history p { margin: 0; }
        .history .note, .history em { font-style: italic; }
        .history ol { list-style: none; padding: 0; margin: 0.8em 0 0; }
        .history li { margin: 0 0 0.2em; }
        .permalink { margin-top: 1.2em; }
        .permalink a { color: var(--soft); text-decoration: none; border-bottom: 1px solid var(--rule); }
        """
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme(appearance: .studio)
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

extension UIColor {
    nonisolated convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
