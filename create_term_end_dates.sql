SET work_mem='1GB';

DROP TABLE IF EXISTS director.term_end_dates;

CREATE TABLE director.term_end_dates AS
WITH

term_dates AS (
    SELECT (director.equilar_id(director_id),
        director.director_id(director_id))::equilar_director_id AS director_id,
        max(fy_end) AS last_fy_end,
        min(start_date) AS start_date,
        max(term_end_date) AS end_date
    FROM director.director
    GROUP BY 1),

resignations AS (
    SELECT directorid, companyid AS boardid, effective_date
    FROM boardex.board_and_director_announcements
    WHERE description ~ 'will leave this Board'),

director_matches AS (
    SELECT director_id, (director_id).equilar_id, directorid
    FROM director.director_matches),

boardex_dates AS (
    SELECT director_id, max(effective_date) AS boardex_term_end_date
    FROM resignations AS a
    INNER JOIN director.boardex_merge AS b
    USING (boardid)
    INNER JOIN director_matches AS c
    ON b.equilar_id=c.equilar_id
    GROUP BY 1),

implied_end_dates AS (
    SELECT b.director_id,
        min(fy_end) AS implied_end_date
    FROM director.co_fin AS a
    INNER JOIN term_dates AS b
    ON director.equilar_id(company_id) =(b.director_id).equilar_id
        AND a.fy_end > b.last_fy_end
    GROUP BY 1)

SELECT DISTINCT *
FROM term_dates AS a
LEFT JOIN boardex_dates
USING (director_id)
LEFT JOIN implied_end_dates
USING (director_id);

GRANT SELECT ON director.term_end_dates TO equilar_access;

CREATE INDEX ON director.term_end_dates (director_id);
