import SwiftUI

enum Route: Hashable {
    case post(TimelineEntry)
    case blygs
    case blyg(URL)
    /// Every saved post of one blyg.
    case blygPosts(URL)
    case settings
}

struct RootView: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var wasInBackground = false
    @State private var path: [Route] = []
    @State private var showingAdd = false
    @State private var showingComposer = false

    var body: some View {
        NavigationStack(path: $path) {
            TimelineScreen(showingAdd: $showingAdd, showingComposer: $showingComposer)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .post(let entry): PostView(entry: entry)
                    case .blygs: BlygsView(showingAdd: $showingAdd)
                    case .blyg(let origin): BlygDetailView(origin: origin)
                    case .blygPosts(let origin): BlygPostsView(origin: origin)
                    case .settings: SettingsView()
                    }
                }
        }
        // A link to a post on a blyg you follow opens here, not in Safari.
        .environment(\.openURL, OpenURLAction { url in
            guard let entry = model.entry(forPage: url) else { return .systemAction }
            path.append(.post(entry))
            return .handled
        })
        .sheet(isPresented: $showingAdd) {
            AddBlygView()
        }
        .sheet(isPresented: $showingComposer) {
            ComposerView()
        }
        .task { await launch() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                wasInBackground = true
                model.enteredBackground() // saves now whatever a refresh was holding back for its end
            }
            if phase == .active {
                model.becameActive()
                // Only on coming back from the background (launch() refreshes everything; Control Center doesn't count).
                if wasInBackground {
                    wasInBackground = false
                    Task { await model.refreshStale() }
                }
            }
        }
    }

    private func launch() async {
        #if DEBUG
        if LaunchFlags.has(LaunchFlags.openAdd) { showingAdd = true }
        if let seed = LaunchFlags.value(after: LaunchFlags.seedBlyg) {
            if let origin = try? await model.add(seed), let token = LaunchFlags.value(after: LaunchFlags.connectToken) {
                try? await model.connect(origin, token: token)
            }
        }
        if LaunchFlags.has(LaunchFlags.openComposer) { showingComposer = true }
        if let id = LaunchFlags.value(after: LaunchFlags.openPost),
           let entry = model.timeline.first(where: { $0.document.id == id }) {
            path = [.post(entry)]
            return
        }
        if LaunchFlags.has(LaunchFlags.openBlygs) { path = [.blygs] }
        if LaunchFlags.has(LaunchFlags.openSettings) { path = [.blygs, .settings] }
        if LaunchFlags.has(LaunchFlags.openBlyg), let first = model.library.blygs.first { path = [.blygs, .blyg(first.origin)] }
        if LaunchFlags.has(LaunchFlags.openBlygPosts), let first = model.library.blygs.first {
            path = [.blygs, .blyg(first.origin), .blygPosts(first.origin)]
        }
        #endif
        await model.refreshAtLaunch() // also the one retry, per launch, of blygs a Studio follows that couldn't be reached
    }
}
