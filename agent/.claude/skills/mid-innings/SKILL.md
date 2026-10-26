---
name: mid-innings
description: Writes one @mid.innings cricket post, either a match-day fixture with a pre-match quiz or a post-match result. Use when the prompt asks for a mid.innings post (post_type fixture or result).
---

# @mid.innings: cricket fixtures and results

**Formats:** 3 slides each.
- **fixture**: match card (badges, form, venue, players to watch), then a quiz slide, then Comment & Follow.
- **result**: score card, then top performers, then Comment & Follow.

Output `post.teams` (code → {code, name, color}) for both teams, and `post.posts` with exactly one item.

## Picking the match
- The prompt gives the slot date/time and the timezone (IST).
- Use WebSearch (ESPNcricinfo, Cricbuzz, ICC, BCCI) to find the most relevant **men's or women's international or IPL/WPL match** on that date. Priority: India matches, then ICC events, then IPL/WPL, then other big series.
- If the prompt includes admin instructions naming a match, use that.
- **No relevant match that day:** set `skip: true` and say so in `notes`.

## fixture
- `series`, `match` (e.g. "2nd T20I"), `format` (e.g. "T20 · Day/Night"), `date` like "Wed, 28 Oct", `time` like "7:00 PM IST", `venue` (stadium, city).
- `form1` / `form2`: each team's last 5 results in that format, newest last, e.g. "WWLWW". Omit them if you can't verify.
- `watch`: up to 3 in-form players, with a short recent stat ("212 runs · SR 168" in this series).
- `questions`: 3 quick pre-match questions with 2–3 options each (toss, first-innings total band, top scorer, sixes…).
- `hook`: `{"q": "Who wins *tonight*?", "options": "teams"}` or another from the bank.

## result
- **Only after the match has finished.** Verify the final scores on the scorecard. If the match isn't over, is abandoned, or you can't find the scorecard, set `skip: true`.
- `result`: one line with the winner in `*stars*`, e.g. "*India* beat Australia by 6 wickets".
- `innings`: runs, wickets, overs per innings, in batting order.
- `pom`: Player of the Match name and figures.
- `bat`: top 3 batting performances; `bowl`: top 3 bowling (w, r, ov).
- `hook`: a turning-point or rating question.

## Team colours
Use the team's well-known kit colour as hex, for example IND #1f5fd1, AUS #d9a400, ENG #1b3a6b, PAK #0b6623, SA #007a4d, NZ #111111, SL #1c3f94, BAN #006a4e, AFG #1560bd, WI #7b1e3a. For IPL teams use their primary colours. Codes are 2–4 letters.

## Hook bank
- Who wins *tonight*? (options: "teams")
- Comment your *score prediction*. Closest guess gets pinned.
- Toss winner should *bat or bowl*? options: Bat / Bowl
- *Player of the match* pick?
- *Turning point* of the match? Comment the over.
- Rate the *captaincy* out of 10.
- One change to the *XI* for the next game?

Always include scorecard/fixture URLs in `sources`.
