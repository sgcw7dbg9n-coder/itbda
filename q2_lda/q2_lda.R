# Question 2: topic modelling of the SA news corpus (news.zip) with LDA.
# Run from the q2_lda folder (open q2_lda.Rproj in RStudio). Tables and charts
# are written to output/.

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(readr)
  library(tidytext)
  library(textstem)
  library(topicmodels)
  library(ggplot2)
  library(ggwordcloud)
})

if (!file.exists("data/news.zip")) {
  stop("Run this from the q2_lda folder (open q2_lda.Rproj in RStudio).", call. = FALSE)
}

n_topics <- 4L               # n: topics in the final model (see the diagnostics chart)
top_k <- 10L                 # k: words reported per topic
candidate_topics <- 2:8      # values of n compared in the diagnostics
seed <- 2026L

dir.create("output", showWarnings = FALSE)
theme_set(theme_minimal(base_size = 11))


# 2.1 Data frame (file_name, content) and denoising --------------------------

news_dir <- file.path(tempdir(), "news")
unzip("data/news.zip", exdir = news_dir)
files <- list.files(news_dir, pattern = "\\.txt$", recursive = TRUE, full.names = TRUE)
files <- files[!grepl("__MACOSX", files, fixed = TRUE) & !startsWith(basename(files), "._")]
files <- files[order(as.integer(str_extract(basename(files), "\\d+")))]

read_article <- function(path) {
  paste(readLines(path, encoding = "UTF-8", warn = FALSE), collapse = "\n")
}

news <- tibble(
  file_name = basename(files),
  content = vapply(files, read_article, character(1), USE.NAMES = FALSE)
)

dateline <- "(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday), [A-Z][a-z]+ \\d{1,2}, \\d{4}"

denoise <- function(text) {
  text |>
    str_replace_all("[\u2018\u2019\u201B\u2032]", "'") |>
    str_replace_all("[\u201C\u201D]", "\"") |>
    str_replace_all("[\u2013\u2014\u00A0]", " ") |>
    str_remove_all(regex(paste0("^\\s*", dateline, "\\s*$"), multiline = TRUE)) |>
    str_remove_all("[\u2013-]?\\s*SAnews\\.gov\\.za") |>
    str_remove_all("https?://\\S+|www\\.\\S+|\\S+@\\S+") |>
    str_remove_all("\\(\\s*[A-Z]{2,}\\s*\\)") |>   # acronym echoes such as "(PSC)"
    str_remove_all("'s\\b") |>
    str_to_lower() |>
    str_replace_all("[^a-z\\s]", " ") |>
    str_squish()
}

# Reporting verbs and filler that appear in every government news release.
domain_stopwords <- c(
  "say", "said", "says", "also", "will", "can", "must", "one", "two", "three",
  "today", "week", "year", "mr", "ms", "minister", "south", "african", "africa",
  "include", "provide", "ensure", "continue",
  tolower(month.name), c("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")
)

news <- news |>
  mutate(
    title = str_squish(str_extract(content, "^[^\n]+")),
    published = as.Date(str_extract(content, dateline), format = "%A, %B %d, %Y"),
    denoised = denoise(content)
  )

tokens <- news |>
  select(file_name, denoised) |>
  unnest_tokens(word, denoised) |>
  anti_join(stop_words, by = "word") |>
  mutate(word = lemmatize_words(word)) |>
  filter(nchar(word) >= 3, !word %in% domain_stopwords, !word %in% stop_words$word)

news <- news |>
  left_join(
    tokens |> group_by(file_name) |> summarise(clean_content = paste(word, collapse = " "), clean_tokens = n()),
    by = "file_name"
  ) |>
  mutate(raw_tokens = str_count(content, "\\S+")) |>
  select(file_name, content, title, published, clean_content, raw_tokens, clean_tokens)

write_csv(news, "output/q2_news_dataframe.csv")

cat("\n== 2.1 News data frame ==\n")
print(news |> select(file_name, title, published, raw_tokens, clean_tokens), n = Inf, width = 120)
cat(sprintf("\nTokens: %d raw -> %d after denoising (%.0f%% removed)\n",
            sum(news$raw_tokens), sum(news$clean_tokens),
            100 * (1 - sum(news$clean_tokens) / sum(news$raw_tokens))))


