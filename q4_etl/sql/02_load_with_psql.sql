-- Alternative to the R loader: import the CSV with psql's client-side \copy.
-- Run from the q4_etl folder:
--   psql -U postgres -d itbda -f sql/01_create_table.sql
--   psql -U postgres -d itbda -f sql/02_load_with_psql.sql
\copy hn_stories FROM 'output/hn_clean.csv' WITH (FORMAT csv, HEADER true, NULL '')

SELECT COUNT(*) AS rows_loaded FROM hn_stories;
