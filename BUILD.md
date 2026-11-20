# BUILD

**Status (2026-11-20):** repo created. Next: Jenna creates the Xcode project (plan step 2). Nothing runs yet.

## Versions

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
- **Posting only to a sandbox blyg** on its own exe.dev VM, never blyg.jdbb.net, until Jenna says otherwise. *Beat:* testing against the live blyg.
- **v0.1 signs in with a pasted Client-access token** (it lasts 30 days, with no refresh). OAuth comes in v0.2, once it's confirmed that Studio accepts an iOS app's https redirect. *Beat:* building OAuth first and risking the demo on an unknown.
- **Apple frameworks only;** no OpenAPI code generator, since it's a package. *Beat:* `swift-openapi-generator`.
- **Third-party network services:** none. The app talks only to the blygs the user adds.

## Lessons

(none yet)
