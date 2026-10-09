# 13_deploy_app.R -------------------------------------------------------------
# Deploys app/ to shinyapps.io. Needs a one-time rsconnect::setAccountInfo()
# on this machine (the token stays local, never in the repo).

APP_NAME <- "mlb-matchup-report"

stopifnot(nrow(rsconnect::accounts()) > 0, file.exists("app/data/meta.json"),
          file.exists("app/models/final_xgboost.ubj"))
rsconnect::deployApp(
  appDir = "app",
  appName = APP_NAME,
  appTitle = "MLB Matchup Report",
  forceUpdate = TRUE,
  launch.browser = FALSE,
  lint = FALSE
)
