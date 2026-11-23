# IDEAS

Ideas not yet planned, newest first. When one is built, it moves to `BUILD.md` (a version entry, and a decision if one was made) and leaves this list.

## Keep the followed blygs in step with your own blyg's Studio (Jenna, 2026-11-23)

**The idea:** follow a blyg once, in Studio or in Blyglet, and it's followed in both. Today you add feeds in both places.

**What exists:** build 6's "Follow the blygs this Studio follows" on a connected blyg's page. It copies Studio's list (`GET /api/subscriptions`) once and skips plain RSS.

**What Studio allows** (sandbox, Studio 0.65, from its `openapi.json`): `GET` and `POST /subscriptions`, `GET`, `PATCH` and `DELETE /subscriptions/{id}`. So both directions are possible in principle.

**Built in build 9:** Studio to Blyglet, add only ("Follow what this Studio follows" is a switch; see `BUILD.md`).

**Still open, smallest first:**
2. **Studio to Blyglet, with removals:** unfollow in the app when a blyg leaves Studio's list. Medium: the app must remember which blygs came from Studio, so it never drops one you added only in the app.
3. **Both ways:** following in Blyglet also subscribes in Studio. Medium to large: it writes to your blyg, so it needs a token with permission to manage subscriptions (unknown which permission that is; today's tokens have read, draft and publish). It also needs a rule for conflicts, and a clear setting, since it changes your blyg.

**Fit:** Blyglet is posting first; reading comes second. Options 2 and 3 make Blyglet a reader that manages your blyg, which is a bigger step. Decide after the hackathon.
