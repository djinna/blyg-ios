import Foundation
import os
import Observation

/// The app's state: the saved library, kept in sync with disk. Opens at once from what's saved;
/// the network only ever adds to it.
@Observable
final class LibraryModel {
    private(set) var library: Library
    private(set) var timeline: [TimelineEntry] = []
    private(set) var refreshing: Set<URL> = []
    /// Set when the saved file couldn't be read at launch, so the app can say so instead of silently starting empty.
    private(set) var loadProblem: LibraryStore.LoadOutcome?

    private let store: LibraryStore?
    private let fetcher: any Fetching

    init(store: LibraryStore?, fetcher: any Fetching) {
        self.store = store
        self.fetcher = fetcher
        if let store {
            let (library, outcome) = store.load()
            self.library = library
            if outcome == .recoveredFromBackup || outcome == .unreadable { loadProblem = outcome }
        } else {
            self.library = Library()
        }
        timeline = library.timeline()
    }

    var isRefreshingAny: Bool { !refreshing.isEmpty }

    func blyg(_ origin: URL) -> SavedBlyg? { library.blygs.first { $0.origin == origin } }

    /// Resolves a URL to a blyg, adds it, then fetches its items. Returns the identity origin.
    @discardableResult
    func add(_ input: String) async throws -> URL {
        let resolved = try await Resolver(fetcher: fetcher).resolve(input)
        if blyg(resolved.origin) == nil {
            library.blygs.append(SavedBlyg(origin: resolved.origin, manifest: resolved.manifest, addedAt: .now))
            save()
        }
        await refresh(resolved.origin)
        return resolved.origin
    }

    func remove(_ origin: URL) {
        library.blygs.removeAll { $0.origin == origin }
        timeline = library.timeline()
        save()
    }

    func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for blyg in library.blygs {
                group.addTask { await self.refresh(blyg.origin) }
            }
        }
    }

    func refresh(_ origin: URL) async {
        guard let current = blyg(origin), !refreshing.contains(origin) else { return }
        refreshing.insert(origin)
        defer { refreshing.remove(origin) }
        let updated: SavedBlyg
        do {
            updated = try await Syncer(fetcher: fetcher).refresh(current)
        } catch {
            // A failed refresh records why and changes nothing else (§13.2).
            guard let index = library.blygs.firstIndex(where: { $0.origin == origin }) else { return }
            library.blygs[index].lastError = Self.describe(error)
            save()
            return
        }
        guard let index = library.blygs.firstIndex(where: { $0.origin == origin }) else { return } // removed meanwhile
        library.blygs[index] = updated
        timeline = library.timeline()
        save()
    }

    private func save() {
        guard let store else { return }
        do { try store.save(library) } catch { Log.store.error("save failed: \(error.localizedDescription, privacy: .public)") }
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case Syncer.Failure.manifest(let status): return status.map { "Its blyg.json answered \($0)." } ?? "Couldn't reach it."
        case Syncer.Failure.index(let status): return status.map { "Its archive index answered \($0)." } ?? "Couldn't read its archive index."
        case Syncer.Failure.rateLimited: return "It asked us to slow down. Try again later."
        case Resolver.Failure.notAURL: return "That doesn't look like a web address."
        case Resolver.Failure.notFound(let tried):
            let list = tried.map { "• \($0.absoluteString)" }.joined(separator: "\n")
            return "No blyg found there. Tried:\n\(list)"
        default: return error.localizedDescription
        }
    }
}
