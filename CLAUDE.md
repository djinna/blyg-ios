# blyg-ios (all agents)

*Blyg: an iPhone app for reading and posting to blygs (the Blygger protocol, blygger.org). Built for the Blygger hackathon, 2026-11-20 to 11-27. Layers on Jenna's global rules and `ios.md` in the `djinna/agents` repo; this file wins where they differ. One bullet per line; no hard wraps.*

- **Status:** current state, versions and decisions are in `BUILD.md`. The working plan is `PLAN_2026-11-20.md`. It's local only and kept out of git through `.git/info/exclude`, because it names work accounts. Its section 0 holds Jenna's answers and wins. Build in the order of its section 6, stopping at each ✓ to show Jenna screenshots in light, dark and the largest text size.
- **This repo is public from the first commit.** Never commit tokens, `.env`, personal data, or anything naming Jenna's work accounts or work projects. Before every commit, grep the staged diff (`git diff --cached`) for tokens (`gho_`, `Bearer`, `token`), `.env` and work names. A public history can't be cleaned.
- **Hackathon:** only commits on `main` count, and merge commits don't, so commit straight to `main`, small and often. Commits count until the end of 2026-11-27 Pacific (03:00 ET 11-28). Author: Jenna's git identity; agent commits add `--trailer "Agent: claude-code" --trailer "Model: <provider>/<model>"`.
- **Apple:** personal team `K24RHPX75P` only. Bundle ID `net.jdbb.blyg`, fixed for good; extension IDs go under it.
- **Simulator:** `iPhone 18 Pro`, named (never `booted`). Jenna's phone: see `xcrun devicectl list devices`.
- **Build and test:** `xcodebuild -scheme Blyg -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath DerivedData.noindex test > DerivedData.noindex/test.log 2>&1` (unit tests plus UI tests). Never pipe it through `head`.
- **Project:** `Blyg.xcodeproj/project.xcproj` (Xcode 27's JSON format; Xcode wrote it directly). Targets `Blyg`, `BlygTests` (Swift Testing) and `BlygUITests` (XCTest). New files under those folders join their target automatically. Swift 6, iOS 18.0+, iPhone only. The shared scheme is in `xcshareddata/xcschemes/`. Close the project in Xcode before an agent moves files or edits `project.xcproj`.
- **Privacy manifest:** `Blyg/PrivacyInfo.xcprivacy`. Add a reason whenever code starts using a required-reason API (UserDefaults, file timestamps and others).
- **Scripts:** `scripts/phone.sh` installs on the phone. `scripts/testflight.sh` uploads: ask first, and bump `CURRENT_PROJECT_VERSION` in every target, the Share extension included. Not copied in yet.
- **Ask Jenna before** creating a VM, uploading to TestFlight, adding testers or submitting for review.
- **Never change the live blyg:** blyg.jdbb.net and its VMs (`jd-blyg`, `jd-blyk` on exe.dev) are read-only from here. The app posts only to the sandbox VM `blyg-sandbox` until Jenna says otherwise.
- **Tokens:** only in the Keychain (app) or a gitignored `.env` (scripts). Never in the bundle, logs, docs, tests or commits.
- **API:** Blygger Studio's `openapi.json` is the source of truth. Hand-write a small Swift client with names that match it. Before writing a call in Swift, try it on the sandbox with Studio's JS SDK from Node.
- **Stack:** SwiftUI, Swift 6, iOS 18+, Apple frameworks only. A package needs Jenna's OK in `BUILD.md` Decisions.
- **Records:** `AGENTLOG.md` (one entry per session, newest first) and `BUILD.md` (status, versions, decisions, lessons), per the global rules.
