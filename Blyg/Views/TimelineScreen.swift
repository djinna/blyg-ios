import SwiftUI

struct TimelineScreen: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.theme) private var theme
    @Binding var showingAdd: Bool
    @Binding var showingComposer: Bool

    var body: some View {
        content
            .navigationTitle("Blyglet")
            // With the feed showing, the masthead row carries the name, so the bar stays small.
            .navigationBarTitleDisplayMode(showsFeed ? .inline : .large)
            .toolbar {
                if showsFeed {
                    ToolbarItem(placement: .principal) { Text(verbatim: "").accessibilityHidden(true) }
                }
            }
            .toolbar {
                if !model.library.blygs.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink(value: Route.blygs) {
                            Label("Your blygs", systemImage: "list.bullet")
                        }
                        .accessibilityIdentifier("blygsButton")
                    }
                }
                // Before any blyg is connected, adding one is the main thing to do. After that, posting is,
                // and it sits at the bottom (below) where a thumb reaches it; adding a blyg lives in Your blygs.
                if model.postingBlygs.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingAdd = true } label: { Label("Add a blyg", systemImage: "plus") }
                            .accessibilityIdentifier("addBlygButton")
                    }
                }
            }
    }

    /// The feed is shown once any post is saved, even when none is recent enough to be in it: then it says so,
    /// and New post and pull to refresh stay where they are.
    private var showsFeed: Bool { !model.timeline.isEmpty || model.library.hasPosts }

    @ViewBuilder private var content: some View {
        if model.library.blygs.isEmpty {
            ScrollingIfNeeded { ContentUnavailableView {
                Label("No blygs yet", systemImage: "text.quote")
            } description: {
                Text("Add a blyg by its address to read it here. Blygs are public, so there's no account to make.")
            } actions: {
                Button("Add a blyg") { showingAdd = true }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("emptyAddBlygButton")
            } }
        } else if !showsFeed {
            if model.isRefreshingAny {
                ProgressView("Loading posts…")
            } else {
                ScrollingIfNeeded { ContentUnavailableView {
                    Label("No posts yet", systemImage: "tray")
                } description: {
                    Text(problemSummary ?? "The blygs you follow haven't published anything yet.")
                } actions: {
                    Button("Try again") { Task { await model.refreshAll() } }
                } }
            }
        } else {
            List {
                masthead
                if model.loadProblem != nil {
                    notice("Your saved copy couldn't be read, so Blyglet loaded its backup.", systemImage: "exclamationmark.triangle")
                }
                ForEach(model.library.blygs.filter { $0.lastError != nil }) { blyg in
                    notice("Couldn't refresh \(blyg.title). \(blyg.lastError ?? "") Showing the saved copy.", systemImage: "wifi.exclamationmark")
                }
                ForEach(model.timeline) { entry in
                    PostLink(entry: entry, identifier: "timelineRow")
                }
                feedEnd
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(theme.page)
            .refreshable { await model.refreshAll() }
            // One-handed posting (tester request, build 2): a bar of its own, so it never sits over a post.
            .safeAreaInset(edge: .bottom) {
                if !model.postingBlygs.isEmpty {
                    Button { showingComposer = true } label: {
                        Label("New post", systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(theme.onPencil)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(.bar)
                    .accessibilityIdentifier("composeButton")
                }
            }
        }
    }

    /// Studio's masthead: the name at display size, then one apparatus line.
    private var masthead: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Blyglet")
                .font(theme.masthead)
                .foregroundStyle(theme.ink)
                .accessibilityAddTraits(.isHeader)
            Text(followingLine)
                .font(theme.apparatus)
                .foregroundStyle(theme.soft)
        }
        .listRowSeparator(.hidden)
        .listRowBackground(theme.page)
        .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 12, trailing: 16))
    }

    /// The feed has an end: a line saying so and how far back it goes, then where the older posts are.
    private var feedEnd: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(FeedWindow.endLine(shown: model.timeline.count, oldest: model.timeline.last?.sortDate))
            Text(FeedWindow.olderLine)
        }
        .font(theme.apparatus)
        .foregroundStyle(theme.soft)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("feedEnd")
        .listRowSeparator(.hidden, edges: .bottom)
        .listRowBackground(theme.page)
        .listRowSeparatorTint(theme.rule)
        .listRowInsets(EdgeInsets(top: 18, leading: 24, bottom: 28, trailing: 16))
    }

    private var followingLine: String {
        let count = model.library.blygs.count
        var line = count == 1 ? "Following 1 blyg" : "Following \(count) blygs"
        if model.isRefreshingAny {
            line += " · updating…"
        } else if let latest = model.library.blygs.compactMap(\.lastRefresh).max() {
            line += " · updated \(latest.formatted(.relative(presentation: .named)))"
        }
        return line
    }

    private func notice(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(theme.apparatus)
            .foregroundStyle(theme.soft)
            .listRowBackground(theme.page)
            .listRowSeparatorTint(theme.rule)
            .listRowInsets(EdgeInsets(top: 10, leading: 24, bottom: 10, trailing: 16))
    }

    private var problemSummary: String? {
        let errors = model.library.blygs.compactMap { blyg in blyg.lastError.map { "\(blyg.title): \($0)" } }
        return errors.isEmpty ? nil : errors.joined(separator: "\n")
    }
}

