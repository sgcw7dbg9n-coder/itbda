# Question 3: WebText API proof of concept. Reads a web page from its link,
# extracts the clean article text into an R data structure, preprocesses it and
# summarises it with two extractive techniques (word frequency and TextRank).
# Run from the q3_webtext folder (open q3_webtext.Rproj in RStudio).

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(readr)
  library(purrr)
  library(rvest)
  library(tidytext)
  library(textstem)
  library(igraph)
  library(ggraph)
  library(ggplot2)
  library(wordcloud)
})
options(readr.show_progress = FALSE)   # the progress bar prints garbage in RGui

page_url <- "https://en.wikipedia.org/wiki/South_African_energy_crisis"
summary_length <- 8L      # sentences per summary
max_per_section <- 2L     # keeps one long section from taking over the summary
min_summary_words <- 12L  # very short sentences rarely stand alone in a summary
refresh <- FALSE          # TRUE downloads the page again even if a snapshot exists
user_agent <- "ITBDA4-14 coursework text-mining scraper (Eduvos student project; R robotstxt + httr + rvest)"

snapshot_file <- "data/page_snapshot.html"
dir.create("data", showWarnings = FALSE)
dir.create("output", showWarnings = FALSE)
theme_set(theme_minimal(base_size = 11))


# 3.1 Extract clean web text into an R data structure ------------------------

# polite_session() reads robots.txt and the site's crawl delay; polite_get()
# refuses disallowed paths, sends the user agent and waits between requests.
source("../shared/polite_fetch.R")

fetch_page <- function(url) {
  session <- polite_session(url, user_agent)
  polite_get(session, parse_url(url)$path)
}

if (refresh || !file.exists(snapshot_file)) {
  message("Downloading ", page_url)
  page <- fetch_page(page_url)
  xml2::write_html(page, snapshot_file)
  retrieved <- Sys.time()
} else {
  message("Using saved snapshot ", snapshot_file, " (set refresh <- TRUE to download again)")
  page <- read_html(snapshot_file)
  retrieved <- file.mtime(snapshot_file)
}

non_article_sections <- c("see also", "references", "notes", "citations", "sources", "footnotes",
                          "bibliography", "further reading", "external links", "external videos", "gallery")

extract_article <- function(page) {
  content <- html_element(page, "#mw-content-text")
  if (inherits(content, "xml_missing")) {
    stop("Page layout not recognised: no '#mw-content-text' block found.", call. = FALSE)
  }

  # Footnote markers, edit links, styles and hidden maintenance text are page
  # furniture, not article content.
  xml2::xml_remove(html_elements(content, paste(
    "sup.reference", "sup.noprint", "span.mw-editsection", "style",
    ".noprint", ".mw-empty-elt", ".mwe-math-mathml-inline", sep = ", "
  )))

  # Paragraphs and headings in document order, at any depth: current Wikipedia
  # pages wrap each section in <section>, older ones put <p> directly under
  # .mw-parser-output. Paragraphs inside tables, figures, infoboxes and
  # navigation boxes are captions or side notes, not running text. Classes are
  # matched as whole tokens and only on elements inside the article body,
  # because the page's <html> and <body> classes contain words like "sidebar".
  has_class <- function(cls) sprintf("contains(concat(' ', normalize-space(@class), ' '), ' %s ')", cls)
  side_content <- paste(vapply(c("infobox", "navbox", "sidebar", "thumb", "reflist", "hatnote"),
                               has_class, character(1)), collapse = " or ")
  nodes <- html_elements(content, xpath = paste0(
    ".//p[not(ancestor::table) and not(ancestor::figure) and ",
    "not(ancestor::*[ancestor::*[@id = 'mw-content-text']][", side_content, "])]",
    " | .//h2 | .//h3"
  ))

  blocks <- tibble(tag = xml2::xml_name(nodes), text = str_squish(html_text2(nodes))) |>
    mutate(
      section = if_else(tag == "h2", text, NA_character_),
      subsection = case_when(tag == "h2" ~ "", tag == "h3" ~ text, .default = NA_character_)
    ) |>
    fill(section, subsection) |>
    mutate(section = coalesce(section, "Introduction"), subsection = coalesce(subsection, ""))

  blocks |>
    filter(tag == "p", nzchar(text), !str_to_lower(section) %in% non_article_sections) |>
    transmute(paragraph_id = row_number(), section, subsection, text,
              words = str_count(text, "\\S+"))
}

