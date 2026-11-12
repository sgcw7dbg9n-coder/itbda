# Polite web requests for Q3 and Q4: check robots.txt before fetching, identify
# the scraper with a user agent, honour the site's crawl delay and wait between
# requests. This replaces the 'polite' package (archived from CRAN in 2026)
# with robotstxt and httr.

suppressPackageStartupMessages({
  library(robotstxt)
  library(httr)
  library(rvest)
})

polite_session <- function(base_url, user_agent, min_delay = 5, rules = NULL) {
  parts <- parse_url(base_url)
  host <- if (is.null(parts$port)) parts$hostname else paste0(parts$hostname, ":", parts$port)
  if (is.null(rules)) rules <- robotstxt(domain = host)

  delays <- rules$crawl_delay
  site_delay <- suppressWarnings(as.numeric(delays$value[delays$useragent == "*"]))
  state <- new.env()
  state$last_request <- NULL

  list(
    scheme = parts$scheme,
    host = host,
    user_agent = user_agent,
    rules = rules,
    delay = max(c(min_delay, site_delay), na.rm = TRUE),
    state = state
  )
}

polite_get <- function(session, path = "", query = NULL) {
  path <- sub("^/", "", path)
  if (!isTRUE(session$rules$check(paths = paste0("/", path), bot = "*"))) {
    stop("robots.txt on ", session$host, " does not allow scraping /", path, call. = FALSE)
  }

  if (!is.null(session$state$last_request)) {
    waited <- as.numeric(difftime(Sys.time(), session$state$last_request, units = "secs"))
    if (waited < session$delay) Sys.sleep(session$delay - waited)
  }

  url <- sprintf("%s://%s/%s", session$scheme, session$host, path)
  response <- GET(url, query = query, user_agent(session$user_agent), timeout(60))
  session$state$last_request <- Sys.time()
  stop_for_status(response, task = paste("download", url))
  read_html(content(response, as = "text", encoding = "UTF-8"))
}
