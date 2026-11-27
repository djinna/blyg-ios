import SwiftUI

/// Every saved post of one blyg, newest first. The main feed shows only a recent window (`FeedWindow`);
/// this is where the rest are read, so nothing saved is out of reach.
struct BlygPostsView: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.theme) private var theme
    let origin: URL
    /// Nil until the rows have been built (off the main actor: there's a row for every post, however many).
    @State private var posts: [TimelineEntry]?

    var body: some View {
        let blyg = model.blyg(origin)
        Group {
            if let posts {
                if posts.isEmpty {
                    ScrollingIfNeeded { ContentUnavailableView {
                        Label("No posts saved", systemImage: "tray")
                    } description: {
                        Text("Nothing from this blyg is saved on this phone yet.")
                    } }
                } else {
                    List {
                        ForEach(posts) { entry in
                            PostLink(entry: entry, identifier: "blygPostRow")
                        }
                        Text(Self.endLine(posts.count))
                            .font(theme.apparatus)
                            .foregroundStyle(theme.soft)
                            .accessibilityIdentifier("blygPostsEnd")
                            .listRowSeparator(.hidden, edges: .bottom)
                            .listRowBackground(theme.page)
                            .listRowSeparatorTint(theme.rule)
                            .listRowInsets(EdgeInsets(top: 18, leading: 24, bottom: 28, trailing: 16))
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .refreshable { await model.refresh(origin) }
                }
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.page)
        .navigationTitle(blyg?.title ?? "Posts")
        .navigationBarTitleDisplayMode(.inline)
        // Built again whenever the blyg has been refreshed: that's the only time its posts change.
        // When that happens SwiftUI cancels the build under way, which still finishes: its rows are out of date
        // and are dropped, so a slow old build can't land on top of a newer one.
        .task(id: blyg?.lastRefresh) {
            let built = await model.posts(of: origin)
            if !Task.isCancelled { posts = built }
        }
    }

    static func endLine(_ count: Int) -> String {
        count == 1 ? "That's the 1 post saved from this blyg." : "That's all \(count) posts saved from this blyg."
    }
}
