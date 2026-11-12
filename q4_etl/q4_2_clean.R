# Question 4.2: Transform. Cleans, denoises and imputes the raw Hacker News
# scrape (data/hn_raw.csv from q4_1_scrape.R) and exports output/hn_clean.csv.
# Run from the q4_etl folder.

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(readr)
  library(tidyr)
  library(janitor)
})
options(readr.show_progress = FALSE)   # the progress bar prints garbage in RGui

if (!file.exists("data/hn_raw.csv")) {
  stop("data/hn_raw.csv not found. Run q4_1_scrape.R first (from the q4_etl folder).", call. = FALSE)
}
dir.create("output", showWarnings = FALSE)

raw <- read_csv("data/hn_raw.csv", col_types = cols(.default = col_character()), na = "") |>
  clean_names()

missing_profile <- function(df, stage) {
  df |>
    summarise(across(c(title, site, author, points, comments, age_hours, posted_time), \(x) sum(is.na(x)))) |>
    mutate(stage = stage, records = nrow(df), .before = 1)
}

clean_title <- function(x) {
  x |>
    str_replace_all("[\u2018\u2019]", "'") |>
    str_replace_all("[\u201C\u201D]", "\"") |>
    str_replace_all("[\u2013\u2014]", "-") |>
    str_replace_all("[\\p{Cc}\\p{Cf}]", " ") |>   # control and zero-width characters
    str_squish()
}

stories <- raw |>
  mutate(
    across(c(page, rank, points, comments), as.integer),
    across(c(age_hours, posted_epoch), as.numeric),
    scraped_at = as.POSIXct(scraped_at, tz = "UTC"),
    posted_time = na_if(posted_time, ""),
    title = clean_title(title)
  ) |>
  # Stories move down while pages are fetched 30 s apart, so the same item can
  # appear twice; keep its first (highest) position.
  arrange(rank) |>
  distinct(item_id, .keep_all = TRUE) |>
  filter(!is.na(title), nzchar(title))

profile_before <- missing_profile(raw |> mutate(across(c(points, comments, age_hours), as.numeric)), "raw")

hn_clean <- stories |>
  mutate(
    post_type = case_when(
      !is.na(post_prefix) ~ paste(post_prefix, "HN"),
      is.na(author) & is.na(points) ~ "Job",
      .default = "Story"
    ),
    # Self posts link to their own discussion page and have no external domain.
    domain = case_when(
      !is.na(site) ~ str_remove(str_to_lower(site), "^www\\."),
      str_detect(coalesce(link, ""), "^item\\?id=") ~ "news.ycombinator.com",
      .default = "unknown"
    ),
    # "discuss" means nobody has commented yet; job adverts cannot be commented on.
    comments_imputed = is.na(comments),
    comments = coalesce(comments, 0L),
    posted_at = coalesce(as.POSIXct(posted_time, format = "%Y-%m-%dT%H:%M:%S", tz = "UTC"),
                         as.POSIXct(posted_epoch, origin = "1970-01-01", tz = "UTC")),
    # Age is read from the text; the posting time in the page is the fallback.
    age_hours = coalesce(age_hours,
                         round(as.numeric(difftime(scraped_at, posted_at, units = "hours")), 2)),
    age_hours = if_else(age_hours < 0, NA_real_, age_hours),
    age_band = cut(age_hours, breaks = c(0, 3, 8, 16, Inf), include.lowest = TRUE,
                   labels = c("0-3 h", "3-8 h", "8-16 h", "16 h+"))
  ) |>
  # Missing points (job adverts) are imputed with the median of stories of a
  # similar age, since points accumulate over time; the flag keeps them separable.
  group_by(age_band) |>
  mutate(points_imputed = is.na(points),
         points = coalesce(points, as.integer(round(median(points, na.rm = TRUE))))) |>
  ungroup() |>
  mutate(
    points = coalesce(points, as.integer(round(median(points, na.rm = TRUE)))),
    author = coalesce(author, "(none)"),
    points_per_hour = round(points / pmax(age_hours, 1), 2),
    title_words = str_count(title, "\\S+")
  ) |>
  select(item_id, rank, page, title, post_type, domain, author, points, points_imputed,
         comments, comments_imputed, age_hours, age_band, posted_at, points_per_hour,
         title_words, scraped_at)

profile_after <- hn_clean |>
  mutate(site = domain, posted_time = format(posted_at)) |>
  missing_profile("clean")

write_csv(hn_clean, "output/hn_clean.csv", na = "")

cat(sprintf("\n== 4.2 Cleaned %d raw records into %d stories ==\n", nrow(raw), nrow(hn_clean)))
cat(sprintf("Duplicates removed: %d | points imputed: %d | comment counts filled: %d\n",
            nrow(raw) - nrow(hn_clean), sum(hn_clean$points_imputed), sum(hn_clean$comments_imputed)))
cat("\nMissing values per column before and after cleaning:\n")
print(bind_rows(profile_before, profile_after))
cat("\nStories by post type:\n")
print(count(hn_clean, post_type, sort = TRUE))
cat("\nNumeric summary:\n")
print(summary(select(hn_clean, points, comments, age_hours, points_per_hour)))
cat("\nSaved output/hn_clean.csv\n")