---
title: Blyglet privacy policy
---

# Blyglet privacy policy

*Last updated 2026-11-22, when the app was renamed from Blyg to Blyglet. The policy itself didn't change.*

**Blyglet collects nothing about you.** There are no accounts, analytics, advertising or tracking, and no server run by the developer. The developer receives no data from the app.

## What stays on your phone

- **The blygs you follow and copies of their posts**, so the app opens instantly and works offline. Unfollowing a blyg deletes its copy, and deleting the app deletes everything.
- **Posting tokens**, one for each blyg you connect, kept in the iPhone's Keychain. They're tied to this phone: not synced to iCloud, and they can't be restored onto a different phone. Disconnecting a blyg, or unfollowing it, deletes its token.

## What the app sends, and to whom

- **To the blygs you add:** requests for their public files (`blyg.json`, their archive index and their posts). Like any website, a blyg's server can see your IP address when you fetch from it.
- **To blygs that a post links to:** when you open a post that links to a post on another blyg, the app fetches two public files from that blyg (its `blyg.json` and the linked post), to show the linked post's opening words under it. It does this for up to three links per post, and only for links that point to blyg posts. That blyg's server can see your IP address, as when you tap a link.
- **To other websites that posts point to:** posts can include images or media hosted elsewhere, and the app loads them when you read the post, like a web browser would. Links you tap open in Safari, except links to posts on blygs you follow, which open in the app.
- **To your own blyg when you post:** your text, link and photo, sent to your blyg's Studio with your token. Photos are re-encoded before upload, which removes their location and camera details.

The Share extension ("Post to blyg") reads only what you choose to share, and sends it only to the blyg you post to.

## Children

Blyglet isn't directed at children and collects no information from anyone.

## Changes and contact

If this policy changes, this page will say so, with a new date. The page's history is public on GitHub, so you can see every change. Questions: [open an issue on GitHub](https://github.com/djinna/blyg-ios/issues).
