import Foundation
import os

/// What the model needs from the saved file. `LibraryStore` is the real one; tests wrap it to count and hold saves.
nonisolated protocol LibraryPersisting: Sendable {
    func load() -> (Library, LibraryStore.LoadOutcome)
    /// Encodes and writes the whole library. Slow for a big one, and it blocks: never call it on the main actor.
    func save(_ library: Library) throws
}

/// Saves the library as JSON in Application Support, atomically, keeping the last good copy.
/// A file that won't decode is set aside, never overwritten, and the backup is loaded instead (ios.md: Data).
nonisolated struct LibraryStore: LibraryPersisting {
    let directory: URL

    var fileURL: URL { directory.appending(path: "library.json") }
    var backupURL: URL { directory.appending(path: "library.backup.json") }

    static func appSupport() -> LibraryStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        // Stays "Blyg" after the rename to Blyglet: changing it would orphan every saved library.
        return LibraryStore(directory: base.appending(path: "Blyg", directoryHint: .isDirectory))
    }

    enum LoadOutcome: Equatable {
        case loaded, empty, recoveredFromBackup, unreadable
    }

    func load() -> (Library, LoadOutcome) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            if let backup = decode(backupURL) { return (backup, .recoveredFromBackup) }
            return (Library(), .empty)
        }
        if let library = decode(fileURL) { return (library, .loaded) }
        setAside(fileURL)
        if let backup = decode(backupURL) {
            Log.store.error("library.json unreadable; loaded the backup")
            return (backup, .recoveredFromBackup)
        }
        Log.store.error("library.json and its backup are unreadable; starting empty")
        return (Library(), .unreadable)
    }

    func save(_ library: Library) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(library)
        // The current file becomes the backup only if it's good, so a bad write can't replace the last good copy.
        if decode(fileURL) != nil {
            _ = try? fm.removeItem(at: backupURL)
            try? fm.copyItem(at: fileURL, to: backupURL)
        }
        try data.write(to: fileURL, options: [.atomic])
    }

    private func decode(_ url: URL) -> Library? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let library = try? decoder.decode(Library.self, from: data), library.version <= Library.currentVersion else { return nil }
        return library
    }

    private func setAside(_ url: URL) {
        let stamp = Int(Date.now.timeIntervalSince1970)
        let aside = directory.appending(path: "library.unreadable-\(stamp).json")
        try? FileManager.default.moveItem(at: url, to: aside)
    }
}
