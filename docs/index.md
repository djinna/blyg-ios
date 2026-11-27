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

Blyglet is for [Blygger](https://blygger.org) blygs. It does a few things well, so you can post from anywhere and get back to your day:

- **Post** text, a link or a photo to your blyg in a couple of taps.
- **Share** from any app, with "Post to blyg" in the Share sheet.
- **Reply** to any blyg post, from whichever of your blygs you choose.
- **Read** the blygs you follow, with the posts they quote and link to. Refreshing runs in the background, and posts come in blyg by blyg.
- **Catch up** on the last two weeks: the feed shows up to 200 posts, and older ones are under **All posts** on each blyg's page.
- **Keep in step** with the blygs your Studio follows. One that can't be reached gets two more tries, on later launches.
- **Make it yours** with color themes and icons

<ul class="icon-grid" aria-label="The twelve app icons">
  <li><img src="icons/all/pencil-blue.png" srcset="icons/all/pencil-blue@2x.png 2x" width="120" height="120" alt="Pencil blue" title="Pencil blue" loading="lazy"></li>
  <li><img src="icons/all/paper.png" srcset="icons/all/paper@2x.png 2x" width="120" height="120" alt="Paper" title="Paper" loading="lazy"></li>
  <li><img src="icons/all/sky.png" srcset="icons/all/sky@2x.png 2x" width="120" height="120" alt="Sky" title="Sky" loading="lazy"></li>
  <li><img src="icons/all/piglet-pink.png" srcset="icons/all/piglet-pink@2x.png 2x" width="120" height="120" alt="Piglet pink" title="Piglet pink" loading="lazy"></li>
  <li><img src="icons/all/pink-on-white.png" srcset="icons/all/pink-on-white@2x.png 2x" width="120" height="120" alt="Pink on white" title="Pink on white" loading="lazy"></li>
  <li><img src="icons/all/ink.png" srcset="icons/all/ink@2x.png 2x" width="120" height="120" alt="Ink" title="Ink" loading="lazy"></li>
  <li><img src="icons/all/warm-pink.png" srcset="icons/all/warm-pink@2x.png 2x" width="120" height="120" alt="Warm pink" title="Warm pink" loading="lazy"></li>
  <li><img src="icons/all/blue-pink-curl.png" srcset="icons/all/blue-pink-curl@2x.png 2x" width="120" height="120" alt="Blue, pink curl" title="Blue, pink curl" loading="lazy"></li>
  <li><img src="icons/all/coral.png" srcset="icons/all/coral@2x.png 2x" width="120" height="120" alt="Coral" title="Coral" loading="lazy"></li>
  <li><img src="icons/all/moss.png" srcset="icons/all/moss@2x.png 2x" width="120" height="120" alt="Moss" title="Moss" loading="lazy"></li>
  <li><img src="icons/all/butter.png" srcset="icons/all/butter@2x.png 2x" width="120" height="120" alt="Butter" title="Butter" loading="lazy"></li>
  <li><img src="icons/all/blue-coral-curl.png" srcset="icons/all/blue-coral-curl@2x.png 2x" width="120" height="120" alt="Blue, coral curl" title="Blue, coral curl" loading="lazy"></li>
</ul>

<p class="apparatus">Pencil blue is the default, and the only one with dark and tinted versions.</p>

Blyglet does quick posts and replies. For editing, threads with quotes, pins and the rest, it opens your blyg's Studio.

## What you need

- **To read:** nothing. Add any blyg by its address; Blyglet reads its public files.
- **To post:** a blyg run on [Blygger Studio](https://github.com/blygger/blygger-studio), at an https address. In its Studio, go to **More → Client access**, create a **REST API** token with the read, draft and publish permissions, and paste it into Blyglet (Your blygs → your blyg). The token stays in your phone's Keychain and goes only to your blyg, never in the clear. Tokens last 30 days.

Blyglet collects nothing about you and runs no servers. See the [privacy policy](privacy.html).

<h2 id="support">Support</h2>

Found a problem or have a question? [Open an issue on GitHub](https://github.com/djinna/blyg-ios/issues), or use **Send Beta Feedback** in the TestFlight app.

Things worth knowing:

- **A post looks wrong.** Blyglet shows each post's HTML as its blyg published it. If it looks wrong on the blyg's own web page too, it's the post, not the app.
- **"Didn't accept the token."** Manual tokens expire after 30 days. Make a new one in Studio and connect again.
- **Unfollowing** removes a blyg and its saved posts from your phone, plus any token for it. Nothing changes on the blyg.
- **The version** is in Settings → About. Please include it when you report a problem.

Blyglet was called Blyg until 2026-11-22; only the name changed. Its source code is at [github.com/djinna/blyg-ios](https://github.com/djinna/blyg-ios).