/// A post's row as a link to the post, for the feed and for a blyg's own list of posts.
struct PostLink: View {
    let entry: TimelineEntry
    let identifier: String
    @Environment(\.theme) private var theme

    var body: some View {
        NavigationLink(value: Route.post(entry)) {
            TimelineRow(entry: entry)
        }
        .accessibilityIdentifier(identifier)
        .listRowBackground(theme.page)
        .listRowSeparatorTint(theme.rule)
        .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 16))
    }
}

struct TimelineRow: View {
    let entry: TimelineEntry
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            apparatusLine
            if let reply = entry.document.stubOf {
                Label("Replying to \(reply.label)", systemImage: "arrowshape.turn.up.left")
                    .font(theme.apparatus.italic())
                    .foregroundStyle(theme.soft)
            }
            if !entry.excerpt.isEmpty {
                Text(entry.excerpt)
                    .font(theme.prose())
                    .lineSpacing(theme.proseLineSpacing)
                    .foregroundStyle(theme.ink)
                    .lineLimit(typeSize.isAccessibilitySize ? 12 : 8)
            }
            if entry.quoteCount > 0 {
                Label(entry.quoteCount == 1 ? "Quotes a post" : "Quotes \(entry.quoteCount) posts", systemImage: "quote.opening")
                    .font(theme.apparatus)
                    .foregroundStyle(theme.pencil)
            }
            if let image = entry.imageURL {
                AsyncImage(url: image) { phase in
                    if let picture = phase.image {
                        picture.resizable().scaledToFill()
                    } else {
                        theme.sunk
                    }
                }
                // Crop from the top: a tall screenshot cropped from its middle starts mid-sentence.
                .frame(maxWidth: .infinity, maxHeight: 180, alignment: .top)
                .clipShape(.rect(cornerRadius: 2))
                .padding(.top, 2)
                .accessibilityHidden(true)
            }
            if let versionLine {
                Text(versionLine)
                    .font(theme.apparatus.italic())
                    .foregroundStyle(theme.soft)
            }
        }
        .padding(.vertical, 18)
    }

    /// The blyg and the date, in the apparatus voice; a thread is marked in the editorial blue.
    private var apparatusLine: Text {
        var line = Text("")
        if entry.document.kind == ItemKind.thread.rawValue {
            line = Text("THREAD").font(theme.label).tracking(0.6).foregroundStyle(theme.pencil) + Text(" · ")
        }
        return (line + Text("\(entry.blygTitle) · \(Self.date(entry.sortDate))"))
            .font(theme.apparatus)
            .foregroundStyle(theme.soft)
    }

    /// "v2 — smol typo": the latest version's note, as Studio shows it.
    private var versionLine: String? {
        let document = entry.document
        guard document.version > 1 else { return nil }
        let note = document.changelog.first { $0.version == document.version }?.note?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return note.isEmpty ? "v\(document.version)" : "v\(document.version) — \(note)"
    }

    static func date(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return date.formatted(date: .omitted, time: .shortened) }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) { return date.formatted(.dateTime.month(.abbreviated).day()) }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

/// Centers its content, and scrolls it when the largest text sizes make it taller than the screen.
struct ScrollingIfNeeded<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                content.frame(minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}
