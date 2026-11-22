import Foundation

/// What the composer (or the Share extension) hands over to publish.
nonisolated struct PostDraft: Sendable, Equatable {
    var text: String = ""
    var link: URL?
    var linkTitle: String = ""
    var photo: MediaUpload?

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && link == nil && photo == nil
    }
}

nonisolated enum PostStep: Sendable, Equatable {
    case creating, uploadingPhoto, publishing
}

nonisolated enum PostFailure: Error, Equatable {
    /// Nothing reached the blyg.
    case notPosted(StudioError)
    /// A draft exists in Studio (with this id) but wasn't published: finish it there.
    case draftSaved(id: String, StudioError)
    case transport(String)
}

nonisolated enum LinkCheck {
    /// True when a link's #fragment looks like a key rather than a place on the page: long and random-looking.
    /// End-to-end encrypted invites (chats, drawings, file shares) carry their key there, and posting the link publishes the key.
    static func fragmentLooksSecret(_ url: URL?) -> Bool {
        guard let fragment = url?.fragment(percentEncoded: false), fragment.count >= 16 else { return false }
        let runs = fragment.split(whereSeparator: { !($0.isLetter || $0.isNumber) })
        return runs.contains { run in
            run.count >= 16 && run.contains(where: \.isNumber) && run.contains(where: \.isUppercase) && run.contains(where: \.isLowercase)
        }
    }

    static let secretWarning = "The part of this link after # looks like a key. Posting it makes it public, and anyone could open what it unlocks."
}

nonisolated enum PostMarkdown {
    /// The fragment's markdown: the author's text, then the link on its own paragraph.
    static func compose(_ draft: PostDraft) -> String {
        var parts: [String] = []
        let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { parts.append(text) }
        if let link = draft.link {
            let title = draft.linkTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            // `[text](url)`, or `<url>` with no title. Never `[url]()`: an empty target links to the blyg's own home page.
            parts.append(title.isEmpty ? "<\(link.absoluteString)>" : "[\(escape(title))](\(link.absoluteString))")
        }
        return parts.joined(separator: "\n\n")
    }

    /// An image line pointing at uploaded media, origin-relative when it lives under the blyg
    /// (spec §5.2: an origin-relative spelling follows the blyg if it moves).
    static func image(alt: String, mediaURL: String, origin: URL) -> String {
        var target = mediaURL
        if mediaURL.hasPrefix(origin.absoluteString) { target = String(mediaURL.dropFirst(origin.absoluteString.count)) }
        return "![\(escape(alt))](\(target))"
    }

    static func escape(_ text: String) -> String {
        var out = ""
        for char in text {
            if "\\[]*_`<>".contains(char) { out.append("\\") }
            out.append(char == "\n" ? " " : char)
        }
        return out
    }
}

/// Publishes a draft through Studio's owner API: create, attach the photo, put it in the text, publish.
/// Each step sends the revision the previous one returned, so a concurrent edit in Studio is a conflict, not a lost update.
nonisolated struct Poster: Sendable {
    let client: StudioClient
    let origin: URL

    struct Result: Sendable, Equatable {
        var id: String
        var version: Int
    }

    func post(_ draft: PostDraft, replyTo: ReplyTarget? = nil,
              step: @Sendable (PostStep) async -> Void = { _ in }) async throws(PostFailure) -> Result {
        await step(.creating)
        let created: StudioItem
        do {
            // A reply is a thread with stubOf; Studio refuses stubOf on a fragment.
            created = try await client.createItem(contentMd: PostMarkdown.compose(draft),
                                                  kind: replyTo == nil ? "fragment" : "thread", replyTo: replyTo)
        } catch {
            throw Self.failure(error, draftId: nil)
        }

        var revision = created.revision
        do {
            if let photo = draft.photo {
                await step(.uploadingPhoto)
                let media = try await client.uploadMedia(photo, itemId: created.id, expectedRevision: revision)
                revision = media.revision ?? revision
                var markdown = created.contentMd
                if !markdown.isEmpty { markdown += "\n\n" }
                markdown += PostMarkdown.image(alt: photo.alt, mediaURL: media.url, origin: origin)
                revision = try await client.updateItem(id: created.id, contentMd: markdown, expectedRevision: revision).revision
            }
            await step(.publishing)
            let published = try await client.publishItem(id: created.id, expectedRevision: revision)
            return Result(id: created.id, version: Int(published.version))
        } catch {
            throw Self.failure(error, draftId: created.id)
        }
    }

    private static func failure(_ error: Error, draftId: String?) -> PostFailure {
        guard let studio = error as? StudioError else { return .transport(error.localizedDescription) }
        if let draftId { return .draftSaved(id: draftId, studio) }
        return .notPosted(studio)
    }

    /// Words for the person posting. 401 and 403 mean the token, not the post.
    static func describe(_ failure: PostFailure, blygTitle: String) -> String {
        func reason(_ error: StudioError) -> String {
            switch error.status {
            case 401: return "\(blygTitle) didn't accept the saved token. It may have expired (tokens last 30 days): make a new one in Studio → More → Client access and connect again."
            case 403: return "The token for \(blygTitle) can't do this. It needs the read, draft and publish permissions."
            case 409: return "The post changed in Studio while this was sending."
            case 413: return "The photo is too large for \(blygTitle)."
            case 415: return "\(blygTitle) doesn't accept that kind of photo."
            case 429: return "\(blygTitle) asked us to slow down. Try again in a minute."
            default: return error.message.isEmpty ? "\(blygTitle) answered \(error.status)." : error.message
            }
        }
        switch failure {
        case .notPosted(let error): return reason(error)
        case .draftSaved(_, let error): return reason(error) + " A draft was saved in Studio; you can finish it there."
        case .transport(let message): return "Couldn't reach \(blygTitle): \(message)"
        }
    }
}
