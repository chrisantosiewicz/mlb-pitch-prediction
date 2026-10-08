# MLB Next-Pitch Model and Matchup Report: Project Plan

*Draft written 2026-10-07 for Chris's review. Nothing has been built yet: no data pulled, no code, no repo. Every phase ends with a stop for review.*

---

## 1. What we're building and the story it tells

**Product:** a model that predicts a pitcher's next pitch type from game context, and a one-page pitcher-vs-batter advance report that uses it. You get it in three forms: a Shiny app, a GitHub Pages write-up, and a printable PDF.

**The interview story, in one breath:**
> "I built a next-pitch model on 2023-2026 Statcast. It's judged against a pitcher's own pitch mix as the baseline, I split by time instead of randomly, and I shrink thin samples toward similar pitchers. Then I turned it into the advance report a coaching staff would actually use, and it refreshes itself during the season."

Three things make that story credible, and the plan protects all three:
1. **Honest evaluation.** A hard baseline, a time split, calibration checks, and a breakdown of where the model fails.
2. **Usability.** The report reads like a real advance report, not a notebook.
3. **Operations.** It stays current during a season without hand work. Most portfolio projects skip this, and analytics departments notice.

---

## 2. How the pieces fit together

```
 Baseball Savant (Statcast)
          │  baseballr::statcast_search(), pulled in daily or weekly chunks
          ▼
 [Phase 1] data/raw/      parquet, partitioned by season and date (never edited)
          │  cleaning script plus a cleaning log
          ▼
 [Phase 1] data/clean/    one row per pitch, typed, pitch groups mapped, PA and game keys
          │
          ├──► [Phase 1] baseline: shrunken pitcher mix (prior seasons only)
          ▼
 [Phase 2] data/features/ count, prev 1-2 pitches, handedness, runners, outs, score, TTO
          │
          ├──► [Phase 2] multinomial logistic regression ──┐
          ├──► [Phase 3] gradient boosting (xgboost) ──────┤
          │                                                ▼
          │                        [Phase 3] evaluation on 2026: log loss, top-1,
          │                                  calibration, per-pitcher failures
          ▼                                                │
 models/  versioned model files plus metadata (train window, metrics, data hash)
          │                                                │
          ▼                                                ▼
 [Phase 4] app/data/  small precomputed tables: pitch mix by count, zone grids,
          │           platoon splits, xwOBA by pitch type, pitcher priors
          ▼
 [Phase 4] Shiny matchup app (shinyapps.io)
          │  shared report-building functions in R/
          ▼
 [Phase 5] Quarto: PDF advance report  +  GitHub Pages write-up with a sample report
          ▲
 [Phase 6] GitHub Actions on a schedule: pull new games, rebuild tables,
           refresh priors, score live performance, redeploy app and site
```

**The design rule that makes this work:** each phase writes files that the next phase reads, and only reads them. Code that computes a pitch mix or a zone grid lives once, in `R/`, and the app, the PDF, and the website all call it. That's why the PDF, the app, and the site can never disagree with each other.

---

## 3. Tools on your machine (checked 2026-10-07)

| Tool | Status | What it means for the plan |
|---|---|---|
| R 4.5.2 | Installed, **not on PATH**, user library empty | Use this version. Packages go in through `renv` in Phase 0. |
| R 4.3.1 | Installed, 287 packages, including baseballr, tidyverse, shiny, xgboost | Older. Don't build on it, but it shows these packages install fine on your machine. |
| RStudio | Installed | Primary editor. |
| Quarto | Bundled inside RStudio (`RStudio\resources\app\bin\quarto`), not on PATH | Enough for the PDF and site. Add it to PATH, or install standalone Quarto, plus `quarto install tinytex` for PDF output. |
| Python | **Not installed** (only the Microsoft Store stub) | Fine if we go all-R (question 1A). Install it only if you pick 1B. |
| git 2.54 | Installed | Ready. |
| GitHub CLI (`gh`) | Not installed | Optional. Makes repo and release steps easier. |

---

## 4. Phases

Every phase has the same shape: **goal → inputs → work → outputs that feed the next phase → leakage watch → what you'll review.** I stop after each one.

### Phase 0: Setup (small, done once)

- **Work:** create the repo; set up `renv` on R 4.5.2; put Rscript and Quarto on PATH; pin package versions; add a `README` skeleton and a `Makefile`-style `run_all.R` that rebuilds everything from raw data.
- **Repo layout:**
  ```
  R/            shared functions (cleaning, features, report pieces)
  pipeline/     numbered scripts: 01_pull.R, 02_clean.R, 03_features.R, ...
  data/         raw/ clean/ features/   (gitignored; too big for git)
  models/       saved models + metadata JSON (small ones committed)
  app/          Shiny app + app/data/ precomputed tables
  reports/      Quarto PDF template
  site/         Quarto website (publishes to GitHub Pages)
  docs/         data dictionary, cleaning log, decisions log
  .github/workflows/  scheduled refresh + deploy
  ```
