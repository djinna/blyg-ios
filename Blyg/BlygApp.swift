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
        #if DEBUG
        if LaunchFlags.has(LaunchFlags.inMemory) {
            return LibraryModel(store: nil, fetcher: URLSessionFetcher(), tokens: MemoryTokenStore(), transport: apiTransport())
        }
        #endif
        return LibraryModel(store: .appSupport(), fetcher: URLSessionFetcher(), tokens: KeychainTokenStore(), transport: apiTransport())
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

    var body: some View {
        let theme = Theme(appearance: appearance)
        RootView()
            .environment(\.theme, theme)
            .tint(theme.pencil)
    }
}
