import SwiftUI

enum Route: Hashable {
    case post(TimelineEntry)
    case blygs
    case blyg(URL)
    case settings
}

struct RootView: View {
    @Environment(LibraryModel.self) private var model
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
                    case .settings: SettingsView()
                    }
                }
        }
        .sheet(isPresented: $showingAdd) {
            AddBlygView()
        }
        .sheet(isPresented: $showingComposer) {
            ComposerView()
        }
        .task { await launch() }
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
        #endif
        await model.refreshAll()
    }
}
