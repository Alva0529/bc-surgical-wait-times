-- 02_suppression.sql
--
-- Profiling query (Step 2), not part of the pipeline. Finds out how the
-- small-numbers rule actually shows up in the cells of the three raw files.
--
-- Section 1 is the main query: the combination of states across the four
-- measure columns, row by row. It is the only query here that can tell a
-- suppressed blank from a not-applicable one:
--   - Suppressed: the value was withheld because it is below 5. A real value
--     exists, within a range, and totals are short by that amount.
--   - Not applicable: there is nothing to report. A percentile wait time cannot
--     exist when no surgeries were completed, and totals are not short at all.
-- A single blank cell looks the same either way. Only the counts in the same
-- row tell the two apart. Sections 2 to 6 support section 1.
--
-- Files are located through data/raw/_manifest.json by resource_id, and every
-- cell is read as text, as in 01_time_coverage.sql. That file's setup is
-- repeated here on purpose, so each profiling file runs on its own.
--
-- Run from the repository root:
--     python src/run_sql.py sql/profile/02_suppression.sql

INSTALL excel;
LOAD excel;


-- Resolve file paths from the manifest ----------------------------------------

-- The manifest holds every version ever fetched, one record each, so a
-- lookup takes the most recently fetched version of the resource.

SET VARIABLE quarterly_path = (
    SELECT local_path
    FROM read_json('data/raw/_manifest.json')
    WHERE resource_id = 'f294562c-a6fd-4d7f-8f99-c51c91891c67'
    ORDER BY last_fetched_at_utc DESC
    LIMIT 1
);

SET VARIABLE annual_path = (
    SELECT local_path
    FROM read_json('data/raw/_manifest.json')
    WHERE resource_id = '6cd508eb-7e31-4c86-b070-dc698131fa9a'
    ORDER BY last_fetched_at_utc DESC
    LIMIT 1
);

SET VARIABLE interim_path = (
    SELECT local_path
    FROM read_json('data/raw/_manifest.json')
    WHERE resource_id = '0c430fa8-043c-48d8-8e61-ecdab63b9ef3'
    ORDER BY last_fetched_at_utc DESC
    LIMIT 1
);


-- Data rows from all three files, in one table --------------------------------
-- Every row keeps the name of its file, and every query below groups by file,
-- so rows from different files are never added together.
--
-- FISCAL_YEAR IS NOT NULL removes the annual file's blank rows.
-- 01_time_coverage.sql showed that every row without a fiscal year is fully
-- blank, so this removes exactly those rows and nothing else.
--
-- row_id only gives each row a unique id, so that its cells can be put back
-- together after unpivoting. The order of the ids means nothing.

CREATE TEMP TABLE data_rows AS
SELECT
    row_number() OVER () AS row_id,
    *
FROM (
    SELECT
        'quarterly' AS file,
        FISCAL_YEAR, QUARTER, HEALTH_AUTHORITY, HOSPITAL_NAME, PROCEDURE_GROUP,
        WAITING, COMPLETED, PERCENTILE_COMP_50TH, PERCENTILE_COMP_90TH
    FROM read_xlsx(getvariable('quarterly_path'),
        sheet = 'Sheet1', header = true, all_varchar = true, stop_at_empty = false)
    WHERE FISCAL_YEAR IS NOT NULL

    UNION ALL

    SELECT
        'annual',
        FISCAL_YEAR, NULL, HEALTH_AUTHORITY, HOSPITAL_NAME, PROCEDURE_GROUP,
        WAITING, COMPLETED, PERCENTILE_COMP_50TH, PERCENTILE_COMP_90TH
    FROM read_xlsx(getvariable('annual_path'),
        sheet = 'Sheet1', header = true, all_varchar = true, stop_at_empty = false)
    WHERE FISCAL_YEAR IS NOT NULL

    UNION ALL

    SELECT
        'interim',
        FISCAL_YEAR, QUARTER, HEALTH_AUTHORITY, HOSPITAL_NAME, PROCEDURE_GROUP,
        WAITING, COMPLETED, PERCENTILE_COMP_50TH, PERCENTILE_COMP_90TH
    FROM read_xlsx(getvariable('interim_path'),
        sheet = 'Sheet1', header = true, all_varchar = true, stop_at_empty = false)
    WHERE FISCAL_YEAR IS NOT NULL
);


-- One row per cell, each cell classified --------------------------------------
-- UNPIVOT INCLUDE NULLS: without INCLUDE NULLS, DuckDB's UNPIVOT silently drops
-- NULL cells, and blank cells are exactly what this file is looking for.
--
-- TRY_CAST, not CAST: the goal here is to classify every cell. A cell that is
-- not a number becomes its own category instead of stopping the query.
--
-- kind is the coarse class. status is the fine class used to compare cells
-- within a row. A text cell's status includes the literal text, because a
-- publisher may mark "suppressed" and "not applicable" with different symbols.

