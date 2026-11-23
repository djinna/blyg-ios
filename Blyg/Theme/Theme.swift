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

/// One colour scheme for the Studio look: the page, its text, and the pencil for links and marks.
nonisolated struct Palette: Sendable, Equatable {
    let page, ink, soft, rule, sunk, pencil, onPencil: UInt32
}

/// Colour themes, from the icon palettes (2026-11-23). Each has a light and a dark palette; Paper and Ink
/// ignore the phone's setting and stay light or dark. Stored as `colorTheme` in UserDefaults (CA92.1).
/// Every text colour passes 4.5:1 on its page and on `sunk` (BlygTests' "Themes" suite checks it).
nonisolated enum ColorTheme: String, CaseIterable, Identifiable, Sendable {
    case pencilBlue, pigletPink, moss, butter, paper, ink

    var id: String { rawValue }
    var title: String {
        switch self {
        case .pencilBlue: "Pencil blue"
        case .pigletPink: "Piglet pink"
        case .moss: "Moss"
        case .butter: "Butter"
        case .paper: "Paper"
        case .ink: "Ink"
        }
    }
    var summary: String {
        switch self {
        case .pencilBlue: "Studio's blue. Follows the phone's light or dark setting."
        case .pigletPink: "Warm pinks. Follows the phone's setting."
        case .moss: "Soft greens. Follows the phone's setting."
        case .butter: "Cream and gold, easy on the eyes. Follows the phone's setting."
        case .paper: "Always light, whatever the phone's setting."
        case .ink: "Always dark, whatever the phone's setting."
        }
    }
    /// Paper and Ink force the colour scheme; the rest follow the phone.
    var scheme: ColorScheme? {
        switch self {
        case .paper: .light
        case .ink: .dark
        default: nil
        }
    }

    var light: Palette {
        switch self {
        case .pencilBlue: Palette(page: 0xFAFBFB, ink: 0x1B2426, soft: 0x5C686B, rule: 0xDDE3E5, sunk: 0xEEF1F3, pencil: 0x23608C, onPencil: 0xFFFFFF)
        case .pigletPink: Palette(page: 0xFDF7F8, ink: 0x2A1E21, soft: 0x6B5A5F, rule: 0xEFDCE0, sunk: 0xF8EAED, pencil: 0xA3324F, onPencil: 0xFFFFFF)
        case .moss: Palette(page: 0xF7FAF5, ink: 0x1D261C, soft: 0x586555, rule: 0xDCE5D8, sunk: 0xEDF3EA, pencil: 0x3A6B3F, onPencil: 0xFFFFFF)
        case .butter: Palette(page: 0xFFFBEA, ink: 0x2A2618, soft: 0x655E45, rule: 0xEDE4C2, sunk: 0xF7EFCF, pencil: 0x7D5A00, onPencil: 0xFFFFFF)
        case .paper: Palette(page: 0xFBFAF6, ink: 0x1B2426, soft: 0x5C686B, rule: 0xE4E1D8, sunk: 0xF2F0E8, pencil: 0x23608C, onPencil: 0xFFFFFF)
        case .ink: dark
        }
    }
    var dark: Palette {
        switch self {
        case .pencilBlue: Palette(page: 0x14191A, ink: 0xE3E7E7, soft: 0x95A2A5, rule: 0x2B3436, sunk: 0x1D2426, pencil: 0x8CC0E4, onPencil: 0x14191A)
        case .pigletPink: Palette(page: 0x1A1416, ink: 0xF1E6E8, soft: 0xAB989D, rule: 0x3A2C30, sunk: 0x251C1F, pencil: 0xF4A7B6, onPencil: 0x1A1416)
        case .moss: Palette(page: 0x141A14, ink: 0xE4EBE2, soft: 0x98A595, rule: 0x2B352A, sunk: 0x1D251C, pencil: 0xA8D3A0, onPencil: 0x141A14)
        case .butter: Palette(page: 0x1A1810, ink: 0xF2ECD6, soft: 0xA9A285, rule: 0x37321F, sunk: 0x24211A, pencil: 0xF3E3A6, onPencil: 0x1A1810)
        case .paper: light
        case .ink: Palette(page: 0x111819, ink: 0xE3E7E7, soft: 0x95A2A5, rule: 0x2B3436, sunk: 0x1C2324, pencil: 0x9CCBE8, onPencil: 0x111819)
        }
    }

    static let storageKey = "colorTheme"
}

