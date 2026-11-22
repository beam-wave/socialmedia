---
name: english-vinglish
description: Writes one @__english.vinglish__ "word of the day" post: one modern English word written as a sentence on a studio wall with a classy rabbit, Hindi meaning in the caption. Use when the prompt asks for an english-vinglish post (post_type word).
---

# @__english.vinglish__: word of the day

**Audience:** Hindi-speaking students and young professionals (18–30) who want to sound better in English at college, at work and online.

## How to write it

**Format:** one card (and reel), styled like a caption on a studio wall: big red serif text reading
*"the word of the day is: WORD. <meaning as a sentence>"*, with a classy rabbit in shades under it. Only English is on the card; the Hindi goes in the caption.

1. Never repeat a word from the recent posts (they list every word used on this channel).
2. Pick **one** word people will love sharing: modern, relatable, a bit witty, useful in real life (e.g. unbothered, overthinking, gaslight, procrastinate, situationship, burnout, petty, nonchalant, delulu-free picks like "resilient"). No swear words, nothing mean about people, no adult themes.
3. Fill `post.days[0]` with `style: "wotd"` and exactly **one** item in `words`:
   - `word`: the word (one or two words, ≤ 14 characters).
   - `en_line`: the meaning **written as a sentence, lower case, ending with a full stop**, the way a friend would explain it, ≤ 70 characters: "it's staying calm when people try to annoy you.", "it's when you replay one conversation 47 times."
   - `pos`, `say` (Devanagari pronunciation with `·`), `en` (short meaning), `hi` (Hindi meaning, main part in `*stars*`), `example` (word in `*stars*`), `example_hi`: these go in the caption.
4. `hook` (under 60 chars, with `q_hi`): e.g. "Tag someone who is *always unbothered*.", "Be honest: are you *this word*?" options Yes / No / Lowkey.
5. Leave `title`, `title_hi` and `sticker` out.

Meanings and pronunciation must be correct; if unsure about a word, pick another. `sources` can stay empty, or list dictionary pages you checked (Cambridge, Oxford Learner's).
