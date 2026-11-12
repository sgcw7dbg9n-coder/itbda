#!/usr/bin/env Rscript
# Hadoop Streaming mapper: emits "document<TAB>row<TAB>column" for every
# whole-word, case-insensitive match of the keyword in its input split.

keyword <- trimws(Sys.getenv("KEYWORD"))
if (!nzchar(keyword)) {
  stop("KEYWORD is not set. Pass it with -cmdenv KEYWORD=<word>.", call. = FALSE)
}

# Hadoop exposes the current input file as an environment variable
# (dots in the property name become underscores).
input_path <- Sys.getenv("mapreduce_map_input_file", unset = "stdin")
document <- basename(input_path)

# (*UCP) makes \b Unicode-aware; \Q...\E treats the keyword as literal text.
pattern <- paste0("(*UCP)\\b\\Q", keyword, "\\E\\b")

# Lines are marked as UTF-8 in readLines() instead of re-encoding the
# connection, which stops reading at the first curly quote on non-UTF-8 locales.
con <- file("stdin")
open(con)
on.exit(close(con))

row <- 0L
while (length(line <- readLines(con, n = 1L, warn = FALSE, encoding = "UTF-8")) > 0L) {
  row <- row + 1L
  starts <- gregexpr(pattern, line, perl = TRUE, ignore.case = TRUE)[[1]]
  if (starts[1] > 0L) {
    cat(sprintf("%s\t%d\t%d\n", document, row, starts), sep = "")
  }
}
