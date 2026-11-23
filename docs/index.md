---
title: Blyglet
---

<div class="hero">
  <span class="app-icon" role="img" aria-label="The Blyglet icon: a curl, like a piglet's tail"></span>
  <h1>Blyglet</h1>
  <p class="tagline">A little iPhone app for posting to your blyg.</p>
  <a class="button" href="https://testflight.apple.com/join/HER7EwkZ">Join the beta on TestFlight</a>
  <p class="apparatus">Free while in testing · iPhone, iOS 18 or later</p>
</div>

Blyglet is for [Blygger](https://blygger.org) blygs. It does a few things well, so you can post from anywhere on your phone and get back to your day:

- **Post** text, a link or a photo to your own blyg, in a couple of taps.
- **Share** to your blyg from any app, with "Post to blyg" in the Share sheet.
- **Reply** to any blyg post, from whichever of your blygs you choose.
- **Read** the blygs you follow, with the posts they quote and link to. It can keep in step with the blygs your Studio follows.
- **Make it yours** with color themes and a choice of twelve icons.

Blyglet does quick posts and replies. For editing, threads with quotes, pins and the rest, it opens your blyg's Studio.

## What you need

- **To read:** nothing. Add any blyg by its address; Blyglet reads its public files.
- **To post:** a blyg run on [Blygger Studio](https://github.com/blygger/blygger-studio). In your blyg's Studio, go to **More → Client access**, create a **REST API** token with the read, draft and publish permissions, and paste it into Blyglet (Your blygs → your blyg). Tokens last 30 days, and stay in your phone's Keychain.

Blyglet collects nothing about you and runs no servers. See the [privacy policy](privacy.html).

<h2 id="support">Support</h2>

Found a problem or have a question? [Open an issue on GitHub](https://github.com/djinna/blyg-ios/issues), or use **Send Beta Feedback** in the TestFlight app.

Things worth knowing:

- **A post looks wrong.** Blyglet shows each post's HTML as its blyg published it. If it looks wrong on the blyg's own web page too, it's the post, not the app.
- **"Didn't accept the token."** Manual tokens expire after 30 days. Make a new one in Studio and connect again.
- **Unfollowing** removes a blyg and its saved posts from your phone, plus any token for it. Nothing changes on the blyg.
- **The version** is in Settings → About. Please include it when you report a problem.

Blyglet was called Blyg until 2026-11-22; only the name changed. Its source code is at [github.com/djinna/blyg-ios](https://github.com/djinna/blyg-ios).
