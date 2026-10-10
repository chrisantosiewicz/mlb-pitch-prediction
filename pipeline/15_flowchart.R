# 15_flowchart.R --------------------------------------------------------------
# A simple "how the model works" flowchart for the website and LinkedIn.
# Writes docs/figures/model_flowchart.png (1600 x 900, 16:9).

suppressPackageStartupMessages(library(ggplot2))

NAVY <- "#0b2545"; RED <- "#c8102e"; LIGHT <- "#eef1f4"; INK <- "#1d2733"

boxes <- data.frame(
  id = c("data", "mix", "batter", "situation", "model", "output", "test"),
  x = c(0.5, 2.2, 2.2, 2.2, 4.25, 6.25, 4.25),
  y = c(3, 4.35, 3, 1.65, 3, 3, 0.55),
  w = c(1.25, 1.85, 1.85, 1.85, 1.6, 1.7, 4.2),
  h = c(1.9, 1.05, 1.05, 1.05, 1.9, 1.9, 0.62),
  fill = c(NAVY, LIGHT, LIGHT, LIGHT, RED, NAVY, "white"),
  title = c("STATCAST", "1. WHO'S PITCHING", "2. WHO'S HITTING", "3. THE SITUATION",
            "THE MODEL", "NEXT PITCH", ""),
  body = c("3.6M pitches\n2022-2026",
           "His pitch mix: past seasons,\nthis season so far, and his\nsplit vs. lefties / righties",
           "How pitchers have\nattacked this hitter",
           "Count, last pitches and\nresults, runners, outs,\nscore, inning, pitch count",
           "Gradient boosting\n(xgboost)\n\nStarts from his mix,\nlearns how the situation\nshifts it",
           "A probability for\neach pitch he throws\n\nFour-seam  40%\nChangeup   23%\nSweeper    13%  ...",
           "Tested once on all of 2026:  right pitch 44.7% of the time vs. 37.2% for his usual mix"),
  stringsAsFactors = FALSE)
boxes$dark <- boxes$fill %in% c(NAVY, RED)

arrows <- data.frame(
  x = c(1.125, 1.125, 1.125, 3.125, 3.125, 3.125, 5.05),
  y = c(3.3, 3, 2.7, 4.35, 3, 1.65, 3),
  xend = c(1.24, 1.24, 1.24, 3.42, 3.42, 3.42, 5.37),
  yend = c(4.2, 3, 1.8, 3.4, 3, 2.6, 3))

p <- ggplot() +
  geom_segment(data = arrows, aes(x, y, xend = xend, yend = yend), colour = "#7a8796", linewidth = 1.1,
               arrow = arrow(length = unit(0.18, "inches"), type = "closed")) +
  geom_rect(data = boxes, aes(xmin = x - w / 2, xmax = x + w / 2, ymin = y - h / 2, ymax = y + h / 2, fill = I(fill)),
            colour = ifelse(boxes$id == "test", RED, NA), linewidth = 1) +
  geom_text(data = subset(boxes, title != ""), aes(x, y + h / 2 - 0.2, label = title,
                                                   colour = I(ifelse(dark, "white", NAVY))),
            fontface = "bold", size = 6) +
  geom_text(data = subset(boxes, id != "test"), aes(x, y - 0.12, label = body, colour = I(ifelse(dark, "white", INK))),
            size = 4.9, lineheight = 0.95) +
  geom_text(data = subset(boxes, id == "test"), aes(x, y, label = body), colour = RED, fontface = "bold", size = 5.2) +
  annotate("text", x = 0, y = 5.25, label = "How the next-pitch model works", hjust = 0,
           fontface = "bold", size = 8.5, colour = NAVY) +
  annotate("text", x = 7.1, y = 0.05, label = "Only information known before the pitch is used.",
           hjust = 1, size = 3.6, colour = "#6b7785") +
  coord_cartesian(xlim = c(-0.15, 7.15), ylim = c(-0.05, 5.5), expand = FALSE) +
  theme_void() +
  theme(plot.background = element_rect(fill = "white", colour = NA),
        plot.margin = margin(16, 20, 12, 20))

dir.create("docs/figures", recursive = TRUE, showWarnings = FALSE)
ggsave("docs/figures/model_flowchart.png", p, width = 16, height = 9, dpi = 100, bg = "white")
file.copy("docs/figures/model_flowchart.png", "site/figures/model_flowchart.png", overwrite = TRUE)
message("Wrote docs/figures/model_flowchart.png")
