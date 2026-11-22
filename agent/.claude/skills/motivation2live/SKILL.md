---
name: motivation2live
description: Writes one @_motivation2live__ daily motivation post (Day N / 365) in English and Hindi with a daily action. Use when the prompt asks for a motivation2live post (post_type quote).
---

# @_motivation2live__: Day N / 365 motivation

**Format:** a bold quote card with a Gen Z sticker and "Today's action", then Comment & Follow. The same content also becomes an animated reel (words reveal one by one, the punch phrase pops, trending music), so write for a 2-second read. The app sets `day`, `date` and `total_days`; you write the content in `post.quotes[0]`.

**Voice:** a funny older sibling who still wants you to win. Gen Z humour and internet slang on top, a real push underneath. Short sentences. It speaks to students and young professionals in India (18–28) who scroll too much and know it.

**Funny vs serious:** about 2 of every 3 posts are `mood: "funny"`, the rest `"serious"`. Look at the recent posts and keep the mix; never 3 funny or 3 serious in a row.
- Funny: self-aware roasts and relatable pain. "Your future self is watching you scroll. *Bro, get up.*" / "Main character energy, side character *screen time*." / "You don't need motivation. You need to *put the phone down*." / "Plot twist: *the grind starts now*, not Monday."
- Serious: the classic coach line, still short. "Small steps every day beat *big plans someday*."
- Slang to use lightly (one or two per post, never forced): lock in, locked in, no side quests, main character, aura, rizz (only about skills, never dating), touch grass, NPC, era ("your discipline era"), delulu, it's giving, no cap, lowkey/highkey, W / L.
- Hindi stays natural Hinglish-friendly Hindi: "भाई, उठ जा।", "बहाने बंद।", "फ़ोन साइड में रख।".
- Humour punches at habits and excuses, never at people, bodies, gender, religion, caste, money status or mental health. No swearing, no dating jokes, nothing sad presented as a joke.

## Steps
1. Check the recent posts in the prompt, then pick a theme not used lately. Rotate through discipline, starting, consistency, focus, fear, comparison, sleep and mornings, health, money habits, failure, patience, and identity.
2. `quote`: an original line, **under 14 words**, with one `*punch phrase*` (the punchline, at the end). It should land on its own, like a meme caption.
3. `quote_hi`: natural, conversational Hindi (tum- or tu-form for funny ones), with its own `*highlight*`. Not a word-by-word translation; the joke has to work in Hindi.
4. `vibe`: a 2–4 word sticker in caps-friendly words that sets the tone before the quote: NO SIDE QUESTS, LOCKED IN, DISCIPLINE ERA, AURA +100, TOUCH GRASS LATER, NPC NO MORE, W MINDSET. For serious posts use a calmer one: DAY BY DAY, SHOW UP, QUIET GRIND. Don't repeat the last 5 stickers.
5. `mood`: funny or serious (see the mix above).
6. `action` / `action_hi`: **one** small concrete task doable today in under 30 minutes. Not "be positive"; for example: "Write tomorrow's top 3 tasks before you sleep tonight."
7. Leave `author` empty unless it's a verified real quote (then add the source).
8. Don't set a `theme`: the app picks the card's colours.
9. `hook` with `q_hi`, from the bank below or a new one in the same voice.

## Hook bank
- Type *I'M IN* if you're showing up today. / आज मेहनत करोगे तो लिखो *मैं तैयार हूँ*।
- Day 1 or *one day*? Choose. options: Day 1 / One day
- What time did you *wake up today*? options: Before 6 / 6–8 AM / After 8
- Comment the *one habit* that changed your life.
- What's *stopping you* right now? Be honest.
- Write your goal below. We'll *check on you* in 30 days.
- Did you finish *yesterday's action*? options: Done / Not yet
- Be honest: how many hours did you *scroll today*? options: Under 1 / 1–3 / Don't ask
- Rate your aura today *out of 10*.
- Lock-in or *side quest* today? options: Locked in / Side quest
- Drop a 🔒 if you're *locked in* this week.

`sources` can be empty for original lines.
