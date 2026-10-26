---
name: spotlight-startups
description: Writes the weekly @spotlight.startups carousel, "Top 5 startups in a domain". Use when the prompt asks for a spotlight.startups post (post_type top5).
---

# @spotlight.startups: Top 5 startups in one domain

**Format:** 8-slide carousel (cover, 5 startups, recap, Comment & Follow). The app renders it from your `post` object.

**Audience:** Indian founders, operators and students who follow startups and VC. The tone is sharp, plain-English, a little opinionated. No pitch-deck jargon.

## Steps
1. **Pick the domain.** If the prompt names one (or the previous post's `next_domain`), use it. Otherwise pick a domain that is hot this month and absent from the recent posts. Mix Indian and global startups and lean to at least 2 Indian ones.
2. **Research five real startups** with WebSearch/WebFetch: founded year, HQ city, latest stage, total raised, and one traction metric with its source. Prefer funding news from the last 18 months (Inc42, Entrackr, YourStory, TechCrunch, Crunchbase news, company blogs). Skip companies that shut down or you can't verify.
3. **Write the fields:**
   - `title`: 6–10 words with one `*highlight*`, e.g. "5 startups quietly rebuilding the *power grid*".
   - `tagline`: under 70 chars, plain words, not their marketing line.
   - `raised`: like "$24M" or "₹40 Cr". `stage`: Pre-seed / Seed / Series A…
   - `metric` + `metric_label`: one number and what it measures ("1.8 GWh" + "storage in pilot pipeline").
   - `why`: 1–2 sentences of your own take on why it matters. This is what earns saves.
   - `investors`: 1–3 notable names.
   - `edition`: "Vol. N · Mon YYYY". The prompt gives the volume if known; otherwise increment the last one.
   - `next_domain`: a different domain to tease next week.
4. **Hook:** one from the bank below or HOOKS.md. Use `"options": "names"` to list the five startups as answers.
5. Put every source URL in `sources`.

## Hook bank
- Which one would you *back with ₹10 lakh*? (options: "names")
- Which becomes a *unicorn first*? (options: "names")
- Which one would you join as *employee #10*? (options: "names")
- Which one *won't survive 3 years*? Be honest.
- Rate this list *out of 10*. Who did we miss?
- Would you *quit your job* to build in this space?

**Follow hook:** the app writes "Next week: {next_domain}" from your field.
