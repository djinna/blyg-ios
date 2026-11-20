import SwiftUI

enum Route: Hashable {
    case post(TimelineEntry)
    case blygs
}

struct RootView: View {
    @Environment(LibraryModel.self) private var model
    @State private var path: [Route] = []
    @State private var showingAdd = false

    var body: some View {
        NavigationStack(path: $path) {
            TimelineScreen(showingAdd: $showingAdd)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .post(let entry): PostView(entry: entry)
                    case .blygs: BlygsView(showingAdd: $showingAdd)
                    }
                }
        }
        .sheet(isPresented: $showingAdd) {
            AddBlygView()
        }
        .task { await launch() }
    }

    private func launch() async {
        #if DEBUG
        if LaunchFlags.has(LaunchFlags.openAdd) { showingAdd = true }
        if let seed = LaunchFlags.value(after: LaunchFlags.seedBlyg) {
            _ = try? await model.add(seed)
        }
        if let id = LaunchFlags.value(after: LaunchFlags.openPost),
           let entry = model.timeline.first(where: { $0.document.id == id }) {
            path = [.post(entry)]
            return
        }
        #endif
        await model.refreshAll()
    }
}
