# AGENTLOG

- 2026-11-20 12:54 ET · claude-code · anthropic/claude-opus-5-5 · session 066b3c2b-144c-4593-a83e-ccbe5344795a
  Ran the plan's precondition checks and recorded Jenna's section 0 answers. Created the public repo djinna/blyg-ios with `.gitignore`, `LICENSE`, `README.md`, `CLAUDE.md` and `BUILD.md`. Set the global git `user.name`. Walked Jenna through creating the Xcode project. Moved it to the repo root and applied the ios.md settings (Swift 6, iOS 18, iPhone only, `net.jdbb.blyg`, privacy manifest, shared scheme). Added the phone and TestFlight scripts. Built the v0.1 reader (resolve, sync, saved library, timeline, post page) with 34 unit tests and a UI test against a fictional fixture blyg, and found and fixed a percent-encoded path bug in the store. Created exe.dev VM `blyg-sandbox` and set up Studio 0.65.0 on it (public at blyg-sandbox.exe.xyz), added it as a Rex host. Built posting (Studio owner API client, Keychain tokens, composer), the Share extension and the app icon. Uploaded v0.1 build 1 to TestFlight from commit 9bc7c4b.

- 2026-11-20 12:40 ET · claude-code · anthropic/claude-opus-5-5 · session f629d2b1-f893-41b2-90a9-4ba90ddcbc84
  Wrote PLAN_2026-11-20.md (plan and handoff prompt for a Blygger iOS app) from another session. Read blygger.org, blyg.jdbb.net and the Studio docs. Nothing built, no repo, no VM.
