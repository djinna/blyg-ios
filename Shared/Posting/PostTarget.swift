import Foundation

/// Which blyg a new post or reply goes to by default.
nonisolated enum PostTarget {
    static let storageKey = "lastPostTarget"

    /// A reply to a post on one of your own blygs goes out from that blyg; otherwise the blyg you last
    /// posted from; otherwise the first you connected. (Build 6 always took the first, and a test reply
    /// to the sandbox went out from Jenna's live blyg.)
    static func choose(replyingTo: URL?, connected: [URL], lastUsed: URL?) -> URL? {
        if let replyingTo, connected.contains(replyingTo) { return replyingTo }
        if let lastUsed, connected.contains(lastUsed) { return lastUsed }
        return connected.first
    }

    /// Remembered in the running target's own UserDefaults (privacy manifest: CA92.1). Only an origin, never a token.
    /// The app and the share sheet each remember their own: sharing one would need an App Group.
    static var lastUsed: URL? {
        get { UserDefaults.standard.string(forKey: storageKey).flatMap(URL.init(string:)) }
        set { UserDefaults.standard.set(newValue?.absoluteString, forKey: storageKey) }
    }
}
