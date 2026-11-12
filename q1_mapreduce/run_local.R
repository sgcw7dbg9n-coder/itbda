#!/usr/bin/env Rscript
# Runs the keyword search locally by simulating the Hadoop Streaming phases:
# one map task per document, shuffle and sort, then the reduce task(s).
#
#   Rscript run_local.R africa        (from the q1_mapreduce folder)
#   source("run_local.R")             (in RStudio; prompts for the keyword)

if (!file.exists("job_config.R")) {
  stop("Run this from the q1_mapreduce folder (open q1_mapreduce.Rproj in RStudio).", call. = FALSE)
}
source("job_config.R")

read_keyword <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  keyword <- if (length(args) > 0) {
    paste(args, collapse = " ")
  } else if (interactive()) {
    readline("Keyword to search for: ")
  } else {
    ""
  }
  keyword <- trimws(keyword)
  if (!nzchar(keyword)) stop("No keyword given. Usage: Rscript run_local.R <keyword>", call. = FALSE)
  keyword
}

rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")

# Runs one streaming task as its own R process, the way Hadoop launches the
# script for each task, with the task's environment variables set.
run_streaming_task <- function(script, input, env) {
  previous <- Sys.getenv(names(env), unset = NA, names = TRUE)
  do.call(Sys.setenv, as.list(env))
  on.exit({
    unset <- is.na(previous)
    if (any(unset)) Sys.unsetenv(names(previous)[unset])
    if (any(!unset)) do.call(Sys.setenv, as.list(previous[!unset]))
  }, add = TRUE)

  out <- suppressWarnings(system2(rscript, script, stdin = input, stdout = TRUE, stderr = ""))
  status <- attr(out, "status")
  if (!is.null(status) && status != 0) {
    stop(sprintf("%s failed on %s (exit status %d)", script, basename(input), status), call. = FALSE)
  }
  sub("\r$", "", out)   # Windows pipes can leave a carriage return on each line
}

# Stand-in for KeyFieldBasedPartitioner -k1,1: same document, same reducer.
partition_for <- function(document, reduces) {
  vapply(document, function(d) sum(utf8ToInt(d)) %% reduces, numeric(1)) + 1
}

keyword <- read_keyword()
started <- Sys.time()

input_dir <- job_config[["mapreduce.input.fileinputformat.inputdir"]]
reduces <- job_config[["mapreduce.job.reduces"]]
output_dir <- file.path(
  job_config[["mapreduce.output.fileoutputformat.outputdir"]],
  gsub("[^A-Za-z0-9]+", "_", tolower(keyword))
)

inputs <- list.files(input_dir, pattern = "\\.txt$", full.names = TRUE, recursive = TRUE)
inputs <- inputs[!grepl("__MACOSX", inputs, fixed = TRUE) & !startsWith(basename(inputs), "._")]
if (length(inputs) == 0) stop("No .txt documents found in ", input_dir, call. = FALSE)

# Hadoop refuses to overwrite an existing output directory; locally we replace it.
unlink(output_dir, recursive = TRUE)
dir.create(file.path(output_dir, "_intermediate"), recursive = TRUE)

# Map phase -----------------------------------------------------------------
map_input_records <- 0L
map_output <- character()
for (input in inputs) {
  map_input_records <- map_input_records + length(readLines(input, warn = FALSE))
  map_output <- c(map_output, run_streaming_task(
    job_config[["stream.map.streamprocessor"]],
    normalizePath(input),
    c(KEYWORD = keyword, mapreduce_map_input_file = normalizePath(input))
  ))
}

# Shuffle and sort ----------------------------------------------------------
records <- if (length(map_output) > 0) {
  read.delim(
    text = map_output, header = FALSE, quote = "",
    col.names = c("document", "row", "col"),
    colClasses = c("character", "integer", "integer")
  )
} else {
  data.frame(document = character(), row = integer(), col = integer())
}
records$partition <- if (nrow(records) > 0) partition_for(records$document, reduces) else integer()
# radix ordering compares bytes, matching Hadoop's -k1,1 -k2,2n -k3,3n comparator.
records <- records[order(records$document, records$row, records$col, method = "radix"), ]

# Reduce phase --------------------------------------------------------------
part_files <- character()
for (p in seq_len(reduces)) {
  reduce_input <- file.path(output_dir, "_intermediate", sprintf("reduce_input_%05d.tsv", p - 1))
  part <- records[records$partition == p, c("document", "row", "col")]
  write.table(part, reduce_input, sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)

  part_file <- file.path(output_dir, sprintf("part-%05d", p - 1))
  reduce_output <- if (nrow(part) > 0) {
    run_streaming_task(job_config[["stream.reduce.streamprocessor"]], normalizePath(reduce_input), c(KEYWORD = keyword))
  } else {
    character()
  }
  writeLines(reduce_output, part_file)
  part_files <- c(part_files, part_file)
}
invisible(file.create(file.path(output_dir, "_SUCCESS")))

# Job report ----------------------------------------------------------------
results <- unlist(lapply(part_files, readLines))
matched_docs <- unique(records$document)
unmatched_docs <- setdiff(basename(inputs), matched_docs)

report <- c(
  sprintf("Job:        %s", job_config[["mapreduce.job.name"]]),
  sprintf("Keyword:    \"%s\" (case-insensitive, whole word)", keyword),
  sprintf("Started:    %s", format(started, "%Y-%m-%d %H:%M:%S")),
  sprintf("Elapsed:    %.1f seconds", as.numeric(difftime(Sys.time(), started, units = "secs"))),
  "",
  "Counters",
  sprintf("  Map tasks (documents):          %d", length(inputs)),
  sprintf("  Map input records (lines):      %d", map_input_records),
  sprintf("  Map output records (matches):   %d", nrow(records)),
  sprintf("  Reduce tasks:                   %d", reduces),
  sprintf("  Reduce input groups (docs):     %d", length(matched_docs)),
  sprintf("  Reduce output records:          %d", length(results)),
  "",
  sprintf("Documents without a match: %s",
          if (length(unmatched_docs) > 0) paste(unmatched_docs, collapse = ", ") else "none"),
  "",
  sprintf("Output (%s):", paste(part_files, collapse = ", ")),
  "document\tmatches\tlocations (row,col)",
  if (length(results) > 0) results else "(no matches)"
)
writeLines(report, file.path(output_dir, "job_log.txt"))
cat(report, sep = "\n")