- **Data storage choice:** Statcast runs about 700k–750k pitches per season, so roughly 3M rows for 2023-2026. That's too big for git and awkward as CSV. Store it as **parquet** (via `arrow`) and query it with **DuckDB**. Both are fast, both are free, and DuckDB lets you write the SQL you know from coursework against local files, which is a good thing to be able to say in an interview.
- **Outputs → Phase 1:** a working environment that anyone can recreate with `renv::restore()`.

### Phase 1: Data, cleaning, data dictionary, baseline

- **Goal:** a trustworthy pitch table and the number every later model has to beat.
- **Pull:** `baseballr::statcast_search()` returns at most about 25k rows per call, so the pull loops over **one week at a time** (or one day at a time during a season) and writes one parquet file per chunk. A failed chunk can be re-run on its own. Regular season only, 2023-2026.
- **Cleaning (each step goes in `docs/cleaning_log.md` with row counts before and after):**
  - Drop postseason, spring training, and exhibition games (`game_type`).
  - Map `pitch_type` to the ~8 groups from question 4, and log what was dropped (eephus, knuckleball, pitchouts, intentional balls, unknowns).
  - **Sweeper caveat:** Savant began labeling sweepers in 2023, and some pitchers' sliders were relabeled. Check pitchers whose slider/sweeper split moves sharply between seasons. This is a known labeling artifact, not a change in behavior, and it belongs in the limitations section.
  - Build keys: game, plate appearance, and pitch number within the PA and within the game.
  - Derive base state, score differential from the pitcher's point of view, and times through the order (from batter appearances against that pitcher in the game).
  - Identify position players pitching and remove them.
- **Data dictionary:** `docs/data_dictionary.md` covers every field we use: source column, meaning, type, units, missing-value rate, and **when it becomes known** (before the pitch or after it). That last column is the leakage guard for the whole project.
- **Baseline:** for each pitcher, predict their overall pitch mix (vs. that batter hand is a variant), computed **only from seasons before the one being scored**, and shrunk toward similar pitchers (question 6). Score it on the tuning season.
- **Outputs → Phase 2:** `data/clean/` parquet, the data dictionary, the cleaning log, baseline predictions, and baseline log loss / top-1.
- **Leakage watch:**
  - Any field measured *during or after* the pitch is off-limits as a feature: `release_speed`, spin, `plate_x/z`, `description`, `events`, `launch_*`, `estimated_woba`, `zone`. They're for the report, not the model.
  - The baseline mix can't include the season it's scoring.
  - Savant revises recent data for a few days after each game. A pull made immediately after games end can differ from a later one. Re-pull a trailing window (see Phase 6).
- **You'll review:** row counts, what got dropped and why, the dictionary, the baseline numbers.

### Phase 2: Features and multinomial logistic regression

- **Goal:** the interpretable model, and the first honest answer to "does context beat the pitcher's mix?"
- **Features (all known before the pitch is thrown):**
  - Count (balls-strikes as 12 categories)
  - Previous pitch type and previous-previous pitch type, within the same PA, plus a "first pitch of PA" flag. The previous PA's last pitch is a possible extension.
  - Batter handedness × pitcher handedness
  - Runners on (base state), outs, inning, score differential
  - Times through the order
  - **The pitcher's own (shrunken) mix as features.** This is the key design choice. A single league-wide model can't know that one pitcher throws 50% sliders and another throws none. Feeding in each pitcher's prior-season mix, and masking pitches outside their repertoire, lets one model learn how context shifts a pitcher away from their usual mix. That's exactly the question the project asks.
- **Model:** multinomial logistic regression (`nnet::multinom` or `glmnet` with a ridge penalty). In plain language: one equation per pitch type gives a score, and the scores are turned into probabilities that sum to 1. Coefficients read as "in a 0-2 count, the odds of a slider vs. a 4-seam rise by X." That reading carries over from your NFL thesis, and it's the model to put on a whiteboard.
- **Repertoire masking:** after prediction, zero out pitch types the pitcher didn't throw in prior seasons and renormalize. Without this, the model wastes probability on pitches the pitcher doesn't have.
- **Outputs → Phase 3:** the feature table, the fitted model, and tuning-season metrics next to the baseline.
- **Leakage watch:** previous-pitch features must come from the same game and PA in time order; pitcher mix features from prior seasons only; nothing from the test season touches tuning.
- **You'll review:** whether multinomial beats the baseline, by how much, and what the coefficients say.

