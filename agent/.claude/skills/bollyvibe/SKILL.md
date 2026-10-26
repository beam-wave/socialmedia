---
name: bollyvibe
description: Writes one @bollyvibe upcoming-movie post (official poster, details, teaser link). Use when the prompt asks for a bollyvibe post (post_type movie).
---

# @bollyvibe: upcoming Bollywood / Indian movies

**Format:** 3 slides: official poster, details card (release countdown, cast, director, teaser), then Comment & Follow. Output `post.movies` with exactly one movie.

## Steps
1. Use WebSearch to find an **upcoming** Hindi (or big pan-India) film releasing in theatres or on OTT in the next 4–8 weeks. It should have news this week (poster, teaser, trailer, release date). It must not appear in the recent posts.
2. Verify against official or trade sources (studio's YouTube/Instagram, Bollywood Hungama, Pinkvilla, Koimoi, Wikipedia):
   - `release_date` as YYYY-MM-DD (an announced date only; if unconfirmed, pick another film)
   - `cast` (up to 4 lead names), `director`, `genre` ("Romance · Drama"), `language`, `studio`, `credit` (studio/production house)
3. `teaser_url`: the **official** YouTube teaser or trailer link from the studio or label channel. No fan uploads.
4. `poster_url`: a direct image URL (jpg/png/webp) of the **official** poster. Wikipedia/Wikimedia upload links or trade-site image URLs work best. Check the URL is an image, not an HTML page. The admin reviews it before it goes live.
5. `title_hi`: the title in Devanagari.
6. `badge`: a short status like "Teaser out", "Trailer out", "New poster" or "Releasing Friday".
7. `theme`: marquee, neon or saffron.
8. `hook` with `q_hi`, from the bank below.

Never include song lyrics or dialogue lines from the film.

## Hook bank
- Will you watch it *first day, first show*? / *फ़र्स्ट डे फ़र्स्ट शो* देखोगे? options: FDFS / This weekend / Waiting for OTT
- *Hit or flop*? Predict now, we'll check Monday. options: Hit / Flop
- Rate this teaser *out of 10*.
- *Opening-day* collection? Comment in crores.
- Poster: *fire or meh*? options: Fire / Meh
- Tag the friend you're *watching this with*.

Put every source URL (release date, teaser, poster) in `sources`.
