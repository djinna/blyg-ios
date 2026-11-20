---
title: Blyg
---

# Blyg

An iPhone app for [Blygger](https://blygger.org) blygs: read the blygs you follow, and post to your own, including from the Share sheet.

- **Reading** needs no account. Add any blyg by its address: the app reads its public `blyg.json`, archive index and posts.
- **Posting** works with blygs run on [Blygger Studio](https://github.com/blygger/blygger-studio). In your blyg's Studio, go to **More → Client access**, create a **REST API** token with the read, draft and publish permissions, and paste it into Blyg (Your blygs → your blyg). Tokens last 30 days.

Blyg is in testing on TestFlight. Source code: [github.com/djinna/blyg-ios](https://github.com/djinna/blyg-ios) (MIT).

## Support

Found a problem or have a question? [Open an issue on GitHub](https://github.com/djinna/blyg-ios/issues), or use **Send Beta Feedback** in the TestFlight app.

Things worth knowing:

- **A post looks wrong.** Blyg shows each post's HTML as its blyg published it. If it looks wrong on the blyg's own web page too, it's the post, not the app.
- **"Didn't accept the token."** Manual tokens expire after 30 days. Make a new one in Studio and connect again.
- **Line breaks.** Studio's markdown joins lines that have a single line break between them. Leave a blank line between paragraphs.
- **Unfollowing** removes a blyg and its saved posts from your phone, plus any token for it. Nothing changes on the blyg.

[Privacy policy](privacy.html)
