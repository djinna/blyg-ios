# Blyg

An iPhone app for [Blygger](https://blygger.org): read the blygs you follow, and post to your own, including from the Share sheet.

Built during the Blygger hackathon (2026-11-20 to 11-27). Work in progress: reading, posting and the Share extension work; testing on TestFlight. See `BUILD.md` for status and decisions.

- SwiftUI, Swift 6, iOS 18+, Apple frameworks only.
- No accounts, analytics or servers of its own. It fetches the blygs you add, plus any images or media their posts link to, which may be hosted elsewhere. When a post links to a post on another blyg, it also fetches that blyg's `blyg.json` and the linked post, to show the linked post under it.
- Posting uses Blygger Studio's owner API. Tokens stay in the iOS Keychain.

## Build it yourself

You need a Mac with **Xcode 27.2 or later**. The project uses Xcode 27's JSON project format, which older versions can't open.

1. Clone this repo.
2. Point it at your own Apple developer team and a bundle ID of your own (Apple ties bundle IDs to one team):
   ```sh
   scripts/use-my-team.sh <YOUR_TEAM_ID> com.example.blyg
   ```
   Your team ID is the 10-character code in Xcode → Settings → Accounts. A free Apple ID's personal team works for running on your own phone; builds expire after 7 days.
3. Open `Blyg.xcodeproj` and run the **Blyg** scheme on a simulator or your phone. Or from the terminal:
   ```sh
   xcodebuild -scheme Blyg -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test
   scripts/phone.sh   # build, install and launch on a connected iPhone
   ```

To try posting without touching a real blyg, run your own [Blygger Studio](https://github.com/blygger/blygger-studio) and make a Client-access token there (More → Client access → REST API, with the read, draft and publish permissions).

How it's built, and why it looks the way it does: [`BUILD.md`](BUILD.md). Notes for coding agents: [`CLAUDE.md`](CLAUDE.md).

MIT licence.
