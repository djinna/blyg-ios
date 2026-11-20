import Foundation

/// Brings one saved blyg up to date from its archive index (§6.2, §13.2).
/// The index is lossless, so diffing it against what's saved is complete recovery;
/// only items whose version changed are fetched.
nonisolated struct Syncer: Sendable {
    let fetcher: any Fetching
    /// Item documents fetched per refresh, newest first; the rest follow on later refreshes.
    var maxDocumentsPerRefresh = 50
    var concurrency = 6

    enum Failure: Error, Equatable {
        case manifest(status: Int?)
        case index(status: Int?)
        case rateLimited
    }

    /// Returns the updated blyg. Throws, leaving the caller's copy untouched, if the manifest or index can't be read.
    func refresh(_ blyg: SavedBlyg, now: Date = .now) async throws -> SavedBlyg {
        var blyg = blyg

        let manifestResult = try? await fetcher.get(BlygURL.manifest(origin: blyg.origin))
        if let status = manifestResult?.status, status == 429 || status == 503 { throw Failure.rateLimited }
        guard let manifestResult, manifestResult.isOK,
              let manifest = try? JSONDecoder().decode(Manifest.self, from: manifestResult.data) else {
            throw Failure.manifest(status: manifestResult?.status)
        }

        guard let indexURL = BlygURL.index(origin: blyg.origin, manifest: manifest) else { throw Failure.index(status: nil) }
        let indexResult = try? await fetcher.get(indexURL)
        if let status = indexResult?.status, status == 429 || status == 503 { throw Failure.rateLimited }
        guard let indexResult, indexResult.isOK,
              let index = try? JSONDecoder().decode(ItemIndex.self, from: indexResult.data) else {
            throw Failure.index(status: indexResult?.status)
        }

        // Which items need their document fetched?
        var wanted: [ItemIndex.Entry] = []
        for entry in index.items {
            guard ItemKind(rawValue: entry.kind) != nil else { continue } // unknown kind: ignore (§5.3)
            if let saved = blyg.items[entry.id] {
                if entry.version < saved.version { continue } // a replay below the watermark (§13.3)
                if entry.version == saved.version, saved.document != nil || saved.kind == ItemKind.withdrawn.rawValue { continue }
            }
            wanted.append(entry)
        }
        wanted.sort { (BlygDate.parse($0.updated) ?? .distantPast) > (BlygDate.parse($1.updated) ?? .distantPast) }
        let batch = Array(wanted.prefix(maxDocumentsPerRefresh))

        let fetched = try await fetchDocuments(batch, origin: blyg.origin, manifest: manifest)
        for (entry, document) in fetched {
            apply(document, entry: entry, to: &blyg, now: now)
        }

        blyg.manifest = manifest
        blyg.lastRefresh = now
        blyg.lastError = nil
        return blyg
    }

    private func fetchDocuments(_ entries: [ItemIndex.Entry], origin: URL, manifest: Manifest) async throws -> [(ItemIndex.Entry, ItemDocument)] {
        var results: [(ItemIndex.Entry, ItemDocument)] = []
        var rateLimited = false
        await withTaskGroup(of: (ItemIndex.Entry, ItemDocument?, Bool).self) { group in
            var next = 0
            func addNext() {
                guard next < entries.count else { return }
                let entry = entries[next]
                next += 1
                group.addTask {
                    guard let url = BlygURL.itemDocument(id: entry.id, origin: origin, manifest: manifest),
                          let result = try? await fetcher.get(url) else { return (entry, nil, false) }
                    if result.status == 429 || result.status == 503 { return (entry, nil, true) }
                    guard result.isOK else { return (entry, nil, false) }
                    return (entry, try? JSONDecoder().decode(ItemDocument.self, from: result.data), false)
                }
            }
            for _ in 0..<concurrency { addNext() }
            for await (entry, document, limited) in group {
                if limited { rateLimited = true; group.cancelAll() }
                if let document, document.id == entry.id { results.append((entry, document)) }
                if !rateLimited { addNext() }
            }
        }
        if rateLimited && results.isEmpty { throw Failure.rateLimited }
        return results
    }

    /// Item documents are ground truth (§13.1 rule 1). Highest version wins; a lower one is a replay and is dropped.
    func apply(_ document: ItemDocument, entry: ItemIndex.Entry, to blyg: inout SavedBlyg, now: Date) {
        let saved = blyg.items[document.id]
        if let saved, document.version < saved.version { return }
        if let saved, document.version == saved.version, saved.document != nil { return }
        guard let kind = ItemKind(rawValue: document.kind) else { return }
        let seenAt = (saved?.version == document.version ? saved?.versionSeenAt : nil) ?? now
        switch kind {
        case .withdrawn:
            // Roll up to null: drop the content, keep the watermark (§13.4).
            blyg.items[document.id] = SavedItem(id: document.id, kind: kind.rawValue, version: document.version,
                                                versionSeenAt: seenAt, document: nil)
        case .fragment, .thread:
            blyg.items[document.id] = SavedItem(id: document.id, kind: kind.rawValue, version: document.version,
                                                versionSeenAt: seenAt, document: document)
        }
    }
}
