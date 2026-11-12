#!/usr/bin/env Rscript
# Hadoop Streaming reducer. Input arrives sorted by document, then row, then
# column, so all matches for one document are consecutive lines. Emits one line
# per document: document<TAB>match_count<TAB>(row,col) (row,col) ...

emit <- function(document, positions) {
  cat(document, "\t", length(positions), "\t", paste(positions, collapse = " "), "\n", sep = "")
}

con <- file("stdin")
open(con)
on.exit(close(con))

current_doc <- NULL
positions <- character()

while (length(line <- readLines(con, n = 1L, warn = FALSE, encoding = "UTF-8")) > 0L) {
  # Streaming may append a separator after an empty value; strsplit drops it.
  fields <- strsplit(line, "\t", fixed = TRUE)[[1]]
  if (length(fields) != 3L) {
    message("Skipping malformed record: ", line)
    next
  }

  if (!identical(fields[1], current_doc)) {
    if (!is.null(current_doc)) emit(current_doc, positions)
    current_doc <- fields[1]
    positions <- character()
  }
  positions <- c(positions, sprintf("(%s,%s)", fields[2], fields[3]))
}

if (!is.null(current_doc)) emit(current_doc, positions)
