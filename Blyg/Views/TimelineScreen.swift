import SwiftUI

struct TimelineScreen: View {
    @Environment(LibraryModel.self) private var model
    @Binding var showingAdd: Bool
    @Binding var showingComposer: Bool

    var body: some View {
        content
            .navigationTitle("Blyg")
            .toolbar {
                if !model.library.blygs.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink(value: Route.blygs) {
                            Label("Your blygs", systemImage: "list.bullet")
                        }
                        .accessibilityIdentifier("blygsButton")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: { Label("Add a blyg", systemImage: "plus") }
                        .accessibilityIdentifier("addBlygButton")
                }
                if !model.postingBlygs.isEmpty {
                    ToolbarItem(placement: .bottomBar) {
                        Button { showingComposer = true } label: { Label("New post", systemImage: "square.and.pencil") }
                            .accessibilityIdentifier("composeButton")
                    }
                }
            }
    }

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
        } else if model.timeline.isEmpty {
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
                if model.loadProblem != nil {
                    Label("Your saved copy couldn't be read, so Blyg loaded its backup.", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                }
                ForEach(model.library.blygs.filter { $0.lastError != nil }) { blyg in
                    Label("Couldn't refresh \(blyg.title). \(blyg.lastError ?? "") Showing the saved copy.",
                          systemImage: "wifi.exclamationmark")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(model.timeline) { entry in
                    NavigationLink(value: Route.post(entry)) {
                        TimelineRow(entry: entry)
                    }
                    .accessibilityIdentifier("timelineRow")
                }
            }
            .listStyle(.plain)
            .refreshable { await model.refreshAll() }
        }
    }

    private var problemSummary: String? {
        let errors = model.library.blygs.compactMap { blyg in blyg.lastError.map { "\(blyg.title): \($0)" } }
        return errors.isEmpty ? nil : errors.joined(separator: "\n")
    }
}

struct TimelineRow: View {
    let entry: TimelineEntry
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let header = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                                                      : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
            header {
                Text(entry.blygTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                Text(entry.sortDate, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !entry.excerpt.isEmpty {
                Text(entry.excerpt)
                    .font(.body)
                    .lineLimit(typeSize.isAccessibilitySize ? 12 : 8)
            }
            if let image = entry.imageURL {
                AsyncImage(url: image) { phase in
                    if let picture = phase.image {
                        picture.resizable().scaledToFill()
                    } else {
                        Color.secondary.opacity(0.1)
                    }
                }
                // Crop from the top: a tall screenshot cropped from its middle starts mid-sentence.
                .frame(maxWidth: .infinity, maxHeight: 180, alignment: .top)
                .clipShape(.rect(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary) }
                .padding(.top, 4)
                .accessibilityHidden(true)
            }
            if let badges {
                Text(badges)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var badges: String? {
        var parts: [String] = []
        if entry.document.kind == ItemKind.thread.rawValue { parts.append("Thread") }
        if entry.document.version > 1 { parts.append("Edited · version \(entry.document.version)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Centres its content, and scrolls it when the largest text sizes make it taller than the screen.
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
