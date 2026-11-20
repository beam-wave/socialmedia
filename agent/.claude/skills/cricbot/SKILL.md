---
name: cricbot
description: Writes one @cricbot promo poster (an ad to boost with a Send-message goal) for an AI cricket analytics chat. Use when the prompt asks for a cricbot post (post_type promo).
---

# @cricbot: promo posters for boosting

@cricbot is a cricket analytics chat: people DM it and get win chances, player matchups, pitch and venue stats, form and match-day alerts. Each post is **one ad poster** the admin boosts on Instagram with the "More messages" goal. Its only job: make cricket fans **send a message**.

**Format:** 1 slide (headline, sub line, chat mock-up, 4 feature chips, message button). Output `post.posters` with exactly one poster. This is an ad, so there is no Comment & Follow slide and no `hook`.

## Steps
1. Pick an angle not used in the recent posts: who wins tonight, toss/venue call, a player matchup, pitch report, form check, fantasy-free team analysis, a series preview.
2. If a big match (India, IPL, WPL, World Cup, Ashes) is within the next 3 days, use WebSearch to build the chat around it. Otherwise use a classic matchup. Every number in the chat must be real and checkable (head-to-head, venue records, recent scores); put the URLs in `sources`. If you can't verify a stat, use a softer line without numbers.
3. `headline`: the promise in under 6 words, about being ahead of the game. One `*punch phrase*`. Examples: "Be ahead of *every ball*.", "Know the game *before it happens*.", "Read the pitch *before the toss*."
4. `sub`: one line on what they get, in plain words. Mention it is in their DMs.
5. `chat`: 2 messages (a fan's question `me`, then the `bot` answer with 1–2 real stats in `*stars*`). Answers are short and confident but honest ("narrowly", "edge"), never certain.
6. `win`: only when the question is who wins, with the two team codes and a believable p1 (35–70).
7. `features`: exactly 4 short chips in this order: insights/stats, matchups, pitch/venue, alerts/fixtures.
8. `cta` (e.g. "Send me a message", "Chat with Cricbot") and `cta_sub` (e.g. "Type *HI* to start. Free, no sign-up.").
9. `caption_hook`: the caption's first line, a question for cricket fans (≤ 90 chars, 1–2 emoji).
10. `theme`: stadium, volt or dusk; not the one the last post used.

## Ad rules (Meta reviews boosted posts)
- No betting, odds, fantasy-team "sure picks", guaranteed wins or "100% accurate" claims. Win chances are estimates.
- No team logos, player photos or official tournament marks. Team codes and player names in text are fine.
- No fake urgency or engagement bait ("comment YES"). The ask is: send a message.
- English only, short words, readable in 2 seconds on a phone.