article <- list(
  url = page_url,
  title = html_text2(html_element(page, "h1")),
  retrieved = format(retrieved, "%Y-%m-%d %H:%M"),
  licence = "Wikipedia text, CC BY-SA 4.0",
  paragraphs = extract_article(page)
)

if (nrow(article$paragraphs) == 0) stop("No article paragraphs were extracted.", call. = FALSE)

saveRDS(article, "output/q3_article.rds")
write_csv(article$paragraphs, "output/q3_paragraphs.csv")

cat(sprintf("\n== 3.1 %s ==\n%s (retrieved %s)\n%d paragraphs, %d words across %d sections\n",
            article$title, article$url, article$retrieved, nrow(article$paragraphs),
            sum(article$paragraphs$words), n_distinct(article$paragraphs$section)))
print(count(article$paragraphs, section, name = "paragraphs"), n = Inf)
str(article, max.level = 1)


# 3.2 Text preprocessing ------------------------------------------------------

# Abbreviations whose full stops would otherwise end a sentence.
protect_abbreviations <- function(text) {
  text |>
    str_replace_all("\\be\\.g\\.", "eg") |>
    str_replace_all("\\bi\\.e\\.", "ie") |>
    str_replace_all("\\b(approx|est|vs|no|mr|ms|dr|prof)\\.(?=\\s)", "\\1") |>
    str_replace_all("\\b([A-Z])\\.([A-Z])\\.", "\\1\\2")
}

clean_display_text <- function(text) {
  text |>
    str_remove_all("\\[(\\d+|[a-z]|citation needed|note \\d+|clarification needed|when\\?|who\\?)\\]") |>
    str_replace_all("[\u2018\u2019]", "'") |>
    str_replace_all("[\u201C\u201D]", "\"") |>
    str_replace_all("[\u2013\u2014]", " - ") |>
    str_replace_all("\u00A0", " ") |>
    str_remove_all("https?://\\S+") |>
    str_squish()
}

sentences <- article$paragraphs |>
  mutate(text = protect_abbreviations(clean_display_text(text))) |>
  unnest_tokens(sentence, text, token = "sentences", to_lower = FALSE) |>
  mutate(sentence = str_squish(sentence), words = str_count(sentence, "\\S+")) |>
  # Fragments such as table lead-ins ("Below is a timeline of ...") and captions
  # are short or have no closing punctuation; they are not sentences to summarise.
  filter(words >= 6, str_detect(sentence, "[.!?][\"')\\]]*$")) |>
  distinct(sentence, .keep_all = TRUE) |>
  mutate(sentence_id = row_number(), position = sentence_id / n())

# The article's own subject words appear in most sentences and would dominate
# the frequency scores without telling the reader anything.
custom_stopwords <- c("also", "include", "including", "however", "although", "per", "cent",
                      "percent", "south", "africa", "african")

sentence_tokens <- sentences |>
  select(sentence_id, sentence) |>
  mutate(sentence = str_to_lower(sentence) |>
           str_replace_all("'s\\b", "") |>
           str_replace_all("[^a-z\\s]", " ")) |>
  unnest_tokens(word, sentence) |>
  anti_join(stop_words, by = "word") |>
  mutate(word = lemmatize_words(word)) |>
  filter(nchar(word) >= 3, !word %in% stop_words$word, !word %in% custom_stopwords)

sentences <- sentences |>
  left_join(sentence_tokens |> group_by(sentence_id) |>
              summarise(clean_text = paste(word, collapse = " "), content_words = n()),
            by = "sentence_id") |>
  filter(!is.na(clean_text))

write_csv(sentences, "output/q3_sentences_clean.csv")

cat(sprintf("\n== 3.2 Preprocessing ==\n%d sentences kept; %d raw words -> %d content words after cleaning\n",
            nrow(sentences), sum(article$paragraphs$words), nrow(sentence_tokens)))


# 3.3 Summarisation -----------------------------------------------------------

