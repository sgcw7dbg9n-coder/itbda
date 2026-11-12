# ITBDA4-14 Project 2: R implementation

All four questions are written in R and run from the `r-env` conda environment.

```
ITBDA-Project2/
  environment.yml          conda packages for every question
  open_rstudio.bat         opens RStudio with the conda R (not needed with a normal R install)
  shared/polite_fetch.R    robots.txt check, user agent and crawl delay for the scrapers
  q1_mapreduce/            Q1 MapReduce keyword search (Hadoop Streaming style)
  q2_lda/                  Q2 news data frame, denoising, LDA, charts
  q3_webtext/              Q3 web text extraction, preprocessing, summaries
  q4_etl/                  Q4 scrape, clean, CSV, PostgreSQL, SQL analysis
```

Each question folder has its own `.Rproj`. Open that project in RStudio (or `cd`
into the folder for `Rscript`) so the relative paths resolve.


## 1. One-time setup

**With a normal R install (recommended):** in the R console or RStudio run

```r
install.packages(c(
  "tidyverse", "tm", "topicmodels", "tidytext", "reshape2", "textstem",
  "wordcloud", "ggwordcloud", "robotstxt", "igraph", "ggraph", "janitor",
  "DBI", "RPostgres"
), repos = "https://cloud.r-project.org")
```

RStudio finds this R by itself; open a question by double-clicking its `.Rproj`.
PostgreSQL for Q4 still comes from conda: `conda activate r-env` then
`conda install -c conda-forge postgresql`.

**With the conda R instead:** add the packages to the environment

```
conda activate r-env
conda install -c conda-forge --override-channels r-tm r-topicmodels r-tidytext r-reshape2 r-textstem r-wordcloud r-ggwordcloud r-robotstxt r-igraph r-ggraph r-janitor r-dbi r-rpostgres postgresql
```

or build a fresh environment with `conda env create -f environment.yml`. Then
start RStudio from Anaconda Prompt with `open_rstudio.bat q1_mapreduce\q1_mapreduce.Rproj`
so the conda DLLs are found (VS Code: `code .` from the activated prompt).

The scrapers do not use the `polite` package (archived from CRAN in September
2026). `shared/polite_fetch.R` does the same job with `robotstxt` and `httr`:
it checks robots.txt, sends a descriptive user agent and waits the site's crawl
delay (at least 5 seconds) between requests.


## 2. Running each question

### Q1 MapReduce keyword search (`q1_mapreduce`)

```
cd q1_mapreduce
Rscript run_local.R africa
```

In RStudio, open `q1_mapreduce.Rproj`, run `source("run_local.R")` and type the
keyword when prompted. The keyword is never hardcoded.

| File | Purpose |
|---|---|
| `mapper.R` | 1.2 Mapper: emits `document, row, column` per whole-word, case-insensitive match |
| `reducer.R` | 1.3 Reducer: groups the sorted matches per document |
| `job_config.R` | 1.4 Job configuration used by the local run |
| `hadoop/run_streaming_job.sh` | 1.4 The same settings as a Hadoop Streaming submission for a cluster |
| `run_local.R` | Simulates map, shuffle/sort and reduce locally and writes the evidence |

Output in `output/<keyword>/`: `part-00000` (result), `job_log.txt` (counters and
result, use for the screenshot), `_intermediate/reduce_input_00000.tsv` (sorted
map output, i.e. what the shuffle hands to the reducer) and `_SUCCESS`.
For "africa": 16 matches in doc1, doc2, doc3 and doc5; doc4, doc6 and doc7 have none.
Rows are line numbers (blank lines count) and columns are character positions,
the same as "Ln, Col" in the editor status bar.

### Q2 LDA topics (`q2_lda`)

```
cd q2_lda
Rscript q2_lda.R
```

Reads `data/news.zip` directly. Settings at the top: `n_topics` (n, default 4),
`top_k` (k, default 10). Writes to `output/`:

- `q2_news_dataframe.csv`: 2.1 data frame (file_name, content, plus title, date and cleaned text)
- `q2_top_terms_per_topic.csv`, `q2_topic_summary.csv`, `q2_document_topic_distribution.csv`: 2.2
- `fig_q2_top_words_bar.png`, `fig_q2_topic_wordclouds.png`: 2.3 (two methods)
- `fig_q2_document_topic_heatmap.png`, `fig_q2_topic_selection.png`: supporting charts

### Q3 WebText (`q3_webtext`)

Needs internet access. Scrapes the Wikipedia article
"South African energy crisis" (CC BY-SA text; robots.txt allows /wiki/ pages and is
checked before downloading).

```
cd q3_webtext
Rscript q3_webtext.R
```

The first run saves `data/page_snapshot.html`; later runs reuse it (set
`refresh <- TRUE` to download again). Change `page_url` to analyse another page.
Writes `q3_article.rds` (the R data structure), cleaned paragraphs and sentences,
both summaries (`q3_summary_word_frequency.md`, `q3_summary_textrank.md`), a
comparison table and four charts to `output/`.

### Q4 ETL with PostgreSQL (`q4_etl`)

Use case: which kinds of tech news posts gain traction on Hacker News.

```
cd q4_etl
Rscript q4_1_scrape.R          # 4.1 about 1 minute: robots.txt asks for 30 s between pages
Rscript q4_2_clean.R           # 4.2 writes output\hn_clean.csv
postgres\start_postgres.bat    # private server on port 5433, no admin rights; keep the window open
Rscript q4_3_postgres.R        # 4.3 creates the table, loads the CSV, runs both investigations
```

