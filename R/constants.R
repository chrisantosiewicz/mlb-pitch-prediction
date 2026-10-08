# constants.R -----------------------------------------------------------------
# Shared definitions used by every pipeline step, the app and the reports.

SEASONS <- 2023:2026

# The ~8 Savant-style pitch groups the model predicts (decision 4A).
# Anything not listed here stays in the clean table, so it still counts as
# "the previous pitch" for sequencing, but is never a prediction target.
PITCH_GROUP_MAP <- tibble::tribble(
  ~pitch_type, ~pitch_group, ~pitch_group_name,
  "FF", "FF", "Four-seam",
  "SI", "SI", "Sinker",
  "FC", "FC", "Cutter",
  "SL", "SL", "Slider",
  "ST", "ST", "Sweeper",
  "CU", "CU", "Curveball",
  "KC", "CU", "Curveball",   # knuckle curve
  "SV", "CU", "Curveball",   # slurve
  "CS", "CU", "Curveball",   # slow curve
  "CH", "CH", "Changeup",
  "FS", "FS", "Splitter",
  "FO", "FS", "Splitter"     # forkball
)

PITCH_GROUPS <- c("FF", "SI", "FC", "SL", "ST", "CU", "CH", "FS")
PITCH_GROUP_NAMES <- c(
  FF = "Four-seam", SI = "Sinker", FC = "Cutter", SL = "Slider",
  ST = "Sweeper", CU = "Curveball", CH = "Changeup", FS = "Splitter"
)

# Pitches the pitcher didn't really "choose" as a pitch type: clock-violation
# automatic balls and strikes, pitchouts and intentional balls.
NON_PITCH_DESCRIPTIONS <- c("automatic_ball", "automatic_strike", "pitchout", "intent_ball")
NON_PITCH_TYPES <- c("PO", "IN", "AB")

# Position players pitching are removed. Two-way players (Ohtani) are kept.
PITCHER_POSITION_TYPES <- c("Pitcher", "Two-Way Player")

# Minimum 2026 pitches for a pitcher to get per-pitcher results reported (3A).
MIN_PITCHES_REPORTED <- 500
