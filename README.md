# Blyg

An iPhone app for [Blygger](https://blygger.org): read the blygs you follow, and post to your own, including from the Share sheet.

Built during the Blygger hackathon (2026-11-20 to 11-27). Work in progress: nothing runs yet. See `BUILD.md` for status and decisions.

- SwiftUI, Swift 6, iOS 18+, Apple frameworks only.
- No accounts, analytics or servers of its own. It talks only to the blygs you add.
- Posting uses Blygger Studio's owner API. Tokens stay in the iOS Keychain.

MIT licence.
