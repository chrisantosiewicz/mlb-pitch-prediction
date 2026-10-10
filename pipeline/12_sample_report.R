# 12_sample_report.R ----------------------------------------------------------
# Renders the sample advance report (two-page PDF + page images for the website).

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
})
for (f in c("constants", "features", "boost_model", "report", "report_insights", "report_pdf")) {
  source(file.path("R", paste0(f, ".R")))
}
d <- load_report_data("app/data")
model <- xgboost::xgb.load("models/final_xgboost.ubj")
pid <- d$players |> filter(role == "P", full_name == "Paul Skenes") |> pull(player_id)
bid <- d$players |> filter(role == "B", full_name == "Shohei Ohtani") |> pull(player_id)
s <- modifyList(DEFAULT_SITUATION, list(count = "1-2"))

render_report_pdf(d, model, pid, bid, "reports/sample_skenes_ohtani.pdf", s)
invisible(file.copy("reports/sample_skenes_ohtani.pdf", "site/files/", overwrite = TRUE))
pages <- build_report_pages(d, model, pid, bid, s)
ggsave("site/figures/sample_report_p1.png", pages$page1, width = 8.5, height = 11, dpi = 150, bg = "white")
ggsave("site/figures/sample_report_p2.png", pages$page2, width = 8.5, height = 11, dpi = 150, bg = "white")
message("Sample report written")