### Phase 3: Gradient boosting and full evaluation

- **Goal:** test whether a flexible model earns its complexity, then evaluate everything honestly.
- **Model:** xgboost (multiclass softprob) on the same features. It can find interactions (two strikes × same-handed batter × previous pitch was a slider) without you writing them by hand. Tuned on the tuning season with early stopping; a small grid only.
- **Final scoring:** refit both models on 2023-25 and score 2026 **once**. That number goes in the write-up, whatever it is.
- **Evaluation:**
  - **Log loss:** the headline metric, because it rewards honest probabilities, not just right guesses. Reported as improvement over the baseline.
  - **Top-1 accuracy:** easy to explain, but it flatters pitchers who throw one pitch 60% of the time, so always shown next to the baseline.
  - **Calibration plots:** when the model says 40% slider, does a slider come 40% of the time? One plot per pitch type.
  - **Per-pitcher results:** improvement over baseline for each pitcher above the sample threshold. Show the best and worst, and look for patterns (deep repertoires? relievers? pitchers whose mix changed a lot in 2026?).
  - **By situation:** by count, by TTO, by handedness matchup.
  - **Uncertainty:** bootstrap over games for confidence intervals on the improvements, so small differences aren't overclaimed.
  - **Optional, only if time allows:** a small permutation-importance or SHAP view for the boosted model.
- **Limitations, written plainly:** pitch type is only part of what a pitcher decides (location matters as much, and this model ignores it). The model doesn't see the catcher, signs, game plans, or scouting reports. Labels come from Savant's classifier. Expect real but modest gains over the mix, because pitchers are trying to be unpredictable. That's a finding, not a failure.
- **Outputs → Phase 4:** the chosen model (or both) saved in `models/` with metadata, the evaluation report, and per-pitcher reliability flags the app uses to warn when a prediction is weak.
- **You'll review:** the headline results, the failure analysis, and which model the app should use.

### Phase 4: Shiny matchup app

