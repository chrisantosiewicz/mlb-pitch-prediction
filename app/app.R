# MLB matchup report: next-pitch model + pitcher-vs-batter advance report.
# Run from the project root:  shiny::runApp("app")

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(dplyr)
  library(ggplot2)
})
for (f in c("constants", "features", "boost_model", "report", "report_pdf")) source(file.path("lib", paste0(f, ".R")))

d <- load_report_data("data")
model <- xgboost::xgb.load("models/final_xgboost.ubj")

player_choices <- function(role, min_pitches) {
  p <- d$players |>
    filter(role == !!role, pitches >= min_pitches, !is.na(full_name)) |>
    arrange(desc(pitches))
  hand <- if (role == "P") p$pitch_hand else p$bat_side
  stats::setNames(p$player_id, sprintf("%s (%s, %s)", p$full_name, p$team, hand))
}
PITCHERS <- player_choices("P", 300)
BATTERS <- player_choices("B", 300)
default_id <- function(choices, name) {
  hit <- grep(paste0("^", name, " \\("), names(choices))
  if (length(hit)) choices[[hit[1]]] else choices[[1]]
}

RESULT_LABELS <- c(UNKNOWN = "Unknown (average)", ball = "Ball", called = "Called strike",
                   whiff = "Swinging strike", foul = "Foul")
BASE_LABELS <- c("Empty" = "___", "1st" = "1__", "2nd" = "_2_", "3rd" = "__3", "1st & 2nd" = "12_",
                 "1st & 3rd" = "1_3", "2nd & 3rd" = "_23", "Loaded" = "123")
SCORE_LABELS <- c("Tied" = "tied", "Up 1" = "up1", "Up 2-3" = "up2-3", "Up 4+" = "up4+",
                  "Down 1" = "down1", "Down 2-3" = "down2-3", "Down 4+" = "down4+")

theme <- bs_theme(version = 5, primary = "#c8102e", secondary = "#0b2545",
                  base_font = font_google("Roboto"), heading_font = font_google("Roboto Condensed"),
                  font_scale = 0.95)
PCTL <- percentile_rankings(d)

section_header <- function(title, note = NULL) {
  card_header(title, if (!is.null(note)) tags$span(class = "float-end text-muted fw-normal text-none small", note))
}

ui <- page_sidebar(
  title = "Matchup Report  ·  Next-Pitch Model",
  window_title = "MLB Matchup Report",
  fillable = FALSE,   # a scrolling report page, not a fixed-height dashboard
  theme = theme,
  tags$head(tags$link(rel = "stylesheet", href = "savant.css")),
  sidebar = sidebar(
    width = 320,
    h6("Matchup"),
    selectizeInput("pitcher", "Pitcher", choices = NULL),
    selectizeInput("batter", "Batter", choices = NULL),
    h6("Situation for the next pitch"),
    selectInput("count", "Count", FACTOR_LEVELS$count_str, "0-2"),
    uiOutput("prev_inputs"),
    layout_columns(
      selectInput("base_state", "Runners", BASE_LABELS),
      selectInput("outs", "Outs", 0:2)
    ),
    layout_columns(
      selectInput("inning", "Inning", FACTOR_LEVELS$inning_bkt),
      selectInput("score", "Pitcher's team", SCORE_LABELS)
    ),
    layout_columns(
      selectInput("tto", "Time through order", c("1st" = 1, "2nd" = 2, "3rd+" = 3)),
      selectInput("pitch_count", "Pitch count", FACTOR_LEVELS$pitch_count_bkt)
    ),
    checkboxInput("starter", "Pitcher started this game", TRUE),
    h6("Display"),
    selectInput("bucket", "Location maps: counts", names(COUNT_BUCKETS)),
    checkboxInput("family", "Pitch mix as fastball / breaking / offspeed", FALSE),
    downloadButton("pdf", "Download PDF report", class = "btn-primary w-100 mt-2")
  ),
  uiOutput("header"),
  layout_columns(
    col_widths = c(5, 7),
    card(section_header("Predicted next pitch"), plotOutput("prediction", height = 290),
         tableOutput("family_table"), card_footer(textOutput("pred_note"))),
    card(section_header("Pitch mix by count", textOutput("mix_note", inline = TRUE)),
         plotOutput("count_mix", height = 400))
  ),
  card(section_header("Model by count", "earlier pitches unknown, averaged over his mix"),
       tableOutput("key_counts")),
  card(section_header("Pitch locations", "catcher's view"), plotOutput("locations", height = 300)),
  layout_columns(
    col_widths = c(6, 6),
    card(section_header("Expected outcomes by pitch type"), plotOutput("xwoba", height = 320)),
    card(section_header("Arsenal vs. this side"), tableOutput("arsenal"),
         section_header("Platoon splits"), tableOutput("platoon"))
  ),
  tags$footer(class = "app-footer", textOutput("footer"))
)

