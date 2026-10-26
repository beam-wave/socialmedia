---
name: mid-innings
description: Writes @mid.innings match-day fixture posts with a 3-question prediction quiz (who wins, first-innings score, player of the match). Result posts are built by the app from the admin's scores, not by you. Use when the prompt asks for a mid.innings fixture post.
---

# @mid.innings: predict before, check after

Every featured match gets two linked posts:

1. **fixture** (before the match): match card, then a 3-question prediction quiz, then Comment & Follow. Fans comment their picks like `1A 2B 3C`.
2. **result** (after the match): scorecard, then the **Prediction check** (the same 3 questions with the correct answer highlighted), then top performers, then Comment & Follow. The app builds this one itself from the admin's scores, timed from your `start_utc` + `match_type`.

Output `post.teams` (code → {code, name, color}) for both teams, and `post.posts` with exactly one item.

## fixture

### Pick the match
- The prompt gives the slot date and the timezone (IST).
- Use WebSearch (ESPNcricinfo, Cricbuzz, ICC, BCCI) to find the most relevant match **starting on that date**. Pick the first that applies:
  1. **India**: men's or women's, any format
  2. **ICC events**: World Cups, Champions Trophy, WTC final, qualifiers
  3. **T20 leagues**: IPL, WPL, BBL, PSL, SA20, CPL, ILT20, MLC, BPL, LPL and other big ones
  4. **The Hundred**
  5. **T10 leagues**: Abu Dhabi T10 and others
  6. Other international matches
  - Within the same tier, prefer the match with bigger stars or a bigger stake (knockout, final, title decider).
- If the slot instructions name a match, use that one.
- **If there's no relevant match that day,** set `skip: true` and say so in `notes`.

### Fields
- `series`, `match` (e.g. "2nd T20I"), `format` (display text, e.g. "T20 · Day/Night"), `venue` (stadium, city).
- `date` like "Wed, 28 Oct" and `time` like "7:00 PM IST", both in IST.
- `start_utc`: the scheduled start in UTC, e.g. `2026-10-28T14:00:00Z`. Verify it, because the result post is timed from it.
- `match_type`: T20, T10, ODI, Test or The Hundred.
- `form1` / `form2`: each team's last 5 results in this format, newest last (e.g. "WWLWW"). Omit them if you can't verify.
- `watch`: up to 3 in-form players with a short recent stat ("212 runs · SR 168 this series").

### `questions`: always exactly these 3, in this order
1. **Who wins the match?** Options are the two full team names.
2. **First-innings score?** 3 bands that fit the format and venue. For a T20 like "Under 160", "160–190", "190+"; for an ODI like "Under 260", "260–310", "310+". Base the bands on recent scores at the venue so each is plausible.
3. **Player of the match?** 3 realistic candidates, mixed from both teams. They're usually the in-form players from `watch`.

### `hook`
Usually `{"q": "Drop your *3 predictions* like 1A 2B 3C", "q_hi": "अपने *3 प्रेडिक्शन* लिखो जैसे 1A 2B 3C"}`. Or `{"q": "Who wins *tonight*?", "options": "teams"}`.

## result

You don't write result posts. The app builds them from the scores the admin enters (both innings, best batter and bowler, player of the match). It works out the winner, the margin and the prediction answers from your fixture's 3 questions. That's why the questions must follow the exact pattern above: Q1 the two full team names, Q2 score bands like "Under 160" / "160–190" / "190+", Q3 three player names.

## Team colours
Use the team's well-known kit colour as hex:

| Team | Colour |
|---|---|
| IND | #1f5fd1 |
| AUS | #d9a400 |
| ENG | #1b3a6b |
| PAK | #0b6623 |
| SA | #007a4d |
| NZ | #111111 |
| SL | #1c3f94 |
| BAN | #006a4e |
| AFG | #1560bd |
| WI | #7b1e3a |

For IPL teams use their primary colour. Codes are 2–4 letters.

Always put the fixture URLs in `sources`.