- **Goal:** pick any pitcher and batter, get the one-page report.
- **Report panels (the same functions later build the PDF):**
  1. Header: pitcher and batter, hands, season lines, sample sizes
  2. Pitch mix by count (heatmap table)
  3. Zone map by pitch type (vs. this batter's hand)
  4. Platoon splits (pitcher vs. L/R, batter vs. L/R)
  5. Expected outcomes by pitch type: the batter's xwOBA against each pitch group, the pitcher's xwOBA allowed, both with sample sizes and shrinkage
  6. Model prediction: choose count, previous pitch, base/out state, and TTO, and see a probability bar chart for the next pitch, with a reliability badge
- **Speed:** the app never touches the 3M-row table. Phase 4 precomputes small summary tables into `app/data/` (a few MB), and the model scores one row at a time. That keeps it inside free hosting limits.
- **Hosting:** shinyapps.io free tier (25 active hours a month), which is plenty for a portfolio link.
- **Outputs → Phase 5:** a deployed app URL and the shared `R/report_*.R` functions.
- **You'll review:** the app itself, the layout, and whether it reads like an advance report.

### Phase 5: PDF advance report and GitHub Pages write-up

- **PDF:** a Quarto template that takes `pitcher_id` and `batter_id` as parameters and calls the same report functions. It's styled like an advance scouting sheet: dense, one page, landscape. The app gets a "Download PDF" button that renders it.
- **Site (GitHub Pages, Quarto website):**
  - Overview and the interview story
  - Data and cleaning (links to the dictionary and the log)
  - Methods in plain language (baseline, shrinkage, time split, both models)
  - Results with calibration and per-pitcher plots, and an honest limitations section
  - A sample matchup report, embedded, with the PDF linked
  - Links to the app and the code
- **Outputs → Phase 6:** a live site, a sample PDF, and a README you can link from your resume.
- **You'll review:** the write-up, especially that every claim is supported and nothing is overclaimed.

### Phase 6: Keeping it current (the in-season loop)

The 2026 regular season is over, so this phase is built and tested in the offseason by **replaying 2026 day by day** as if it were live. It then runs for real from Opening Day 2027.

| Cadence | Job | What it does |
|---|---|---|
| **Daily** (GitHub Actions cron, overnight ET) | `refresh_data` | Pull yesterday's games **plus a re-pull of the previous 3–5 days** to catch Savant revisions. Upsert into the season's parquet. Run data checks (row counts vs. games played, missing fields, new pitch types). Fail loudly if checks fail. |
| **Daily** | `refresh_tables` | Rebuild the app's summary tables and refresh each pitcher's shrunken mix with current-season data blended in. This step is cheap and keeps the report current without retraining. |
| **Weekly** | `score_live` | Score the frozen model on the past week's pitches and log log loss and top-1 against the baseline in `docs/monitoring.csv`. A small chart on the site shows it. Drift becomes visible, not guessed at. |
| **Weekly** | `redeploy` | Redeploy the Shiny app (`rsconnect`) with new tables, re-render the site and sample PDF, and publish to GitHub Pages. |
| **Monthly, or when monitoring degrades** | `retrain` | Refit on everything through last month, using a time-ordered check (train through month N−1, evaluate on month N) before promoting. The new model replaces the old one only if it does at least as well on that holdout. Old models stay in `models/` with their metadata. |
| **Offseason** | `rebuild` | A full refit with the new season added, a fresh tuning/test split (e.g., train 2024-26, test 2027), and an update to the write-up. |

- **Where the data lives during automation:** the parquet files are too big for the repo. Options: (a) GitHub Release assets per season, which are free, simple, and what I recommend; (b) cloud storage (S3/R2) if it grows. The Actions job downloads the season file, appends to it, and re-uploads it.
- **Safety rails:** the pipeline is idempotent (re-running a day changes nothing); the app always loads the last good tables, so a failed pull leaves yesterday's report up instead of a broken one; each run writes a short log.
- **Leakage watch during the season:** live predictions for a game may only use data through the previous day. The daily mix refresh has to respect that, or the live monitoring numbers will look better than they really are.

---

## 5. Leakage risks in one place

| Risk | Where | Guard |
|---|---|---|
| Post-pitch fields used as features (velo, spin, location, outcome, xwOBA) | Phases 2–3 | Data dictionary "known when" column; feature list whitelisted, not blacklisted |
| Pitcher mix computed from the season being scored | Phases 1–3, 6 | Prior-seasons-only mixes for evaluation; through-yesterday mixes live |
| Random train/test split | Phases 2–3 | Time split only; test season scored once |
| Tuning on the test season | Phase 3 | Separate tuning season (question 5) |
| Previous-pitch features leaking across games or out of order | Phase 2 | Built with ordered window functions within game and PA; unit-tested |
| Savant reclassifying pitch types (e.g., sweepers) | Phase 1 | Flag pitchers with big label shifts; discuss in limitations |
| Savant revising recent data | Phase 6 | Trailing re-pull window |
| Report xwOBA computed from the same games as the matchup being previewed | Phases 4–6 | "Through date" stamp on every report |

---

## 6. Decisions I need from you

The original six, carried forward with my recommended defaults. A one-line answer like "1A 2A 3A 4A 5A 6A 7A 8A" works.

**1. Main language**
- **A. All R:** baseballr, tidymodels/xgboost, Shiny, Quarto *(recommended: it matches your thesis stack, R 4.5 and RStudio are already installed, and Python isn't)*
- B. Python for data and modeling, R for Shiny (needs a Python install and two environments)

**2. GitHub repo**
- **A. You create an empty public repo (e.g., `mlb-next-pitch`) and attach it here. I commit each phase.** *(recommended)*
- B. I build in this folder and you push later

**3. Which pitchers**
- **A. Model every pitcher with shrinkage; report per-pitcher results only above ~500 pitches in 2026** *(recommended)*
- B. Only qualified starters and high-usage relievers

**4. Pitch-type classes**
- **A. ~8 Savant-style groups** (4-seam, sinker, cutter, slider, sweeper, curve family, changeup, splitter), rare types dropped, predictions masked to each pitcher's repertoire *(recommended)*
- B. 3 buckets: fastball, breaking, offspeed

**5. Time split**
- **A. Train 2023-24, tune on 2025, refit on 2023-25, score 2026 once; regular season only** *(recommended)*
- B. Train 2023-25, test 2026, no separate tuning season

**6. Shrinkage**
- **A. Empirical Bayes toward similar pitchers (same hand and role), weighted by sample size** *(recommended: one-sentence explanation, no Stan)*
- B. Full hierarchical Bayesian model in brms/Stan

New ones this plan raises:

**7. App hosting**
- **A. shinyapps.io free tier** *(recommended: simplest, enough for a portfolio)*
- B. Shinylive (runs in the browser on GitHub Pages; free and always on, but xgboost support in the browser is uncertain, so it's riskier)

**8. In-season refresh**
- **A. Build the automation in the offseason, prove it by replaying 2026, and switch it on for Opening Day 2027** *(recommended)*
- B. Skip automation; refresh by hand when needed (less to defend in interviews, but you lose the operations story)

---

## 7. Once you say go

1. Phase 0 setup, then Phase 1 pulls 2023-2026 and stops with the cleaning log, data dictionary, and baseline numbers for your review.
2. Each later phase starts only after you've signed off on the one before.
3. A `docs/decisions.md` log records every choice and the plain-language reason for it, so it doubles as your interview prep.
