# Question 4.3: Load and analyse. Creates the hn_stories table in PostgreSQL,
# imports output/hn_clean.csv and runs the two SQL investigations in
# sql/03_analysis.sql. Start the local server first (postgres/start_postgres.bat).
# Connection settings come from the standard PG* environment variables.
# Run from the q4_etl folder.

suppressPackageStartupMessages({
  library(DBI)
  library(RPostgres)
  library(readr)
  library(dplyr)
  library(stringr)
})

if (!file.exists("output/hn_clean.csv")) {
  stop("output/hn_clean.csv not found. Run q4_2_clean.R first (from the q4_etl folder).", call. = FALSE)
}

con <- tryCatch(
  dbConnect(
    Postgres(),
    host = Sys.getenv("PGHOST", "localhost"),
    port = as.integer(Sys.getenv("PGPORT", "5432")),
    user = Sys.getenv("PGUSER", "postgres"),
    password = Sys.getenv("PGPASSWORD", ""),
    dbname = Sys.getenv("PGDATABASE", "itbda"),
    bigint = "integer"
  ),
  error = \(e) stop("Could not connect to PostgreSQL. Start it with postgres\\start_postgres.bat, then retry.\n",
                    conditionMessage(e), call. = FALSE)
)
on.exit(dbDisconnect(con), add = TRUE)

# Splits a .sql file into statements, keeping each statement's leading comment
# block as its description.
read_sql_statements <- function(path) {
  chunks <- str_split(paste(readLines(path, warn = FALSE), collapse = "\n"), ";\\s*(\n|$)")[[1]]
  chunks <- chunks[str_detect(chunks, "[A-Za-z]")]
  lapply(chunks, \(chunk) {
    lines <- str_split(chunk, "\n")[[1]]
    is_comment <- str_detect(lines, "^\\s*--")
    list(description = str_trim(str_remove(lines[is_comment], "^\\s*--\\s?")),
         sql = str_trim(paste(lines[!is_comment], collapse = "\n")))
  }) |>
    Filter(f = \(s) nzchar(s$sql))
}

# Load ------------------------------------------------------------------------
for (statement in read_sql_statements("sql/01_create_table.sql")) dbExecute(con, statement$sql)

hn_clean <- read_csv("output/hn_clean.csv", show_col_types = FALSE, na = "",
                     col_types = cols(item_id = col_double(), age_band = col_character()))
loaded <- dbAppendTable(con, "hn_stories", hn_clean)

cat(sprintf("\n== 4.3 Loaded %d rows into hn_stories ==\n", loaded))
print(dbGetQuery(con, "
  SELECT column_name, data_type
  FROM information_schema.columns
  WHERE table_name = 'hn_stories'
  ORDER BY ordinal_position"))

# Analyse ---------------------------------------------------------------------
dir.create("output", showWarnings = FALSE)
investigations <- read_sql_statements("sql/03_analysis.sql")

for (i in seq_along(investigations)) {
  query <- investigations[[i]]
  result <- dbGetQuery(con, query$sql)
  cat(sprintf("\n%s\n", paste(query$description, collapse = "\n")))
  cat(query$sql, "\n\n")
  print(as_tibble(result), n = Inf, width = 140)
  write_csv(result, sprintf("output/q4_investigation_%d.csv", i))
}

cat("\nSaved query results to output/q4_investigation_*.csv\n")
