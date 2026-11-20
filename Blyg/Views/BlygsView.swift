import SwiftUI

/// The blygs you follow. Unfollowing deletes the saved copy of that blyg from this phone, nothing else.
struct BlygsView: View {
    @Environment(LibraryModel.self) private var model
    @Binding var showingAdd: Bool

    var body: some View {
        List {
            ForEach(model.library.blygs) { blyg in
                NavigationLink(value: Route.blyg(blyg.origin)) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(blyg.title).font(.headline)
                        if model.isConnected(blyg.origin) {
                            Image(systemName: "square.and.pencil").foregroundStyle(.tint)
                                .accessibilityLabel("You can post here")
                        }
                    }
                    Text(blyg.origin.absoluteString)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text(status(blyg))
                        .font(.footnote)
                        .foregroundStyle(blyg.lastError == nil ? Color.secondary : Color.red)
                }
                .padding(.vertical, 2)
                }
                .accessibilityIdentifier("blygRow")
                .swipeActions {
                    Button("Unfollow", role: .destructive) { model.remove(blyg.origin) }
                }
            }
        }
        .navigationTitle("Your blygs")
        .toolbar {
            Button { showingAdd = true } label: { Label("Add a blyg", systemImage: "plus") }
        }
        .refreshable { await model.refreshAll() }
    }

    private func status(_ blyg: SavedBlyg) -> String {
        let count = blyg.items.values.filter(\.isShowable).count
        var parts = [count == 1 ? "1 post" : "\(count) posts"]
        if let error = blyg.lastError {
            parts.append(error)
        } else if let refreshed = blyg.lastRefresh {
            parts.append("updated \(refreshed.formatted(.relative(presentation: .named)))")
        }
        return parts.joined(separator: " · ")
    }
}
