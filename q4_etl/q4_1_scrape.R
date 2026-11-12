# Question 4.1: Extract. Scrapes the Hacker News front pages and uses regex to


suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(readr)
  library(purrr)
  library(rvest)
})
options(readr.show_progress = FALSE)   # the progress bar prints garbage in RGui

site_url <- "https://news.ycombinator.com"
pages <- 1:3              # 30 stories per page
refresh <- FALSE          # TRUE scrapes again even if the pages were saved before
user_agent <- "ITBDA4-14 coursework ETL scraper (Eduvos student project; R robotstxt + httr + rvest)"

dir.create("data/raw_html", recursive = TRUE, showWarnings = FALSE)

# Hacker News' robots.txt asks for a 30 second crawl delay; polite_session()
# picks that up and polite_get() refuses disallowed paths. Saved pages are
# reused so the cleaning can be rerun without scraping again.
source("../shared/polite_fetch.R")
session <- NULL

fetch_page <- function(page_number) {
  path <- sprintf("data/raw_html/hn_page_%d.html", page_number)
  if (!refresh && file.exists(path)) {
    message("Using saved ", path, " (set refresh <- TRUE to scrape again)")
    return(list(html = read_html(path), scraped_at = file.mtime(path)))
  }
  if (is.null(session)) session <<- polite_session(site_url, user_agent)
  message(sprintf("Scraping page %d (waiting %s s between requests)...", page_number, session$delay))
  page <- polite_get(session, "news", query = list(p = page_number))
  xml2::write_html(page, path)
  list(html = page, scraped_at = Sys.time())
}

parse_page <- function(page, page_number, scraped_at) {
  items <- html_elements(page, "tr.athing")
  if (length(items) == 0) {
    stop("No stories found on page ", page_number, ": the Hacker News layout may have changed.", call. = FALSE)
  }

  # Each story row is followed by a row holding its points, author, age and comments.
  subtext <- xml2::xml_find_first(items, "following-sibling::tr[1]/td[contains(@class, 'subtext')]")
  title_link <- html_element(items, "span.titleline > a")
  age <- html_element(subtext, "span.age")

  comments_text <- map_chr(seq_along(subtext), \(i) {
    links <- html_text2(html_elements(subtext[[i]], "a"))
    hits <- links[str_detect(links, regex("comment|discuss", ignore_case = TRUE))]
    if (length(hits) > 0) tail(hits, 1) else NA_character_
  })

  tibble(
    item_id = html_attr(items, "id"),
    page = page_number,
    rank_text = html_text2(html_element(items, "span.rank")),
    title = html_text2(title_link),
    link = html_attr(title_link, "href"),
    site = html_text2(html_element(items, "span.sitestr")),
    points_text = html_text2(html_element(subtext, "span.score")),
    # Logged-out pages drop the "hnuser" class, so match the profile link itself.
    author = html_text2(html_element(subtext, "a.hnuser, a[href^='user?id=']")),
    age_text = html_text2(age),
    age_timestamp = html_attr(age, "title"),
    comments_text = comments_text,
    scraped_at = scraped_at
  )
}

raw_pages <- map(pages, \(p) {
  fetched <- fetch_page(p)
  parse_page(fetched$html, p, format(fetched$scraped_at, "%Y-%m-%d %H:%M:%S", tz = "UTC"))
})
raw <- bind_rows(raw_pages)

# Regex analysis: pull numbers out of the free-text fields. Anything that does
# not match stays NA here and is dealt with in 4.2.
hours_per_unit <- c(minute = 1 / 60, hour = 1, day = 24, month = 24 * 30, year = 24 * 365)

stories_raw <- raw |>
  mutate(
    rank = as.integer(str_extract(rank_text, "\\d+")),
    points = as.integer(str_match(points_text, "(\\d+)\\s*points?")[, 2]),
    comments = as.integer(str_match(comments_text, "(\\d+)[\\s\u00A0]*comments?")[, 2]),
    age_value = as.numeric(str_match(age_text, "(\\d+)\\s+(minute|hour|day|month|year)s?\\s+ago")[, 2]),
    age_unit = str_match(age_text, "(\\d+)\\s+(minute|hour|day|month|year)s?\\s+ago")[, 3],
    age_hours = round(age_value * unname(hours_per_unit[age_unit]), 2),
    # The age tooltip holds the UTC posting time, sometimes followed by a Unix timestamp.
    posted_time = str_extract(age_timestamp, "\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}"),
    posted_epoch = as.numeric(str_extract(age_timestamp, "\\d{9,}$")),
    post_prefix = str_match(title, "^(Show|Ask|Launch|Tell) HN\\b")[, 2]
  ) |>
  select(item_id, page, rank, title, link, site, author, points, comments, age_hours,
         posted_time, posted_epoch, post_prefix, rank_text, points_text, comments_text, age_text,
         age_timestamp, scraped_at)

write_csv(stories_raw, "data/hn_raw.csv", na = "")

cat(sprintf("\n== 4.1 Scraped %d records from %d pages ==\n", nrow(stories_raw), length(pages)))
print(stories_raw |> select(rank, title, site, points, comments, age_hours), n = 15, width = 120)

cat("\nData quality issues in the raw scrape:\n")
issues <- tibble(
  issue = c("Duplicate stories (same item id)", "Missing points (jobs, new posts)",
            "Missing comment count ('discuss' or none)", "Missing domain (self posts)",
            "Missing author", "Age not parsed from text"),
  records = c(sum(duplicated(stories_raw$item_id)), sum(is.na(stories_raw$points)),
              sum(is.na(stories_raw$comments)), sum(is.na(stories_raw$site)),
              sum(is.na(stories_raw$author)), sum(is.na(stories_raw$age_hours)))
)
print(issues)
cat("\nSaved raw HTML to data/raw_html/ and the raw data frame to data/hn_raw.csv\n")