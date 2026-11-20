import SwiftUI

@main
struct BlygApp: App {
    @State private var model = BlygApp.makeModel()

    var body: some Scene {
        WindowGroup {
            RootView()
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
