-- Relational table for the cleaned Hacker News stories (output/hn_clean.csv).
DROP TABLE IF EXISTS hn_stories;

CREATE TABLE hn_stories (
    item_id          BIGINT        PRIMARY KEY,
    rank             INTEGER       NOT NULL CHECK (rank > 0),
    page             SMALLINT      NOT NULL,
    title            TEXT          NOT NULL,
    post_type        TEXT          NOT NULL,
    domain           TEXT          NOT NULL,
    author           TEXT          NOT NULL,
    points           INTEGER       NOT NULL CHECK (points >= 0),
    points_imputed   BOOLEAN       NOT NULL,
    comments         INTEGER       NOT NULL CHECK (comments >= 0),
    comments_imputed BOOLEAN       NOT NULL,
    age_hours        NUMERIC(8, 2),
    age_band         TEXT,
    posted_at        TIMESTAMPTZ,
    points_per_hour  NUMERIC(10, 2),
    title_words      INTEGER       NOT NULL,
    scraped_at       TIMESTAMPTZ   NOT NULL
);

CREATE INDEX hn_stories_post_type_idx ON hn_stories (post_type);