# Greedy pick of the highest-scoring sentences. A candidate is skipped if it is
# too short, repeats an already chosen sentence (cosine similarity above
# max_overlap) or its section already has max_per_section sentences.
pick_sentences <- function(scores, similarity, n, max_overlap = 0.5) {
  eligible <- sentences$words >= min_summary_words
  chosen <- integer()
  for (i in order(scores, decreasing = TRUE)) {
    if (length(chosen) == n) break
    if (!eligible[i]) next
    if (sum(sentences$section[chosen] == sentences$section[i]) >= max_per_section) next
    if (length(chosen) == 0 || max(similarity[i, chosen]) <= max_overlap) chosen <- c(chosen, i)
  }
  sort(chosen)
}

# Sentence-by-term TF-IDF matrix with unit-length rows, so the cross product
# gives cosine similarity between sentences.
tfidf <- sentence_tokens |>
  filter(sentence_id %in% sentences$sentence_id) |>
  count(sentence_id, word) |>
  bind_tf_idf(word, sentence_id, n)
tfidf_matrix <- tfidf |>
  cast_sparse(sentence_id, word, tf_idf) |>
  as.matrix()
tfidf_matrix <- tfidf_matrix[as.character(sentences$sentence_id), , drop = FALSE]
tfidf_matrix <- tfidf_matrix / pmax(sqrt(rowSums(tfidf_matrix^2)), 1e-12)
similarity <- tcrossprod(tfidf_matrix)
diag(similarity) <- 0

# Technique 1: word-frequency scoring (Luhn). A sentence scores the average
# normalised corpus frequency of its content words.
word_freq <- sentence_tokens |> count(word, sort = TRUE) |> mutate(weight = n / max(n))
frequency_scores <- sentence_tokens |>
  inner_join(word_freq |> select(word, weight), by = "word") |>
  group_by(sentence_id) |>
  summarise(score = mean(weight)) |>
  right_join(sentences |> select(sentence_id), by = "sentence_id") |>
  arrange(sentence_id) |>
  pull(score) |>
  coalesce(0)

# Technique 2: TextRank. Sentences are nodes, edges are weighted by TF-IDF
# cosine similarity, and PageRank scores how central each sentence is.
edge_threshold <- 0.05
graph <- graph_from_adjacency_matrix(similarity * (similarity > edge_threshold),
                                     mode = "undirected", weighted = TRUE, diag = FALSE)
textrank_scores <- page_rank(graph, weights = E(graph)$weight)$vector

summaries <- list(
  frequency = pick_sentences(frequency_scores, similarity, summary_length),
  textrank = pick_sentences(textrank_scores, similarity, summary_length)
)

sentences <- sentences |>
  mutate(frequency_score = frequency_scores,
         textrank_score = textrank_scores,
         in_frequency_summary = row_number() %in% summaries$frequency,
         in_textrank_summary = row_number() %in% summaries$textrank)
write_csv(sentences, "output/q3_sentence_scores.csv")

format_summary <- function(rows, method) {
  picked <- sentences[rows, ]
  c(sprintf("# %s summary of \"%s\"", method, article$title),
    sprintf("Source: %s (retrieved %s)", article$url, article$retrieved),
    sprintf("%d of %d sentences, %d of %d words (%.1f%% of the article)",
            nrow(picked), nrow(sentences), sum(picked$words), sum(sentences$words),
            100 * sum(picked$words) / sum(sentences$words)),
    "",
    sprintf("- [%s] %s", picked$section, picked$sentence))
}

frequency_summary <- format_summary(summaries$frequency, "Word-frequency")
textrank_summary <- format_summary(summaries$textrank, "TextRank")
writeLines(frequency_summary, "output/q3_summary_word_frequency.md")
writeLines(textrank_summary, "output/q3_summary_textrank.md")

shared <- intersect(summaries$frequency, summaries$textrank)
comparison <- tibble(
  method = c("Word frequency", "TextRank"),
  n_sentences = lengths(summaries),
  words = c(sum(sentences$words[summaries$frequency]), sum(sentences$words[summaries$textrank])),
  sections_covered = c(n_distinct(sentences$section[summaries$frequency]),
                       n_distinct(sentences$section[summaries$textrank])),
  shared_with_other = length(shared)
) |>
  mutate(compression_pct = round(100 * words / sum(sentences$words), 1))
write_csv(comparison, "output/q3_summary_comparison.csv")

cat("\n== 3.3 Summaries ==\n")
cat(frequency_summary, sep = "\n")
cat("\n")
cat(textrank_summary, sep = "\n")
cat(sprintf("\nThe two summaries share %d sentence(s); Jaccard overlap %.2f\n",
            length(shared), length(shared) / length(union(summaries$frequency, summaries$textrank))))
