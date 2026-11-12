#!/usr/bin/env bash
# Submits the keyword search to a Hadoop cluster with Hadoop Streaming.
# R (Rscript) must be installed on every worker node.
#
#   ./hadoop/run_streaming_job.sh africa
#   ./hadoop/run_streaming_job.sh "south africa" /data/news /results/south_africa
#
# Configuration settings (same names as job_config.R):
#   mapreduce.job.name                            label shown in the YARN UI
#   mapreduce.input.fileinputformat.split.minsize Long.MAX_VALUE, so no document is
#                                                 split and row numbers stay correct
#   stream.map.output.field.separator             tab between document, row, column
#   stream.num.map.output.key.fields              all 3 fields form the sort key
#   mapreduce.job.output.key.comparator.class     KeyFieldBasedComparator, so the
#   mapreduce.partition.keycomparator.options     key sorts by document, then row and
#                                                 column numerically (-k2,2n -k3,3n)
#   -partitioner KeyFieldBasedPartitioner         with keypartitioner.options -k1,1,
#                                                 every match for a document goes to
#                                                 the same reducer
#   mapreduce.job.reduces                         number of reduce tasks (part files)
#   -cmdenv KEYWORD                               the search keyword, read by mapper.R
#                                                 with Sys.getenv("KEYWORD")
#   -files                                        ships both scripts to every node
set -euo pipefail

keyword="${1:?Usage: $0 <keyword> [hdfs_input_dir] [hdfs_output_dir]}"
slug="$(echo "$keyword" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '_' | sed 's/_$//')"
input_dir="${2:-/user/${USER}/keyword_search/input}"
output_dir="${3:-/user/${USER}/keyword_search/output/${slug}}"

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
streaming_jar="$(ls "${HADOOP_HOME:?Set HADOOP_HOME}"/share/hadoop/tools/lib/hadoop-streaming-*.jar | head -n 1)"

# Load the corpus into HDFS on the first run.
if ! hdfs dfs -test -d "$input_dir"; then
  hdfs dfs -mkdir -p "$input_dir"
  hdfs dfs -put "$project_dir"/data/map_reduce_test_docs/*.txt "$input_dir"
fi

# Hadoop will not overwrite an existing output directory.
hdfs dfs -rm -r -f -skipTrash "$output_dir"

hadoop jar "$streaming_jar" \
  -D mapreduce.job.name="keyword-search-${slug}" \
  -D mapreduce.input.fileinputformat.split.minsize=9223372036854775807 \
  -D stream.map.output.field.separator=$'\t' \
  -D stream.num.map.output.key.fields=3 \
  -D mapreduce.job.output.key.comparator.class=org.apache.hadoop.mapreduce.lib.partition.KeyFieldBasedComparator \
  -D mapreduce.partition.keycomparator.options="-k1,1 -k2,2n -k3,3n" \
  -D mapreduce.partition.keypartitioner.options="-k1,1" \
  -D mapreduce.job.reduces=1 \
  -files "${project_dir}/mapper.R,${project_dir}/reducer.R" \
  -cmdenv KEYWORD="$keyword" \
  -mapper "Rscript mapper.R" \
  -reducer "Rscript reducer.R" \
  -partitioner org.apache.hadoop.mapred.lib.KeyFieldBasedPartitioner \
  -input "$input_dir" \
  -output "$output_dir"

hdfs dfs -cat "${output_dir}/part-*"
