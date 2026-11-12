-- Investigation 1: which kinds of post attract the most engagement?
-- Imputed points (job adverts) are excluded so they do not distort averages.
SELECT
    post_type,
    COUNT(*)::INT                                                   AS stories,
    ROUND(AVG(points), 1)                                           AS avg_points,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY points)             AS median_points,
    ROUND(AVG(comments), 1)                                         AS avg_comments,
    ROUND(SUM(comments)::NUMERIC / NULLIF(SUM(points), 0), 2)       AS comments_per_point,
    ROUND(AVG(points_per_hour), 1)                                  AS avg_points_per_hour
FROM hn_stories
WHERE NOT points_imputed
GROUP BY post_type
ORDER BY avg_points DESC;

-- Investigation 2: how do front-page position and story age relate to engagement?
-- Stories are grouped into bands of ten ranks; the last two columns are the
-- correlations across all stories, repeated on every row for comparison.
WITH ranked AS (
    SELECT *, ((rank - 1) / 10) * 10 + 1 AS band_start
    FROM hn_stories
    WHERE NOT points_imputed
),
overall AS (
    SELECT
        ROUND(CORR(points, comments)::NUMERIC, 2)  AS corr_points_comments,
        ROUND(CORR(points, age_hours)::NUMERIC, 2) AS corr_points_age
    FROM ranked
)
SELECT
    r.band_start || '-' || (r.band_start + 9)  AS rank_band,
    COUNT(*)::INT                              AS stories,
    ROUND(AVG(r.points), 1)                    AS avg_points,
    ROUND(AVG(r.comments), 1)                  AS avg_comments,
    ROUND(AVG(r.age_hours), 1)                 AS avg_age_hours,
    ROUND(AVG(r.points_per_hour), 1)           AS avg_points_per_hour,
    o.corr_points_comments,
    o.corr_points_age
FROM ranked r
CROSS JOIN overall o
GROUP BY r.band_start, o.corr_points_comments, o.corr_points_age
ORDER BY r.band_start;