print(comparison)


# Visualisations --------------------------------------------------------------

caption <- sprintf("Source: %s, retrieved %s", article$url, article$retrieved)

top_words_plot <- word_freq |>
  slice_max(n, n = 20, with_ties = FALSE) |>
  ggplot(aes(n, reorder(word, n))) +
  geom_col(fill = "#378ADD") +
  labs(title = sprintf("Most frequent content words in \"%s\"", article$title),
       subtitle = "After removing stop words and lemmatising; these weights drive the word-frequency summary",
       x = "Occurrences in the article", y = NULL, caption = caption)
ggsave("output/fig_q3_top_words.png", top_words_plot, width = 9, height = 6, dpi = 200, bg = "white")

png("output/fig_q3_wordcloud.png", width = 1800, height = 1400, res = 200)
par(mar = c(2, 0, 3, 0))
set.seed(2026)
wordcloud(word_freq$word, word_freq$n, max.words = 120, min.freq = 2, random.order = FALSE,
          rot.per = 0.15, colors = c("#85B7EB", "#378ADD", "#185FA5", "#0C447C"))
title(main = sprintf("Word cloud of \"%s\" (top 120 content words)", article$title),
      sub = "Word size is proportional to frequency in the article")
invisible(dev.off())

score_plot <- sentences |>
  select(sentence_id, position, section,
         `Word frequency` = frequency_score, TextRank = textrank_score,
         in_frequency_summary, in_textrank_summary) |>
  pivot_longer(c(`Word frequency`, TextRank), names_to = "method", values_to = "score") |>
  group_by(method) |>
  mutate(score = score / max(score),
         selected = if_else(method == "TextRank", in_textrank_summary, in_frequency_summary)) |>
  ungroup() |>
  ggplot(aes(sentence_id, score)) +
  geom_segment(aes(xend = sentence_id, yend = 0), colour = "grey80") +
  geom_point(aes(colour = selected, size = selected)) +
  scale_colour_manual(values = c(`TRUE` = "#D85A30", `FALSE` = "grey55"),
                      labels = c(`TRUE` = "In summary", `FALSE` = "Not selected")) +
  scale_size_manual(values = c(`TRUE` = 2.8, `FALSE` = 1.2), guide = "none") +
  facet_wrap(~ method, ncol = 1) +
  labs(title = "Where each summary's sentences come from",
       subtitle = sprintf("Scores scaled to the best sentence; highlighted: the %d sentences chosen (at most %d per section, no near-duplicates)",
                          summary_length, max_per_section),
       x = "Sentence number in the article", y = "Relative sentence score", colour = NULL,
       caption = caption) +
  theme(legend.position = "top")
ggsave("output/fig_q3_sentence_scores.png", score_plot, width = 10, height = 6, dpi = 200, bg = "white")

V(graph)$textrank <- textrank_scores
V(graph)$selected <- seq_len(vcount(graph)) %in% summaries$textrank
V(graph)$label <- if_else(V(graph)$selected, as.character(seq_len(vcount(graph))), "")
network_plot <- ggraph(graph, layout = "fr") +
  geom_edge_link(aes(alpha = weight), colour = "grey60", show.legend = FALSE) +
  geom_node_point(aes(size = textrank, colour = selected)) +
  geom_node_text(aes(label = label), repel = TRUE, size = 3.2) +
  scale_colour_manual(values = c(`TRUE` = "#D85A30", `FALSE` = "#85B7EB"),
                      labels = c(`TRUE` = "In TextRank summary", `FALSE` = "Other sentence")) +
  scale_size_continuous(range = c(1, 7)) +
  labs(title = "TextRank sentence similarity network",
       subtitle = sprintf("Nodes are sentences, edges link sentences with TF-IDF cosine similarity above %.2f; labels are sentence numbers",
                          edge_threshold),
       size = "PageRank score", colour = NULL, caption = caption) +
  theme_void(base_size = 11) +
  theme(plot.margin = margin(10, 10, 10, 10))
ggsave("output/fig_q3_textrank_network.png", network_plot, width = 10, height = 8, dpi = 200, bg = "white")

cat("\nSaved data, summaries and charts to output/\n")
