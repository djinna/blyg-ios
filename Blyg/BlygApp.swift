import SwiftUI

@main
struct BlygApp: App {
    @State private var model = BlygApp.makeModel()

    var body: some Scene {
        WindowGroup {
            ThemedRoot()
                .environment(model)
        }
    }

    static func makeModel() -> LibraryModel {
        var store: LibraryStore? = LibraryStore.appSupport()
        var tokens: any TokenStore = KeychainTokenStore()
        var buildTimeline: @Sendable (Library) -> [TimelineEntry] = { $0.timeline() }
        #if DEBUG
        if LaunchFlags.has(LaunchFlags.inMemory) {
            store = nil
            tokens = MemoryTokenStore()
        }
        if LaunchFlags.has(LaunchFlags.useFixtures) {
            // The fixture blyg's posts are dated November 2026. The feed's window is measured from then (or from
            // `-feedNow`), so the UI tests and screenshots don't change as the calendar moves on.
            let now = LaunchFlags.value(after: LaunchFlags.feedNow).flatMap(BlygDate.parse) ?? Fixtures.now
            buildTimeline = { $0.timeline(now: now) }
        }
        #endif
        return LibraryModel(store: store, fetcher: URLSessionFetcher(), tokens: tokens, transport: apiTransport(),
                            buildTimeline: buildTimeline)
    }

    /// The owner-API transport, with the DEBUG fixture network when the app runs with -useFixtures.
    static func apiTransport() -> URLSessionTransport {
        let config = URLSessionTransport.defaultConfiguration()
        #if DEBUG
        if LaunchFlags.has(LaunchFlags.useFixtures) { config.protocolClasses = [FixtureURLProtocol.self] }
        #endif
        return URLSessionTransport(configuration: config)
    }
}

/// Reads the Appearance setting in a view, not in the App: a change then updates the views below
/// instead of re-evaluating the whole scene (which left Settings unable to take a second tap).
struct ThemedRoot: View {
    @AppStorage(Appearance.storageKey) private var appearance: Appearance = .studio
    @AppStorage(ColorTheme.storageKey) private var colors: ColorTheme = .pencilBlue

    var body: some View {
        let theme = Theme(appearance: appearance, colors: colors)
        RootView()
            .environment(\.theme, theme)
            .tint(theme.pencil)
            .preferredColorScheme(colors.scheme)
    }
}
