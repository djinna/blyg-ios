# BUILD

**Status (2026-11-22):** builds 5, 6, 7 and 8 are in the hackathon group (Jenna removed build 2). Build 8 was uploaded and added on 2026-11-22. It adds quote cards, quoted posts shown as quotes, kept line breaks, the share sheet's default blyg, and refresh on return. On the sandbox, post `6g2xswnerpj7aymc7g41w31gs5` links to two other sandbox posts, for trying quote cards on a phone. Build 9 (2026-11-23) renames the app Blyglet and adds the C6 curl icon, color themes, an icon picker, About and keeping in step with your Studio's follows; Jenna checked it on her phone, and it was uploaded at 12:10 ET from `cb7caba` and added to the hackathon group. On `main` since then, for build 10: US spelling in the app's strings. The site moved to https://blyglet.com the same day. Ideas not yet planned are in `IDEAS.md`.

## Versions

### v0.1, build 9: Blyglet, its icon, themes and Settings (2026-11-22 to 11-23)
- **The app is now called Blyglet** on the home screen, in the share sheet, in its masthead and on its public pages. Saved blygs and connected blygs carry over: the bundle ID, Keychain group and library folder didn't change.
- **New icon, the C6 curl:** a piglet's tail as one rising stroke. Pencil blue on light home screens, a deeper Pencil blue on dark ones, gray for tinted ones.
- **Settings** (formerly "Appearance" in Your blygs):
  - **Color:** Pencil blue (default), Piglet pink, Moss and Butter follow the phone's light or dark setting; Paper is always light and Ink always dark.
  - **App icon:** the twelve C6 palettes.
  - **About:** version and build, Help, Privacy, source.
  - Choosing a row no longer re-wraps its text (Jenna's nit).
- **"Follow what this Studio follows"** is now a switch on a connected blyg's page: it follows the Studio's blygs now and any new ones on refresh.

### v0.1, build 8: quote cards, quotes, line breaks, share sheet (2026-11-22)
- **Quote cards:** when a post links to a blyg post, the post page shows that post's blyg, author, date and opening words under it, at most three. A link to a post on a blyg you follow now opens in the app. The privacy page and README say what's fetched.
- **Quoted posts are shown as quotes.** A thread's `content_html` bakes other posts in as `blockquote.blyg-transclusion` (§10). Timeline rows used to flatten them in, so a thread that opened with a quote showed someone else's words as the author's. A reply to such a thread also sent those words out as its `stub_of.cited.excerpt`. Rows now use the author's own words, plus "Quotes a post". The post page says "From <blyg>" under each quote.
- **Single line breaks are kept** in the composer and the share sheet.
- **The share sheet remembers its last blyg,** using the same rule as the composer.
- **Coming back to the app refreshes:**
  - your own blygs after 30 s, so a share-sheet post shows up;
  - the others after 10 minutes.

### v0.1, build 7: replies go out from the right blyg (2026-11-22)
- **Default "Reply from":** a reply to a post on one of your connected blygs now comes from that blyg; otherwise the blyg you last posted from; otherwise the first you connected. Build 6 always took the first, so Jenna's test reply to a sandbox post went out from her live blyg.
- **Where a post goes is unmissable:** a bordered "To / Reply from" button, and a line saying which blyg it publishes on.

### v0.1, build 6: replies, and the first tester's requests (2026-11-22)
- **Reply to any post:** a thread with `stubOf` `{origin, id, version, cited}`, from whichever of your blygs you choose. Studio refuses `stubOf` on a fragment, and accepts a reply to any blyg without following it first; both tried on the sandbox with Studio's SDK.
- **Replies show "Replying to …"** in the timeline and on the post page, drawn from `stub_of`. The citation is the replier's own label and is shown as theirs.
- **New post** is a bottom bar, for one-handed use (tester request). It has a bar of its own, so it never covers a post (Jenna's earlier nit).
- **"Follow the blygs this Studio follows"** on a connected blyg's page (tester request). It reads `/api/subscriptions`, adds blygs one at a time and skips plain RSS.
- **Edit in Studio, Share and Safari** are in a More menu on the post page.
- Text on the blue buttons stays readable in dark mode.

### v0.1, builds 4 and 5: forkable, and the Appearance fix (2026-11-20)
- **Build 4 (d9a040e):**
  - no team ID in code (the Keychain group comes from the entitlements);
  - `scripts/use-my-team.sh`;
  - build instructions in the README.
- **Build 5 (f7ee126):** Appearance can be switched more than once.

### v0.1, build 3: the Studio and System looks (2026-11-20)
- Restyled to Blygger Studio's design language, with San Francisco as an option (see Decisions).
- **Composer:** a page, not a form.
- **Post page:** metadata above the post, versions below it.
- Uploaded for internal testing while build 2 is in review.

### v0.1, build 2: for Beta App Review (2026-11-20)
- **In-app links:** Help and Privacy, at the bottom of Your blygs.
- **Public pages:** support and privacy on GitHub Pages (https://djinna.github.io/blyg-ios/), written from an audit of the code.
- **App Review demo:** the review notes carry a 30-day sandbox token made for App Review. It's never in the binary or the repo.

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

- **Backups on GitHub and the sandbox VM (2026-11-23).** Every push goes to GitHub and to a bare repo on `blyg-sandbox` (`~/backups/`), Jenna's choice of her exe.dev account as the second home. The local-only files go to a separate private repo and the VM through a script, never to the public repo, since the plan names work accounts. *Beat:* a new VM for backups (one more machine), and Time Machine alone (not off-site).
- **The site is blyglet.com, served by GitHub Pages from `docs/` (2026-11-23).** Jenna registered the domain at Porkbun and set the DNS; GitHub redirects the old `djinna.github.io/blyg-ios/` addresses, so Help and Privacy in builds 5 to 8 keep working, and build 9 links to blyglet.com directly. The front page is a landing page with support below it, under `#support`. *Beat:* a page on a VM, which would be one more server to keep up.
- **The site's type and color switcher is adapted from Jenna's own site, with fonts served from blyglet.com (2026-11-23).** It offers the app's serif plus eight OFL faces, and the app's four light-and-dark color themes. Jenna approved publishing the adapted code under MIT, though its source repo is private. *Beat:* Google Fonts, which makes every visitor's browser contact Google, at odds with the app's no-third-parties stance; the self-hosted latin subsets are 384 KB.
- **Icon: the C6 curl (2026-11-23).** Designed with Jenna on a claude.ai canvas, copied into `scripts/make-icon.swift` exactly. Dark home screens get a deeper Pencil blue (`#173F5C`) with the same curl. *Beat:* the "66" quote mark (it said "Studio", not "little"); one quote, a corner "66", a quote and plus, a lowercase b; the other piglet-tail sketches; Paper as the dark icon (a bright tile on a dark home screen; Jenna chose the deeper blue after comps).
- **Color themes are palettes for the Studio look (2026-11-23).** Each theme sets page, ink, secondary text, rules, panels and the pencil, in light and dark. The System look keeps iOS's colors and takes only the link color. Paper and Ink force light or dark, which gives them a job: as palettes they were the default's own light and dark. A unit test holds every theme to 4.5:1 for text and links. Testing kept light at Jenna's request: the contrast test, plus timeline and post screenshots per theme; only Settings gets the full light, dark and largest-text set. *Beat:* all twelve icon palettes as themes (coral and pinks often fail contrast as link colors).
- **Alternate icons are light-only (2026-11-23).** Only the default icon has dark and tinted versions; Settings says so. The alternates come from `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS`, and a test checks each is in the built app. Whether an alternate set can carry its own dark version wasn't checked.
- **Keeping in step with a Studio is add-only (2026-11-23).** The app remembers the Studio's list and, on refresh, follows only blygs new to it. So a blyg unfollowed in the app never comes back, and nothing is ever unfollowed or written to the Studio. *Beat:* rerunning the whole import on every refresh (it would re-add what you unfollowed); two-way sync (writes to your blyg; see `IDEAS.md`).
- **Name Blyglet (Blyg until 2026-11-22); bundle ID `net.jdbb.blyg`, repo `djinna/blyg-ios`, MIT.** Personal team `K24RHPX75P`.
  - **Why the rename:** Jenna asked in the hackathon group whether naming the app Blyg was gauche. The protocol's steward at the Protocol Institute said it wasn't, but that there may be many competing clients, as with web and desktop clients, so it's courteous not to own the generic term; even the reference client is called Studio, not "Blygger". PI won't host client repos either: it stewards the spec, Studio and the commons sites, and leaves clients to individuals and companies.
  - **Why Blyglet:** "a little blyg", as in piglet, for a small app whose first job is posting from the phone. Said "BLIG-let". "Blygger" is the protocol's name, so the app says "for Blygger".
  - **Only the names people see changed:** the home-screen and share-sheet names, the masthead, the app's own text, the README and the public pages. The bundle ID can't change for an existing App Store Connect app. Targets, scheme and folders stay `Blyg`, as does the library folder on the phone (renaming it would orphan every saved library). The repo stays `blyg-ios`: builds 5 to 8 link to its GitHub Pages, and the hackathon has its URL.
  - *Beat:* keeping Blyg; "Blygger"; Burrow (already a Blygger desktop client); Blygsam (Swedish "modest", but hard to say); Blygroll and Blygnet (they sound like readers, and the app is posting-first); Bower, Blygnib and Blygpen (fine, but Blyglet says "little").
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
- **Support and privacy pages on GitHub Pages from `docs/`**, not on the VM. They're versioned with the code and need no server; the VM keeps the sandbox blyg and, later, the OAuth files. *Beat:* the plan's pages on the VM.
- **Two looks, one layout: Studio (default) and System**, chosen in Your blygs → Appearance (2026-11-20).
  - Studio follows Blygger Studio's own stylesheet: Iowan Old Style for prose, a small sans "apparatus" for metadata, pencil blue (`#23608C`, dark `#8CC0E4`) for editorial marks, hairlines instead of cards.
  - System is San Francisco and iOS colors, for people who prefer sans on a phone.
  - Only type and color change, so each feature is built once. *Beat:* keeping the original stock-list screens as a second layout, which would mean building every feature twice.
  - The setting lives in UserDefaults (privacy manifest reason CA92.1). The share sheet stays System, since sharing the setting would need an App Group.
  - Jenna saw a mockup of Studio-native first (claude.ai design canvas); she doesn't love the look but chose to match Blygger's design language.
- **Blyg stays minimal; Studio is the full editor (2026-11-22).** Studio already ships as an installable web app (`{blyg}/studio/manifest.webmanifest`, with a phone composer). So Blyg covers reading, quick posts, replies and the share sheet, and links to Studio ("Edit in Studio") for editing, threads with quotes, pins and withdrawal. *Beat:* reimplementing Studio's editor natively, or a second "maximal" app.
- **No link previews or embeds in Blyg for now.** Studio adds none to post HTML; its YouTube poster is a script on its own pages only. A post that links to another blyg post could show a quote card from the protocol (v0.2). *Beat:* fetching third-party previews, which would break "talks only to blygs and their media".
- **Third-party network services:** none of our own. The app fetches the blygs the user adds, plus any images or media their posts link to, which can be on other hosts. *Beat:* blocking images from other hosts with a content rule list, which keeps the privacy claim but leaves many posts imageless. The README says this plainly.
- **Sync from `items/index.json` and item documents, not `feed.xml`.** The spec makes item documents the ground truth and the feed a lossy signal. It also lists each version of an item separately, and must be rolled up by `blyg:id`. The feed is used only to find a manifest. *Beat:* the plan's "read `feed.xml`".
- **Never vary behavior by `generator` or `level`.** Spec §3.2 and §13.1 rule 8 forbid it. Posting will be offered when a blyg's `/api` answers and a token is saved. *Beat:* the plan's "read `generator` and only show Post when `/api` responds".
- **Identity is the URL the manifest was fetched from, after redirects (§12.2).** It is never taken from the manifest's `site` field. URLs with stray whitespace are trimmed for display and fetching, because live blygs published them; blyg.jdbb.net did until 2026-11-20.
- **Test data is a made-up blyg (`sample.example`), not copies of real posts.** ios.md says tests never name real people. Also, a copy in a public repo would outlive any post its author later withdrew. *Beat:* the plan's "saved copies of Jenna's public feed".
- **Post HTML renders in a `WKWebView` with JavaScript, frames and stored cookies off.** A link opens outside the app. The text follows Dynamic Type and dark mode through CSS. *Beat:* converting HTML to an attributed string, which uses WebKit anyway and is slow.
- **The timeline is ordered by each post's claimed `updated` date, capped at when the app first saw that version** (§13.7), so a future-dated post can't stay on top. *Beat:* trusting the claimed date.


- **Quote cards fetch only what a link proves is a blyg post (2026-11-22).** Jenna approved the privacy-page change first.
  - **What counts as a candidate:** a `links[]` entry (§10.3a), or an `<a href>` shaped like Studio's item page (`f/{id}/`, `t/{id}/`). The shape alone isn't trusted: the fetched item's own `page` must resolve back to the link.
  - **Cost:** two JSON GETs per card, with nothing fetched for posts already saved.
  - **What a card shows:** escaped plain text, never the linked post's HTML or images.
  - **Where:** on the post page only, never in the timeline.
  - **What's skipped:** links inside baked quotes (they're the quoted author's), the post itself, and the post it replies to.
  - Studio puts every `[[id]]` link in the HTML as an ordinary `<a href>` to the page as well, so both routes find it; checked on the sandbox.
  - *Beat:* resolving every link with the full §12.1 resolver, which would probe any website a post links to; and showing the current version as if it were a quote. A card is a link preview, not a transclusion: only the publisher bakes quotes (§10.3–§10.4).
- **No OAuth during the hackathon (2026-11-22).** It would let testers sign in with their Studio password instead of pasting a token, with no 30-day expiry. From reading Studio 0.65's code: it registers any app without approval, can issue REST tokens, and access tokens last an hour and renew. Still unknown: whether Studio will redirect back into an iOS app. The costs: an Associated Domains file on a domain we control, signing changes, every tester's Studio being new enough, and the app and the share sheet racing to renew one token. Paste stays as a fallback for App Review. Jenna will raise it with the group. *Beat:* building it this week.
- **Single line breaks become Studio's backslash hard break (2026-11-22).** Studio's markdown-it joins single newlines, and a phone has no Shift+Enter.
  - The break is written exactly as Studio's own Shift+Enter writes it (`format-shortcuts.ts`), so Edit in Studio shows familiar markdown.
  - It applies only between two lines of one paragraph. A backslash at the end of a block shows literally, so lists, headings, setext underlines, fences, math and tables are left alone.
  - Every case was checked with Studio 0.65's `renderMarkdown` on the sandbox.
  - *Beat:* a hint only, which leaves the surprise in place; a "line break" key, which is one more control in a minimal composer.
- **Baked quotes: shown as quotes, named from what's saved, never re-fetched (2026-11-22).** Readers display baked HTML and never resolve (§10.3).
  - The "From …" line uses the saved blyg's title, or else the host.
  - The link is the saved post's page, or else Studio's `f/{id}/` convention, as Studio's own page does.
  - *Beat:* fetching each quoted post to label it.

## Lessons

- **`URL.path()` is percent-encoded.** `FileManager.fileExists(atPath: url.path())` is false for anything under `Application Support`, so the saved library was always read from its backup. Use `path(percentEncoded: false)`, and give test folders a space in their name. Found by the offline-state screenshot, not by the tests.
- **Default to the safest target, and make the target visible.** A composer that silently picks a blyg will eventually post somewhere unintended; this happened on the first try (build 6). A reply's natural home is the blyg it answers.
- **Two `@AppStorage` properties on the same key misbehaved.** The Settings screen and the root view both read `appearance`. After the first change, Settings stopped redrawing, so further taps looked dead; the value was still being saved. Fix: one reader (`ThemedRoot`) passes the theme down; Settings only writes. Caught by Jenna on build 3; a UI test now switches back and forth.
- **A web view's text reaches the accessibility tree late on a busy simulator.** The UI test waits 20 s for it.
- **A development archive doesn't register the bundle IDs.** With no capabilities that need one, automatic signing uses the team's wildcard profile, so App Store Connect's New App form can't find the IDs. An App Store export (`xcodebuild -exportArchive` with `destination` `export`, nothing uploaded) registers them. Afterwards, reload App Store Connect.
- **Internal TestFlight needs an emailed invitation, even for the account holder.** The tester shows as "Invited", and the app doesn't appear in TestFlight until the email's link or redeem code is used; refreshing TestFlight doesn't help. The external public link has no such step.
- **Check markdown on Studio's own renderer, not from memory.** On the sandbox, `npx tsx` with a script that imports `~/blygger-studio/src/markdown.ts` renders exactly what a post will show, math plugin included.
- **SF Symbols and Apple's system fonts can't be used in app icons** (license). The icon is drawn as shapes by `scripts/make-icon.swift`.