nonisolated struct Theme: Sendable {
    let appearance: Appearance
    var colors: ColorTheme = .pencilBlue

    // MARK: Type

    /// Post text: Studio's serif (Iowan Old Style ships with iOS), or San Francisco. Scales with Dynamic Type.
    func prose(_ style: Font.TextStyle = .body) -> Font {
        switch appearance {
        case .studio: .custom("Iowan Old Style", size: Self.size(style), relativeTo: style)
        case .system: .system(style)
        }
    }

    /// The masthead ("Blyglet"): display size, regular weight in the serif, bold in San Francisco.
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

    // The Studio look takes every colour from the theme. The System look keeps iOS's own colours and takes
    // only the pencil from the theme (iOS's link blue for the default theme).
    var page: Color { pick(\.page, system: Color(.systemBackground)) }
    var ink: Color { pick(\.ink, system: Color(.label)) }
    var soft: Color { pick(\.soft, system: Color(.secondaryLabel)) }
    var rule: Color { pick(\.rule, system: Color(.separator)) }
    var sunk: Color { pick(\.sunk, system: Color(.secondarySystemBackground)) }
    /// Links and editorial marks.
    var pencil: Color {
        appearance == .system && colors == .pencilBlue ? Color(.link) : dynamic(\.pencil)
    }
    /// Text on a pencil-coloured button. In dark palettes the pencil is light, so white text on it fails
    /// contrast: each palette names its own (the dark page colour there, about 9:1 on #8CC0E4).
    var onPencil: Color { dynamic(\.onPencil) }

    private func pick(_ key: KeyPath<Palette, UInt32>, system: Color) -> Color {
        appearance == .studio ? dynamic(key) : system
    }

    private func dynamic(_ key: KeyPath<Palette, UInt32>) -> Color {
        let (light, dark) = (colors.light[keyPath: key], colors.dark[keyPath: key])
        return Color(UIColor { traits in UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light) })
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
        typealias Colors = (page: String, ink: String, soft: String, rule: String, pencil: String, sunk: String)
        func css(_ p: Palette) -> Colors {
            func h(_ v: UInt32) -> String { "#" + String(format: "%06x", v) }
            return (h(p.page), h(p.ink), h(p.soft), h(p.rule), h(p.pencil), h(p.sunk))
        }
        let fonts: (prose: String, apparatus: String)
        var light: Colors, dark: Colors
        switch appearance {
        case .studio:
            fonts = ("\"Iowan Old Style\", \"Palatino Linotype\", Palatino, Charter, Georgia, serif", "-apple-system, sans-serif")
            (light, dark) = (css(colors.light), css(colors.dark))
        case .system:
            fonts = ("-apple-system, sans-serif", "-apple-system, sans-serif")
            light = ("#ffffff", "#000000", "#6b6b70", "#d1d1d6", "#0a66d6", "#f2f2f7")
            dark = ("#000000", "#ffffff", "#98989f", "#38383a", "#4ea1ff", "#1c1c1e")
            if colors != .pencilBlue { (light.pencil, dark.pencil) = (css(colors.light).pencil, css(colors.dark).pencil) }
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
        .linked { margin: 1.6em 0 0; }
        .linked-label { font: -apple-system-caption1; font-family: \(fonts.apparatus); color: var(--pencil); text-transform: uppercase; letter-spacing: 0.06em; margin: 0 0 0.5em; }
        .card { display: block; color: var(--ink); text-decoration: none; border: 1px solid var(--rule); border-left: 2px solid var(--pencil);
          border-radius: 2px; padding: 0.6em 0.8em; margin: 0 0 0.7em; }
        .card-meta { display: block; font: -apple-system-footnote; font-family: \(fonts.apparatus); color: var(--soft); }
        .card-text { display: -webkit-box; -webkit-box-orient: vertical; -webkit-line-clamp: 5; overflow: hidden; white-space: pre-line; margin-top: 0.25em; }
        .card-text.gone { font-style: italic; color: var(--soft); }
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