# 2.2 LDA: top n topics and top k words per topic ---------------------------

# Words used only once in the whole corpus carry no co-occurrence signal.
term_counts <- tokens |> count(file_name, word)
kept_terms <- term_counts |> group_by(word) |> filter(sum(n) >= 2) |> ungroup()
dtm <- cast_dtm(kept_terms, file_name, word, n)
cat(sprintf("\nDocument-term matrix: %d documents x %d terms\n", nrow(dtm), ncol(dtm)))

fit_lda <- function(k, run_seed = seed) {
  LDA(dtm, k = k, method = "Gibbs",
      control = list(seed = run_seed, burnin = 1000, iter = 2000, thin = 100))
}

# UMass coherence: do a topic's top words actually occur in the same documents?
umass_coherence <- function(model, top_n = top_k) {
  present <- as.matrix(dtm) > 0
  top_terms <- terms(model, top_n)
  scores <- apply(top_terms, 2, function(words) {
    pairs <- combn(seq_along(words), 2)
    mean(apply(pairs, 2, function(ij) {
      wi <- words[max(ij)]
      wj <- words[min(ij)]
      log((sum(present[, wi] & present[, wj]) + 1) / sum(present[, wj]))
    }))
  })
  mean(scores)
}

# CaoJuan2009: mean cosine similarity between topics; lower means more distinct topics.
topic_similarity <- function(model) {
  beta <- exp(model@beta)
  beta <- beta / sqrt(rowSums(beta^2))
  similarity <- tcrossprod(beta)
  mean(similarity[upper.tri(similarity)])
}

# Coherence and topic overlap for each candidate n, averaged over several Gibbs
# runs because a single run on ten documents is noisy. With so few documents
# neither metric has a clean optimum, so n is set above and this table backs it.
selection_seeds <- seed + 0:4
selection <- expand_grid(n = candidate_topics, run_seed = selection_seeds) |>
  mutate(model = mapply(fit_lda, n, run_seed, SIMPLIFY = FALSE),
         coherence = vapply(model, umass_coherence, numeric(1)),
         similarity = vapply(model, topic_similarity, numeric(1))) |>
  group_by(n) |>
  summarise(coherence = mean(coherence), similarity = mean(similarity))

cat(sprintf("\nTopic-number diagnostics, mean of %d runs per n\n", length(selection_seeds)))
cat("(coherence: higher is better, similarity: lower is better)\n")
print(selection |> mutate(used = if_else(n == n_topics, "<- used", "")), n = Inf)

lda <- fit_lda(n_topics)

topic_words <- tidy(lda, matrix = "beta")
doc_topics <- tidy(lda, matrix = "gamma")

top_terms <- topic_words |>
  group_by(topic) |>
  slice_max(beta, n = top_k, with_ties = FALSE) |>
  mutate(rank = row_number(), cumulative_beta = cumsum(beta)) |>
  ungroup()

topic_labels <- top_terms |>
  filter(rank <= 3) |>
  group_by(topic) |>
  summarise(label = paste0("Topic ", first(topic), ": ", paste(term, collapse = ", ")))

topic_summary <- topic_words |>
  group_by(topic) |>
  summarise(entropy_bits = -sum(beta * log2(beta))) |>
  left_join(top_terms |> group_by(topic) |> summarise(top_k_mass = sum(beta)), by = "topic") |>
  left_join(doc_topics |> group_by(topic) |> summarise(prevalence = mean(gamma)), by = "topic") |>
  left_join(
    doc_topics |> group_by(document) |> slice_max(gamma, n = 1) |> ungroup() |>
      group_by(topic) |> summarise(dominant_in = paste(document, collapse = ", ")),
    by = "topic"
  ) |>
  left_join(topic_labels, by = "topic") |>
  arrange(desc(prevalence)) |>
  mutate(prevalence_rank = row_number())

write_csv(top_terms, "output/q2_top_terms_per_topic.csv")
write_csv(doc_topics |> pivot_wider(names_from = topic, values_from = gamma, names_prefix = "topic_"),
          "output/q2_document_topic_distribution.csv")
write_csv(topic_summary, "output/q2_topic_summary.csv")