CREATE TEMP TABLE cells AS
WITH unpivoted AS (
    SELECT
        row_id, file, FISCAL_YEAR, QUARTER,
        HEALTH_AUTHORITY, HOSPITAL_NAME, PROCEDURE_GROUP,
        column_name,
        literal,
        TRY_CAST(literal AS DOUBLE) AS number
    FROM data_rows
    UNPIVOT INCLUDE NULLS (
        literal FOR column_name IN
            (WAITING, COMPLETED, PERCENTILE_COMP_50TH, PERCENTILE_COMP_90TH)
    )
)
SELECT
    *,
    CASE
        WHEN literal IS NULL    THEN 'blank'
        WHEN trim(literal) = '' THEN 'whitespace'
        WHEN number IS NULL     THEN 'text'
        ELSE 'number'
    END AS kind,
    CASE
        WHEN literal IS NULL    THEN 'blank'
        WHEN trim(literal) = '' THEN 'whitespace'
        WHEN number IS NULL     THEN 'text ' || literal
        WHEN number < 0         THEN 'negative'
        WHEN number = 0         THEN '0'
        WHEN column_name IN ('PERCENTILE_COMP_50TH', 'PERCENTILE_COMP_90TH')
                                THEN 'positive'
        WHEN number <> floor(number) THEN 'not whole'
        WHEN number < 5         THEN '1-4'
        ELSE '5+'
    END AS status
FROM unpivoted;


-- Each row's four cell statuses, side by side again ---------------------------
-- Each row_id has exactly one cell per measure column, so max() simply picks
-- that one cell's status.

CREATE TEMP TABLE row_status AS
SELECT
    d.*,
    s.completed_status,
    s.waiting_status,
    s.p50_status,
    s.p90_status
FROM data_rows AS d
JOIN (
    SELECT
        row_id,
        max(status) FILTER (WHERE column_name = 'COMPLETED')            AS completed_status,
        max(status) FILTER (WHERE column_name = 'WAITING')              AS waiting_status,
        max(status) FILTER (WHERE column_name = 'PERCENTILE_COMP_50TH') AS p50_status,
        max(status) FILTER (WHERE column_name = 'PERCENTILE_COMP_90TH') AS p90_status
    FROM cells
    GROUP BY row_id
) AS s
    ON s.row_id = d.row_id;


-- 1. MAIN QUERY: combinations of cell states within a row ---------------------
-- COMPLETED comes first, because the percentiles are computed over completed
-- surgeries. How to read the result:
--   - COMPLETED '0' next to blank percentiles: not applicable. No surgeries were
--     completed, so no wait time exists.
--   - COMPLETED withheld (blank or text) next to withheld percentiles:
--     suppressed together, "values less than 5 and their corresponding wait
--     times". If a withheld count can be 0, some of these could really be not
--     applicable, and the file cannot show which.
--   - WAITING withheld while COMPLETED is '5+': shows whether a small WAITING
--     also removes the percentiles.
--   - Any count shown as '1-4': the rule is not applied everywhere.

SELECT
    file,
    completed_status,
    waiting_status,
    p50_status,
    p90_status,
    count(*) AS n_rows
FROM row_status
GROUP BY file, completed_status, waiting_status, p50_status, p90_status
ORDER BY file, n_rows DESC;


-- 2. Kinds of cell, per file and column ---------------------------------------

SELECT
    file,
    column_name,
    count(*)                                   AS cells,
    count(*) FILTER (WHERE kind = 'number')     AS number_cells,
    count(*) FILTER (WHERE kind = 'blank')      AS blank_cells,
    count(*) FILTER (WHERE kind = 'whitespace') AS whitespace_cells,
    count(*) FILTER (WHERE kind = 'text')       AS text_cells
FROM cells
GROUP BY file, column_name
ORDER BY file, column_name;


-- 3. Every literal that is not a number ---------------------------------------
-- One line per distinct literal (NULL for blank cells), with the first and last
-- fiscal year it appears in. This shows whether the encoding differs between
-- columns, and whether it changed over time.

SELECT
    file,
    column_name,
    literal,
    count(*)         AS cells,
    min(FISCAL_YEAR) AS first_fiscal_year,
    max(FISCAL_YEAR) AS last_fiscal_year
FROM cells
WHERE kind <> 'number'
GROUP BY file, column_name, literal
ORDER BY file, column_name, cells DESC;


-- 4. Distribution of the published numbers ------------------------------------
-- Counts: a literal 0 means zeros are published rather than suppressed. Any
-- value above 0 and below 5 means the rule is not applied everywhere. Negative
-- or unusually large values would be sentinel numbers.

