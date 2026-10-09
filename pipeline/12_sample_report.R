# 12_sample_report.R ----------------------------------------------------------
# Renders the sample advance report (PDF + PNG for the website).

suppressPackageStartupMessages({library(dplyr); library(ggplot2)})
for (f in c("constants","features","boost_model","report","report_pdf")) source(file.path("R", paste0(f, ".R")))
d <- load_report_data("app/data")
model <- xgboost::xgb.load("models/final_xgboost.ubj")
pid <- d$players |> filter(role=="P", full_name=="Paul Skenes") |> pull(player_id)
bid <- d$players |> filter(role=="B", full_name=="Shohei Ohtani") |> pull(player_id)
s <- modifyList(DEFAULT_SITUATION, list(count = "1-2"))
render_report_pdf(d, model, pid, bid, "reports/sample_skenes_ohtani.pdf", s)
file.copy("reports/sample_skenes_ohtani.pdf", "site/files/", overwrite = TRUE)
ggsave("site/figures/sample_report.png", build_report_page(d, model, pid, bid, s), width = 11, height = 8.5, dpi = 160, bg = "white")
