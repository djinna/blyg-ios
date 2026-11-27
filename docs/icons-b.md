---
title: Blyglet · icons, option B
---

<link rel="stylesheet" href="assets/icon-options.css">

<div class="hero hero-stickers">
<div class="hero-text">
  <span class="app-icon" role="img" aria-label="The Blyglet icon: a curl, like a piglet's tail"></span>
  <h1>Blyglet</h1>
  <p class="tagline">A little iPhone app for posting to your blyg.</p>
  <a class="button" href="https://testflight.apple.com/join/HER7EwkZ">Join the beta on TestFlight</a>
  <p class="apparatus">Free while in testing · iPhone, iOS 18 or later</p>
</div>
<ul class="sticker-sheet" aria-label="The app icons">
  <li style="--x:28%;--y:76px;--r:-4deg;--z:20;--i:0;--ny:8px;--nr:-8deg"><img src="icons/all/pencil-blue.png" srcset="icons/all/pencil-blue@2x.png 2x" width="76" height="76" alt="Pencil blue" title="Pencil blue"></li>
  <li style="--x:2%;--y:6px;--r:-12deg;--z:3;--i:1;--ny:30px;--nr:6deg"><img src="icons/all/piglet-pink.png" srcset="icons/all/piglet-pink@2x.png 2x" width="76" height="76" alt="Piglet pink" title="Piglet pink"></li>
  <li style="--x:25%;--y:0px;--r:8deg;--z:2;--i:2;--ny:4px;--nr:-4deg"><img src="icons/all/coral.png" srcset="icons/all/coral@2x.png 2x" width="76" height="76" alt="Coral" title="Coral"></li>
  <li style="--x:50%;--y:10px;--r:-7deg;--z:4;--i:3;--ny:26px;--nr:10deg"><img src="icons/all/sky.png" srcset="icons/all/sky@2x.png 2x" width="76" height="76" alt="Sky" title="Sky"></li>
  <li style="--x:54%;--y:84px;--r:11deg;--z:7;--i:4;--ny:12px;--nr:-11deg"><img src="icons/all/pink-on-white.png" srcset="icons/all/pink-on-white@2x.png 2x" width="76" height="76" alt="Pink on white" title="Pink on white"></li>
  <li style="--x:0%;--y:86px;--r:6deg;--z:6;--i:5;--ny:34px;--nr:5deg"><img src="icons/all/ink.png" srcset="icons/all/ink@2x.png 2x" width="76" height="76" alt="Ink" title="Ink"></li>
  <li style="--x:6%;--y:160px;--r:-9deg;--z:9;--i:6;--ny:2px;--nr:-6deg"><img src="icons/all/warm-pink.png" srcset="icons/all/warm-pink@2x.png 2x" width="76" height="76" alt="Warm pink" title="Warm pink"></li>
  <li style="--x:30%;--y:152px;--r:13deg;--z:10;--i:7;--ny:28px;--nr:9deg"><img src="icons/all/blue-pink-curl.png" srcset="icons/all/blue-pink-curl@2x.png 2x" width="76" height="76" alt="Blue, pink curl" title="Blue, pink curl"></li>
  <li style="--x:52%;--y:164px;--r:-5deg;--z:11;--i:8;--ny:10px;--nr:-3deg"><img src="icons/all/paper.png" srcset="icons/all/paper@2x.png 2x" width="76" height="76" alt="Paper" title="Paper"></li>
  <li style="--x:72%;--y:2px;--r:10deg;--z:5;--i:9;--ny:32px;--nr:12deg"><img src="icons/all/moss.png" srcset="icons/all/moss@2x.png 2x" width="76" height="76" alt="Moss" title="Moss"></li>
  <li style="--x:74%;--y:156px;--r:7deg;--z:12;--i:10;--ny:6px;--nr:-9deg"><img src="icons/all/blue-coral-curl.png" srcset="icons/all/blue-coral-curl@2x.png 2x" width="76" height="76" alt="Blue, coral curl" title="Blue, coral curl"></li>
  <li style="--x:75%;--y:80px;--r:-10deg;--z:8;--i:11;--ny:24px;--nr:4deg"><img src="icons/all/butter.png" srcset="icons/all/butter@2x.png 2x" width="76" height="76" alt="Butter" title="Butter"></li>
</ul>
</div>

Blyglet is for [Blygger](https://blygger.org) blygs. It does a few things well, so you can post from anywhere and get back to your day:

- **Post** text, a link or a photo to your blyg in a couple of taps.
- **Share** from any app, with "Post to blyg" in the Share sheet.
- **Reply** to any blyg post, from whichever of your blygs you choose.
- **Read** the blygs you follow, with the posts they quote and link to. Refreshing runs in the background, and posts come in blyg by blyg.
- **Catch up** on the last two weeks: the feed shows up to 200 posts, and older ones are under **All posts** on each blyg's page.
- **Keep in step** with the blygs your Studio follows. One that can't be reached gets two more tries, on later launches.
- **Make it yours** with color themes and icons.

<p class="apparatus icon-note">Pencil blue is the default, and the only one with dark and tinted versions.</p>

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
