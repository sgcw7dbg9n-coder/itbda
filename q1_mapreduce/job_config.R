# Job configuration for the keyword search. Property names mirror the Hadoop
# settings passed with -D in hadoop/run_streaming_job.sh, so the local run and a
# cluster run are configured the same way.

job_config <- list(
  "mapreduce.job.name" = "keyword-search",
  "mapreduce.input.fileinputformat.inputdir" = "data/map_reduce_test_docs",
  "mapreduce.output.fileoutputformat.outputdir" = "output",

  # Each document must reach one mapper whole, otherwise row numbers restart
  # part-way through a file. Hadoop: split.minsize = Long.MAX_VALUE.
  "mapreduce.input.fileinputformat.split.minsize" = "9223372036854775807",

  # Mapper output is document<TAB>row<TAB>column; all three fields form the
  # key so the framework sorts by document, then row and column numerically.
  "stream.map.output.field.separator" = "\t",
  "stream.num.map.output.key.fields" = 3L,
  "mapreduce.partition.keycomparator.options" = "-k1,1 -k2,2n -k3,3n",

  # Partition on the document only, so one reducer sees all of a document's matches.
  "mapreduce.partition.keypartitioner.options" = "-k1,1",
  "mapreduce.job.reduces" = 1L,

  "stream.map.streamprocessor" = "mapper.R",
  "stream.reduce.streamprocessor" = "reducer.R"
)
