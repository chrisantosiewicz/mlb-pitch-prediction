# PDF advance report: breakdown and redesign plan

*Draft for Chris's review, 2026-10-10. Nothing has changed in the PDF yet.*

## The core problem

The current page packs eight blocks into one landscape sheet, and every block speaks analyst. A casual fan has no way in: there is no "so what", the type is small, and terms like xwOBA, H-brk and chase% go unexplained. An analyst, meanwhile, gets two blocks that overlap (actual mix by count and model by count) and no sample sizes in some places.

**Recommendation: two pages in one PDF.**
- **Page 1, "The Game Plan."** For any fan, readable in 30 seconds.
- **Page 2, "The Detail."** Everything an analyst wants, with room to breathe.

Same download button, same data. A fan stops after page 1; an analyst flips over.

## Block by block

| # | Block today | Purpose | What's wrong | Change |
|---|---|---|---|---|
| 1 | **Title band + subtitle** (names, hands, teams, data dates, head-to-head, flags) | Identify the matchup and the data window | The subtitle crams four facts into one gray line, and head-to-head is buried | **Page 1:** big names and a plain line ("RHP, Pirates vs. LHB, Dodgers"), with head-to-head as its own small box. Data dates move to the footer. |
| 2 | **Predicted next pitch** (bars + tick for usual mix) | The model's answer for one chosen situation | Good, but "tick = usual mix" needs explaining, and a single situation is a narrow view | **Page 1:** keep it, retitled "If the count is 1-2...", with a one-line legend. Show the family split (fastball / breaking / offspeed) as one stacked bar above it, since that's what a hitter thinks in. |
| 3 | **Mix by count** (12 × 6 heatmap of what he actually threw) | Real tendencies by count | 72 numbers is too many for a fan, and small cells (20 pitches in 3-0) look as solid as big ones | **Page 1:** collapse to three situations a fan understands: *first pitch*, *pitcher ahead*, *hitter ahead*, each as one stacked bar. **Page 2:** keep the full heatmap, fade cells under 30 pitches and label the sample. |
| 4 | **Model by count** (9 counts, family split + top two pitches) | The model's view by count | Overlaps with block 3 and reads as a wall of percentages | **Page 2 only.** Make it a small chart (stacked family bars by count) instead of a table. Page 1's three situations already carry the headline. |
| 5 | **Location maps** (5 density maps) | Where each pitch goes | The maps are tiny, and five of them crowd the page | **Page 1:** only his top two pitches, larger, with a plain caption ("Fastball: up in the zone. Changeup: down and away to lefties"). **Page 2:** all pitches, by count bucket (ahead / behind). |
| 6 | **Expected outcomes by pitch type** (dodged xwOBA bars, both players) | Who wins each pitch-type matchup | xwOBA means nothing to a casual fan, and the dodged bars plus PA labels are busy | **Page 1:** a simple "Pitch-by-pitch edge" strip, one row per pitch, colored *pitcher edge / even / hitter edge* (from shrunk xwOBA vs. league). **Page 2:** keep the full bars with xwOBA and PA. |
| 7 | **Arsenal table** (usage, velo, H-brk, V-brk, whiff, chase, n) | What each pitch is | Abbreviations and eight columns | **Page 2:** full names ("Horizontal break, in"), pitch-color dots, sorted by usage. **Page 1:** only usage and velocity, folded into the pitch-by-pitch strip. |
| 8 | **Platoon splits** (both players vs. L/R) | Handedness context | Fine for analysts, noise for fans | **Page 2 only**, plus the **Savant-style percentile sliders** from the app for both players. They're the most fan-friendly analytics there is. |
| 9 | **Footer** (model note) | Credibility | Too small to read | **Page 2:** a short "How to read this" glossary (xwOBA, whiff, chase, percentile) and a model note ("tested on all of 2026; when it says 40%, it happens about 40% of the time"). |

## New: "Three things to know" (page 1)

Three plain sentences, generated from the data with fixed rules so they never overclaim. Every sentence cites its number and sample. For example:
- "Skenes throws his four-seamer 45% of the time to lefties and goes to the changeup or splitter with two strikes."
- "Ohtani does his damage against fastballs (.422 xwOBA, 259 PA) and is weakest against splitters."
- "First pitch: expect a fastball about half the time."

This is the single biggest step toward the casual fan. The rules: pick the pitcher's top pitch, his two-strike shift, the hitter's best and worst pitch types (minimum PA), and the first-pitch call. A sentence only appears if its sample clears a threshold.

## Layout and style

- **Portrait letter, two pages.** Portrait reads better on a phone and in print.
- **Fonts:** at least 9 pt body and 13 pt section titles. Today's smallest text is about 6 pt.
- **Whitespace:** page 1 holds 5 blocks; page 2 holds 6. Today one page holds 8.
- **One color system:** pitch colors everywhere a pitch appears; red/blue only for good/bad (edge strip, percentiles), matching the app.
- **Plain labels on page 1, technical labels on page 2.**

## Decisions for Chris

1. **Two pages (fan page + analyst page) vs. a one-page fan version with the analyst version as a separate download.** I recommend two pages in one PDF: one file to share, and the fan never has to choose.
2. **Auto-generated "Three things to know."** I recommend yes, with conservative rules and numbers in every sentence.
3. **Portrait vs. landscape.** I recommend portrait.
