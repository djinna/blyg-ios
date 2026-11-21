import Foundation

/// DEBUG-only launch arguments for UI tests and simulator screenshots (ios.md: simctl can't tap).
nonisolated enum LaunchFlags {
    /// Serve the fictional blyg at https://sample.example/ instead of the network.
    static let useFixtures = "-useFixtures"
    /// Keep the library in memory: start empty, save nothing.
    static let inMemory = "-inMemoryLibrary"
    /// `-seedBlyg <url>`: add this blyg at launch.
    static let seedBlyg = "-seedBlyg"
    /// `-openPost <item id>`: open this post at launch, once it's loaded.
    static let openPost = "-openPost"
    /// Open the add-a-blyg sheet at launch.
    static let openAdd = "-openAdd"
    /// Open "Your blygs" at launch.
    static let openBlygs = "-openBlygs"
    /// `-connectToken <token>`: connect the seeded blyg with this token (fixtures only; never a real token).
    static let connectToken = "-connectToken"
    /// Open Settings (Appearance) at launch.
    static let openSettings = "-openSettings"
    /// Open the composer at launch.
    static let openComposer = "-openComposer"

    static func value(after flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static func has(_ flag: String) -> Bool { ProcessInfo.processInfo.arguments.contains(flag) }
}