cat(sprintf("\n== 2.2 LDA with n = %d topics, top k = %d words ==\n", n_topics, top_k))
for (t in topic_summary$topic) {
  s <- filter(topic_summary, topic == t)
  cat(sprintf("\n%s\n  prevalence %.1f%% of corpus | top-%d words hold %.1f%% of the topic | entropy %.2f bits\n  dominant in: %s\n",
              s$label, 100 * s$prevalence, top_k, 100 * s$top_k_mass, s$entropy_bits,
              coalesce(s$dominant_in, "no document")))
  words <- filter(top_terms, topic == t)
  cat(sprintf("  %2d. %-16s %.4f\n", words$rank, words$term, words$beta), sep = "")
}


# 2.3 Visualisations --------------------------------------------------------

label_lookup <- setNames(topic_labels$label, topic_labels$topic)

selection_plot <- selection |>
  select(n, coherence, similarity) |>
  pivot_longer(-n, names_to = "metric") |>
  mutate(metric = recode(metric,
    coherence = "Coherence (UMass): higher is better",
    similarity = "Topic overlap (mean cosine similarity): lower is better")) |>
  ggplot(aes(n, value)) +
  geom_line(colour = "grey50") +
  geom_point(aes(colour = n == n_topics), size = 3, show.legend = FALSE) +
  scale_colour_manual(values = c(`TRUE` = "#D85A30", `FALSE` = "grey40")) +
  scale_x_continuous(breaks = candidate_topics) +
  facet_wrap(~ metric, scales = "free_y") +
  labs(title = "Choosing the number of LDA topics",
       subtitle = sprintf("Mean of %d Gibbs runs per n; the final model uses n = %d (highlighted)",
                         length(selection_seeds), n_topics),
       x = "Number of topics (n)", y = "Metric value")
ggsave("output/fig_q2_topic_selection.png", selection_plot, width = 10, height = 4, dpi = 200, bg = "white")

bar_plot <- top_terms |>
  mutate(term = reorder_within(term, beta, topic)) |>
  ggplot(aes(beta, term, fill = factor(topic))) +
  geom_col(show.legend = FALSE) +
  facet_wrap(~ topic, scales = "free_y", labeller = as_labeller(label_lookup)) +
  scale_y_reordered() +
  labs(title = sprintf("Top %d words per topic (LDA, n = %d)", top_k, n_topics),
       subtitle = "Bar length is the word's probability within the topic (beta)",
       x = "Word probability within topic (beta)", y = NULL)
ggsave("output/fig_q2_top_words_bar.png", bar_plot, width = 11, height = 7, dpi = 200, bg = "white")

cloud_plot <- topic_words |>
  group_by(topic) |>
  slice_max(beta, n = 30, with_ties = FALSE) |>
  ungroup() |>
  ggplot(aes(label = term, size = beta, colour = beta)) +
  geom_text_wordcloud_area(seed = seed, rm_outside = TRUE) +
  scale_size_area(max_size = 22) +
  scale_colour_gradient(low = "#85B7EB", high = "#0C447C") +
  facet_wrap(~ topic, labeller = as_labeller(label_lookup)) +
  labs(title = "Word clouds of the 30 most probable words per topic",
       subtitle = "Word size and colour scale with the word's probability within the topic (beta)")
ggsave("output/fig_q2_topic_wordclouds.png", cloud_plot, width = 11, height = 7, dpi = 200, bg = "white")

heatmap_plot <- doc_topics |>
  left_join(news |> select(document = file_name, title), by = "document") |>
  mutate(document = factor(document, levels = rev(news$file_name)),
         topic = factor(topic, labels = label_lookup[as.character(sort(unique(topic)))])) |>
  ggplot(aes(topic, document, fill = gamma)) +
  geom_tile(colour = "white") +
  geom_text(aes(label = sprintf("%.2f", gamma)), size = 3) +
  scale_fill_gradient(low = "#F1EFE8", high = "#D85A30", limits = c(0, 1)) +
  scale_x_discrete(labels = function(x) str_wrap(x, 18)) +
  labs(title = "Topic mix of each news article",
       subtitle = "Share of each document assigned to each topic (gamma)",
       x = NULL, y = "Document", fill = "Gamma")
ggsave("output/fig_q2_document_topic_heatmap.png", heatmap_plot, width = 10, height = 6, dpi = 200, bg = "white")

cat("\nSaved tables and charts to output/\n")
