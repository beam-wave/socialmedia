---
name: english-vinglish
description: Writes one @__english.vinglish__ daily vocabulary post (Day N): three useful English words with Devanagari pronunciation, English and Hindi meanings and an example. Use when the prompt asks for an english-vinglish post (post_type words).
---

# @__english.vinglish__: 3 English words a day, with Hindi

**Format:** one card (also made into a reel): a Gen Z heading with a tiny sticker, then three word cards. Each card shows the word, its part of speech, how to say it in Devanagari, a short English meaning, the Hindi meaning and one example sentence in English and Hindi. The `hook` question sits in a small footer. The app sets `day` and the card colours; you write `post.days[0]`.

**Audience:** Hindi-speaking students and young professionals (18–30) who want to speak better English at college, in interviews, at the office and online.

## Steps
1. Read the recent posts in the prompt (they list every word already used). **Never repeat a word.**
2. Pick a theme for today's 3 words so they belong together, and rotate themes: office and emails, interviews, feelings, describing people, money, daily conversation, social media, confidence, study, travel, relationships, health. Mix one easy, one medium and one "sound smart" word.
3. Words must be **useful in real life** and common in Indian English contexts. No rare dictionary words, no slang that will date, nothing offensive.
4. For each word:
   - `word`: as people would type it (capitalise the first letter).
   - `pos`: noun, verb, adj., adv. or phrase.
   - `say`: pronunciation in Devanagari, syllables split with `·` (e.g. `रि·ज़ि·लिएंट`, `प्रो·क्रैस·टि·नेट`). Use the common Indian-English way of saying it; check it.
   - `en`: a simple English meaning, **under 8 words**, easier than the word itself.
   - `hi`: natural Hindi meaning, not a stiff dictionary word; wrap the main meaning in `*stars*` (e.g. `*लचीला*, जल्दी हार न मानने वाला`).
   - `example`: a short everyday sentence (office, college, friends, phone) with the word in `*stars*`. Under 10 words.
   - `example_hi`: the same sentence in natural, conversational Hindi.
5. `title`: a short Gen Z heading (≤ 34 chars), e.g. "3 words to sound smarter", "Office English, unlocked", "Speak like a pro today", "Words for your interview era". `title_hi`: e.g. "आज के 3 अंग्रेज़ी शब्द".
6. `sticker`: 1–2 words, e.g. No cap, Level up, Main character, Office ready, Save this, W vocab.
7. `hook`: a comment question under 60 characters, with `q_hi`. Rotate:
   - Make a sentence with *one of these words*.
   - Which word did you *already know*? options: 1 / 2 / 3 / None
   - Which word will you *use today*? options: 1 / 2 / 3
   - Use *word 2* in a sentence about your day.
   - Rate your English *out of 10*.

Meanings and pronunciation must be correct; when unsure about a word, choose another. `sources` can stay empty, or list dictionary pages you checked (Cambridge, Oxford Learner's).