SELECT
    file,
    column_name,
    count(*) FILTER (WHERE number = 0)                AS zero,
    count(*) FILTER (WHERE number > 0 AND number < 5) AS above_0_below_5,
    count(*) FILTER (WHERE number < 0)                AS negative,
    count(*) FILTER (WHERE number <> floor(number))   AS not_whole,
    min(number)                                       AS min_value,
    max(number)                                       AS max_value
FROM cells
WHERE column_name IN ('WAITING', 'COMPLETED')
  AND kind = 'number'
GROUP BY file, column_name
ORDER BY file, column_name;

-- Percentiles, in weeks.

SELECT
    file,
    column_name,
    count(*) FILTER (WHERE number = 0) AS zero,
    count(*) FILTER (WHERE number < 0) AS negative,
    min(number)                        AS min_value,
    max(number)                        AS max_value
FROM cells
WHERE column_name IN ('PERCENTILE_COMP_50TH', 'PERCENTILE_COMP_90TH')
  AND kind = 'number'
GROUP BY file, column_name
ORDER BY file, column_name;


-- 5. Where withheld cells occur in the hierarchy ------------------------------
-- The three flags are the raw total markers, not a derived "level", so this
-- also shows which combinations of totals exist at all. A NULL flag would mean
-- a NULL dimension value.

SELECT
    file,
    HEALTH_AUTHORITY = 'All Health Authorities' AS all_health_authorities,
    HOSPITAL_NAME    = 'All Facilities'         AS all_facilities,
    PROCEDURE_GROUP  = 'All Procedures'         AS all_procedures,
    count(DISTINCT row_id) AS n_rows,
    count(*) FILTER (WHERE column_name = 'COMPLETED'
                       AND kind <> 'number')                 AS completed_withheld,
    count(*) FILTER (WHERE column_name = 'WAITING'
                       AND kind <> 'number')                 AS waiting_withheld,
    count(*) FILTER (WHERE column_name = 'PERCENTILE_COMP_50TH'
                       AND kind <> 'number')                 AS p50_withheld,
    count(*) FILTER (WHERE column_name = 'PERCENTILE_COMP_90TH'
                       AND kind <> 'number')                 AS p90_withheld
FROM cells
GROUP BY file, all_health_authorities, all_facilities, all_procedures
ORDER BY file, all_health_authorities DESC, all_facilities DESC, all_procedures DESC;


-- 6. Example rows for every combination found in section 1 --------------------
-- Up to three raw rows per file and combination: candidates for the CI fixture,
-- which must include suppressed rows. Ordered by the natural key rather than
-- row_id, so the same examples come back on every run.

SELECT
    file,
    completed_status,
    waiting_status,
    p50_status,
    p90_status,
    FISCAL_YEAR,
    QUARTER,
    HEALTH_AUTHORITY,
    HOSPITAL_NAME,
    PROCEDURE_GROUP,
    COMPLETED,
    WAITING,
    PERCENTILE_COMP_50TH,
    PERCENTILE_COMP_90TH
FROM row_status
QUALIFY row_number() OVER (
    PARTITION BY file, completed_status, waiting_status, p50_status, p90_status
    ORDER BY FISCAL_YEAR, QUARTER, HEALTH_AUTHORITY, HOSPITAL_NAME, PROCEDURE_GROUP
) <= 3
ORDER BY file, completed_status, waiting_status, p50_status, p90_status,
         FISCAL_YEAR, QUARTER, HEALTH_AUTHORITY, HOSPITAL_NAME, PROCEDURE_GROUP;


-- 7. The unexplained blank percentiles ----------------------------------------
-- Rows where COMPLETED is 5 or more and the percentiles are blank. Neither
-- documented rule explains them: the count is not suppressed, and surgeries
-- were completed, so a wait time exists. This records where they sit. It does
-- not explain them.

CREATE TEMP TABLE unexplained AS
SELECT *
FROM row_status
WHERE p50_status = 'blank'
  AND completed_status = '5+';

SELECT PROCEDURE_GROUP, count(*) AS n_rows, string_agg(DISTINCT file, ', ') AS files
FROM unexplained
GROUP BY PROCEDURE_GROUP
ORDER BY n_rows DESC;

SELECT HEALTH_AUTHORITY, HOSPITAL_NAME, count(*) AS n_rows
FROM unexplained
GROUP BY HEALTH_AUTHORITY, HOSPITAL_NAME
ORDER BY n_rows DESC;

SELECT FISCAL_YEAR, count(*) AS n_rows, string_agg(DISTINCT file, ', ') AS files
FROM unexplained
GROUP BY FISCAL_YEAR
ORDER BY FISCAL_YEAR;