server <- function(input, output, session) {
  updateSelectizeInput(session, "pitcher", choices = PITCHERS, server = TRUE,
                       selected = default_id(PITCHERS, "Paul Skenes"))
  updateSelectizeInput(session, "batter", choices = BATTERS, server = TRUE,
                       selected = default_id(BATTERS, "Shohei Ohtani"))

  ids <- reactive({
    req(input$pitcher, input$batter)
    list(p = as.integer(input$pitcher), b = as.integer(input$batter))
  })
  mu <- reactive(matchup(d, ids()$p, ids()$b))
  groups <- reactive(shown_groups(d, ids()$p, mu()$stand))

  output$prev_inputs <- renderUI({
    if (input$count == "0-0") return(helpText("First pitch of the at-bat."))
    pitch_opts <- c("Unknown (average)" = "UNKNOWN", stats::setNames(groups(), PITCH_GROUP_NAMES[groups()]))
    results <- c("UNKNOWN", possible_results(input$count))
    tagList(
      layout_columns(
        selectInput("prev1", "Previous pitch", pitch_opts),
        selectInput("prev1_result", "Its result", stats::setNames(results, RESULT_LABELS[results]))
      ),
      if (sum(as.integer(strsplit(input$count, "-")[[1]])) >= 2)
        selectInput("prev2", "Pitch before that", pitch_opts)
    )
  })

  situation <- reactive({
    list(count = input$count,
         prev1 = input$prev1 %||% "UNKNOWN", prev1_result = input$prev1_result %||% "UNKNOWN",
         prev2 = input$prev2 %||% "UNKNOWN",
         base_state = input$base_state, outs = input$outs, inning = input$inning, score = input$score,
         tto = input$tto, pitch_count = input$pitch_count, starter = input$starter)
  })
  pred <- reactive(predict_next_pitch(d, model, ids()$p, ids()$b, situation()))

  percentile_block <- function(id, side) {
    rows <- dplyr::filter(PCTL[[side]], player_id == id)
    if (!nrow(rows)) return(div(class = "pctl-note", "Not enough plate appearances for percentile rankings."))
    tagList(
      div(class = "pctl-title", sprintf("Percentile rankings, %s", paste(range(unlist(d$meta$outcome_seasons)), collapse = "-"))),
      lapply(seq_len(nrow(rows)), function(i) {
        r <- rows[i, ]
        col <- percentile_color(r$pctl)
        div(class = "pctl-row",
            div(class = "pctl-label", r$metric),
            div(class = "pctl-track",
                div(class = "pctl-fill", style = sprintf("width:%d%%;background:%s", r$pctl, col)),
                div(class = "pctl-dot", style = sprintf("left:%d%%;background:%s", r$pctl, col), r$pctl)),
            div(class = "pctl-value", r$value))
      }),
      div(class = "pctl-note", sprintf("Among %ss with %d+ PA. Red = better for this player.",
                                       side, PERCENTILE_MIN_PA))
    )
  }

  output$header <- renderUI({
    m <- mu()
    h2h <- head_to_head_summary(d, ids()$p, ids()$b)
    flags <- c(if (isTRUE(m$flags$mix_changed)) "Mix changed this season",
               if (isTRUE(m$flags$relabeled)) "Pitch relabel repaired")
    div(class = "matchup-header",
        div(class = "player-card",
            div(class = "player-role", "Pitcher"),
            div(class = "player-name", m$pitcher$full_name),
            div(class = "player-meta", sprintf("%s  ·  Throws %s  ·  %s pitches in %s", m$pitcher$team, m$p_throws,
                                               format(m$pitcher$pitches, big.mark = ","), d$meta$report_season)),
            lapply(flags, function(f) span(class = "flag-badge", f)),
            percentile_block(ids()$p, "pitcher")),
        div(class = "vs-card",
            div(class = "vs", "VS"),
            div(class = "h2h-title", "Head to head"),
            if (is.null(h2h)) div(class = "h2h-line", "No history")
            else tagList(div(class = "h2h-line", strong(sprintf("%d PA", h2h$PA)), sprintf(" (%s)", h2h$Seasons)),
                         div(class = "h2h-line", sprintf("%d H · %d HR · %d K · %d BB", h2h$H, h2h$HR, h2h$K, h2h$BB)),
                         div(class = "h2h-line", sprintf("xwOBA %s", h2h$xwOBA)))),
        div(class = "player-card batter",
            div(class = "player-role", "Batter"),
            div(class = "player-name", m$batter$full_name),
            div(class = "player-meta", sprintf("%s  ·  Bats %s  ·  hits %s-handed vs. this pitcher", m$batter$team,
                                               m$batter$bat_side, ifelse(m$stand == "L", "left", "right"))),
            percentile_block(ids()$b, "batter"))
    )
  })

  output$prediction <- renderPlot(plot_prediction(pred()), res = 96)
  output$family_table <- renderTable(family_summary(pred()), striped = TRUE, width = "100%")
  output$pred_note <- renderText({
    s <- situation()
    unknown <- s$count != "0-0" && "UNKNOWN" %in% c(s$prev1, s$prev1_result)
    paste0(d$meta$app_model, " model.",
           if (unknown) " Unknown earlier pitches are averaged over his usual mix." else "")
  })
  output$count_mix <- renderPlot(plot_count_mix(d, ids()$p, mu()$stand, input$family), res = 96)
  output$locations <- renderPlot(plot_locations(d, ids()$p, mu()$stand, input$bucket), res = 96)
  output$xwoba <- renderPlot(plot_xwoba_by_pitch(d, ids()$p, ids()$b), res = 96)
  output$arsenal <- renderTable({
    a <- arsenal_table(d, ids()$p, mu()$stand)
    a$Pitch <- pitch_dot(names(PITCH_GROUP_NAMES)[match(a$Pitch, PITCH_GROUP_NAMES)])
    a
  }, striped = TRUE, width = "100%", sanitize.text.function = identity)
  output$mix_note <- renderText(sprintf("vs. %sHB, %s", mu()$stand, d$meta$report_season))
  output$platoon <- renderTable(platoon_table(d, ids()$p, ids()$b), striped = TRUE, width = "100%")
  output$key_counts <- renderTable(key_count_table(d, model, ids()$p, ids()$b, situation()),
                                   striped = TRUE, width = "100%")
  output$pdf <- downloadHandler(
    filename = function() {
      m <- mu()
      clean <- function(x) gsub("[^A-Za-z]+", "_", x)
      sprintf("advance_report_%s_vs_%s.pdf", clean(m$pitcher$full_name), clean(m$batter$full_name))
    },
    content = function(file) {
      withProgress(message = "Building PDF", value = 0.5,
                   render_report_pdf(d, model, ids()$p, ids()$b, file, situation()))
    }
  )
  output$footer <- renderText(sprintf(
    "Statcast data through %s. Pitch mix and locations: %s regular season. xwOBA: %s. Next-pitch model trained on 2023-2025 and tested once on 2026.",
    d$meta$data_through, d$meta$report_season, paste(range(unlist(d$meta$outcome_seasons)), collapse = "-")))
}

shinyApp(ui, server)
