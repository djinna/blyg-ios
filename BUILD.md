# BUILD

**Status (2026-11-20):** version 0.1 (build 1) uploaded to TestFlight from commit 9bc7c4b. Next: Jenna installs it from TestFlight and uses it for a day (plan step 6 ✓); then the public pages and the external group (step 7).

## Versions

### v0.1, build 1: first TestFlight upload (2026-11-20)
- **Posting:** connect a blyg with a pasted Client-access token, then post text, a link and a photo.
- **Share extension:** "Post to blyg" from any app's share sheet.
- **Icon:** a quote mark, in light and dark versions.
- Jenna's first posts from the app, to the sandbox and then to blyg.jdbb.net, worked on her phone before the upload.

### v0.1 reader (2026-11-20)
- **Adding a blyg:** follows spec 0.4 §12.1 steps 1–5. It accepts an address, a post link, a feed URL or a page with `<link rel="blyg">`, within six fetches. On failure it lists the URLs it tried.
- **Syncing:** from the archive index, fetching only items whose version changed (6 at a time, 50 per refresh). Withdrawn items drop out, unknown kinds are ignored, and a lower version is treated as a replay. A failed refresh keeps the saved copy and says so.
- **Screens:**
  - a timeline across all blygs;
  - a post page with dates, version history and pins;
  - "Your blygs", with Unfollow;
  - empty, loading, error and offline states.

### v0: plan (2026-11-20)
- A local plan (`PLAN_2026-11-20.md`, not in git) covers the scope, app design, sandbox VM, distribution, risks and build order.
- v0.1 targets the hackathon demo:
  - a reader for several blygs (manifest, feed, items) with an offline cache;
  - a markdown composer that publishes through Studio's owner API, using a Client-access token pasted once and kept in the Keychain;
  - a "Post to blyg" Share extension.
- v0.2: OAuth sign-in, edits with revision conflicts, threads and reply stubs, transclusion previews.

## Decisions

- **Name Blyg, bundle ID `net.jdbb.blyg`, repo `djinna/blyg-ios`, MIT.** "Blygger" is the protocol's name, so the app says "for Blygger" instead. Personal team `K24RHPX75P`. *Beat:* using "Blygger" as the app name.
- **Commit straight to `main`.** The hackathon leaderboard counts only default-branch commits and skips merge commits. *Beat:* feature branches with PRs.
- **External TestFlight with a public link, and `testFlightInternalTestingOnly = false` from the start.** This departs from ios.md's internal-only default. The reason: the app holds no private data. It shows public blygs, and each user pastes their own token into their own Keychain; none is bundled. *Beat:* internal testing, where every tester must first become an App Store Connect user on the team.
- **Testing only on a sandbox blyg** on its own exe.dev VM, never blyg.jdbb.net. *Beat:* testing against the live blyg.
  - From 2026-11-20 Jenna may connect her live blyg in her own copy of the app, at her request.
  - Its token is made in her live Studio and goes straight to her phone's Keychain. It never passes through this project or an agent.
  - The sandbox (2026-11-20) is a copy of the live blyg's setup: unmodified Studio under `wrangler dev`, secrets outside the code folder.
  - It has none of the live blyg's extras: no skin proxy, AI key, or poll and update timers. A sandbox needs none of them, and every extra is something else to keep running.
- **v0.1 signs in with a pasted Client-access token** (it lasts 30 days, with no refresh). OAuth comes in v0.2, once it's confirmed that Studio accepts an iOS app's https redirect. *Beat:* building OAuth first and risking the demo on an unknown.
- **iPhone only, iOS 18.0 and later.** The minimum is the plan's choice: it lets testers with older iPhones install the app, and the APIs needed (SwiftUI, PhotosUI, AuthenticationServices) all exist on 18. Xcode defaulted to iOS 27.2 and iPhone plus iPad. *Beat:* iPad support, which would need its own layouts. Jenna can still ask for it.
- **Posting reuses Studio's owner API as Studio's own JS SDK does:**
  - create a draft, upload the photo attached to it, and add `![alt](media/…)` to the text (the upload alone doesn't put it in the post), then publish;
  - each step sends the revision the previous one returned.

  Tried on the sandbox with the SDK first (2026-11-20). *Beat:* uploading the photo first. The upload must be attached to an item to be kept.
- **The Share extension reads connections straight from the shared Keychain.** Each token item also holds its blyg's title and API URL, so there's no App Group and no shared files. *Beat:* an App Group holding the library, which would need an explicit App ID and a capability.
- **Apple frameworks only;** no OpenAPI code generator, since it's a package. *Beat:* `swift-openapi-generator`.
- **Third-party network services:** none of our own. The app fetches the blygs the user adds, plus any images or media their posts link to, which can be on other hosts. *Beat:* blocking images from other hosts with a content rule list, which keeps the privacy claim but leaves many posts imageless. The README says this plainly.
- **Sync from `items/index.json` and item documents, not `feed.xml`.** The spec makes item documents the ground truth and the feed a lossy signal. It also lists each version of an item separately, and must be rolled up by `blyg:id`. The feed is used only to find a manifest. *Beat:* the plan's "read `feed.xml`".
- **Never vary behaviour by `generator` or `level`.** Spec §3.2 and §13.1 rule 8 forbid it. Posting will be offered when a blyg's `/api` answers and a token is saved. *Beat:* the plan's "read `generator` and only show Post when `/api` responds".
- **Identity is the URL the manifest was fetched from, after redirects (§12.2).** It is never taken from the manifest's `site` field. URLs with stray whitespace are trimmed for display and fetching, because live blygs published them; blyg.jdbb.net did until 2026-11-20.
- **Test data is a made-up blyg (`sample.example`), not copies of real posts.** ios.md says tests never name real people. Also, a copy in a public repo would outlive any post its author later withdrew. *Beat:* the plan's "saved copies of Jenna's public feed".
- **Post HTML renders in a `WKWebView` with JavaScript, frames and stored cookies off.** A link opens outside the app. The text follows Dynamic Type and dark mode through CSS. *Beat:* converting HTML to an attributed string, which uses WebKit anyway and is slow.
- **The timeline is ordered by each post's claimed `updated` date, capped at when the app first saw that version** (§13.7), so a future-dated post can't stay on top. *Beat:* trusting the claimed date.


## Lessons

- **`URL.path()` is percent-encoded.** `FileManager.fileExists(atPath: url.path())` is false for anything under `Application Support`, so the saved library was always read from its backup. Use `path(percentEncoded: false)`, and give test folders a space in their name. Found by the offline-state screenshot, not by the tests.
- **A web view's text reaches the accessibility tree late on a busy simulator.** The UI test waits 20 s for it.
- **A development archive doesn't register the bundle IDs.** With no capabilities that need one, automatic signing uses the team's wildcard profile, so App Store Connect's New App form can't find the IDs. An App Store export (`xcodebuild -exportArchive` with `destination` `export`, nothing uploaded) registers them. Afterwards, reload App Store Connect.
- **Internal TestFlight needs an emailed invitation, even for the account holder.** The tester shows as "Invited", and the app doesn't appear in TestFlight until the email's link or redeem code is used; refreshing TestFlight doesn't help. The external public link has no such step.
- **SF Symbols and Apple's system fonts can't be used in app icons** (licence). The icon is drawn as shapes by `scripts/make-icon.swift`.
