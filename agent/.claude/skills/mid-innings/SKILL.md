---
name: mid-innings
description: Writes @mid.innings cricket posts. A match-day fixture post with a 3-question prediction quiz (who wins, first-innings score, player of the match), and after the match a result post, built from facts the admin enters, with the scorecard and the prediction answer key. Use when the prompt asks for a mid.innings post (post_type fixture or result).
---

# @mid.innings: predict before, check after

Every featured match gets two linked posts:

1. **fixture** (before the match): match card, then a 3-question prediction quiz, then Comment & Follow. Fans comment their picks like `1A 2B 3C`.
2. **result** (after the match): scorecard, then the **Prediction check** (the same 3 questions with the correct answer highlighted), then top performers, then Comment & Follow asking *"What was the turning point of the match?"*

The app creates the result post from your fixture (timed from `start_utc` + `match_type`). The admin then types in the match facts, and you write the post from them.

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

The admin types the match facts into the app, and the prompt has them under **"Match facts entered by the admin"**:
- `summary`: free text
- `innings`: per innings, the batting team, a score like "184/7 (20)", the best batter like "Kohli 78* (44)", and the best bowler like "Bumrah 3/24 (4)"
- `pom`: Player of the Match

**Treat these facts as the truth. Don't search for the result.** Only search if a fact is missing and you need it, such as an overs count, and say so in `notes`.

The prompt also includes the **"Linked fixture post"**. Score **its** questions; don't invent new ones.

Build `post.posts[0]` from the facts:
- Keep `series`, `match` and `venue` from the fixture. `team1` is the side that batted first and `team2` the other. `winner` is the team code.
- `result`: one line with the winner in `*stars*`, e.g. "*India* beat Australia by 6 wickets". Work out the margin from the scores if the summary doesn't state it.
- `innings`: runs, wickets and overs per innings, in batting order.
- `pom`: `{name, figures}`.
- `bat`: one entry per innings, that innings' best batter (`team` = batting side).
- `bowl`: one entry per innings, that innings' best bowler (`team` = bowling side).
- `answers`: the fixture's 3 questions, with `q` and `options` copied **exactly**.
  - `answer` is the correct letter. Q1 is the winner, Q2 is the first-innings total against the bands, Q3 is the POM against the 3 names.
  - Use `X` when none of the options happened.
  - Add a short `note` with the fact, e.g. "New Zealand made 186/5".
- `hook`: always exactly this open question, with **no options and no named players or moments**, so fans write their own view:
  `{"q": "What was the *turning point* of the match? Comment your view 👇", "q_hi": "मैच का *टर्निंग पॉइंट* क्या था? कमेंट में अपनी राय लिखो 👇"}`
- Copy `teams` from the fixture.

If the facts are contradictory, or too thin to build the post (e.g. no scores), set `skip: true` and say what's missing in `notes`. The admin will fix the facts.

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

For fixtures, always put the fixture URLs in `sources`. For results, `sources` can be empty because the admin's facts are the source.