- `data/raw_html/` and `data/hn_raw.csv`: the raw scrape with its gaps and duplicates
- `sql/01_create_table.sql`, `sql/03_analysis.sql`: the DDL and the two SQL investigations
- `sql/02_load_with_psql.sql`: the same import using `psql \copy`, if you prefer to show it in psql
- `output/q4_investigation_1.csv`, `output/q4_investigation_2.csv`: query results for the write-up

**If PostgreSQL is not allowed to run on your PC** (for example a work laptop
that blocks `postgres.exe`), run `q4_3_make_insert_sql.R` instead of the last two
steps. It turns `output/hn_clean.csv` into `sql/02_insert_data.sql`. Paste
`sql/01_create_table.sql` and that file into the Schema panel of an online
PostgreSQL such as db-fiddle.com (no account needed), and `sql/03_analysis.sql`
into the Query panel. `colab/q4_3_postgres_colab.ipynb` does the same in Google
Colab where a Google account can be used.

The project uses its own PostgreSQL server (data in `%USERPROFILE%\pgdata-itbda`,
user `postgres`, database `itbda`) on **port 5433**, not the default 5432, and
`q4_3_postgres.R` only connects to `localhost:5433`. So the scripts cannot write
into any other PostgreSQL on the PC, such as a company database. Stop the server
afterwards with `postgres\stop_postgres.bat`.


## 3. Results (final run, 12 November 2026)

Every number below comes from the saved outputs and the `console_output.txt`
file in each question's `output` folder (R 4.6.2 on Windows).

### Q1 MapReduce keyword search

Keyword "africa" (case-insensitive, whole word): 7 map tasks over 307 lines,
16 matches, 1 reducer. `output/africa/part-00000`:

| Document | Matches | Locations (row, column) |
|---|---|---|
| doc1.txt | 1 | (1,64) |
| doc2.txt | 3 | (1,57) (33,24) (58,81) |
| doc3.txt | 8 | (1,38) (3,7) (5,7) (40,146) (46,7) (50,142) (52,86) (54,44) |
| doc5.txt | 4 | (1,62) (3,88) (23,121) (38,27) |

doc4, doc6 and doc7 contain no match. "African" is not counted because the
search matches whole words only.

### Q2 LDA topics

- 2.1: 10 articles in a data frame (`file_name`, `content`, plus title, date and
  cleaned text). Denoising cut 3,832 raw tokens to 1,747 (54% removed); the
  document-term matrix is 10 documents x 325 terms.
- 2.2: n = 4 topics. Over 5 Gibbs runs per n, n = 4 scored better than n = 5 on
  both coherence (-0.164 vs -0.180) and topic overlap (0.072 vs 0.079).

| Topic | Top words | Share of corpus | Main articles |
|---|---|---|---|
| 1 | government, public, coalition, administration, country | 23.1% | news_7, news_8 |
| 2 | eskom, police, expect, power, cape | 28.5% | news_1, news_4, news_5, news_10 |
| 3 | department, priority, report, school, unemployment | 23.1% | news_2, news_3 |
| 4 | service, invoice, pay, day, gxoyiya | 25.3% | news_6, news_9 |

- 2.3: `fig_q2_top_words_bar.png` (bar chart of word probabilities) and
  `fig_q2_topic_wordclouds.png` (word clouds), plus a document-topic heatmap
  and the topic-number diagnostics chart.

### Q3 WebText summaries

- 3.1: Wikipedia "South African energy crisis", retrieved 2026-11-12 09:40:
  60 paragraphs, 4,313 words in 7 sections, stored as an R list
  (`q3_article.rds`: url, title, retrieval time, licence, paragraph table).
- 3.2: 175 sentences kept; 4,313 raw words reduced to 2,085 content words.
- 3.3: two 8-sentence extractive summaries.

| Method | Words | Share of article | Sections covered |
|---|---|---|---|
| Word frequency | 186 | 4.4% | 6 |
| TextRank | 260 | 6.1% | 5 |

The two summaries share 3 sentences (Jaccard overlap 0.23). The summaries are in
`q3_summary_word_frequency.md` and `q3_summary_textrank.md`; the charts are top
words, a word cloud, sentence scores by position and the TextRank network.

### Q4 ETL

- 4.1: 90 Hacker News posts scraped from 3 pages. Raw data issues: 1 job advert
  without points or author, 7 posts showing "discuss" instead of a comment
  count, 2 self posts without a domain, and ages given only as text.
- 4.2: points imputed for 1 post (median of posts of similar age, flagged),
  7 comment counts set to 0 (flagged), domains standardised, posting time
  parsed; 0 missing values remain. Post types: 80 Story, 8 Show HN, 1 Job,
  1 Launch HN. Median 100.5 points, 33.5 comments, 13.5 hours old.
- 4.3: the table and both investigations are in `sql/`. PostgreSQL could not run
  on the work PC, so the import was done with `sql/02_insert_data.sql` (generated
  from `output/hn_clean.csv`) on db-fiddle.com.


## 4. Troubleshooting

- **"DLL not found" or a package fails to load (conda R only):** R was started
  outside the activated environment. Start RStudio or VS Code from Anaconda
  Prompt after `conda activate r-env`.
- **Scraping times out or returns 403:** the work network may block the site.
  Try another network; the scripts save the raw pages so you only need to
  scrape once.
- **Hacker News layout changed:** `q4_1_scrape.R` stops with a clear message if
  it finds no stories; the selectors are in `parse_page()`.
