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
            return LibraryModel(store: nil, fetcher: URLSessionFetcher(), tokens: MemoryTokenStore())
        }
        #endif
        return LibraryModel(store: .appSupport(), fetcher: URLSessionFetcher(), tokens: KeychainTokenStore())
    }
}
