-- 01_time_coverage.sql
--
-- Profiling query (Step 2), not part of the pipeline. For the three raw files
-- it answers:
--   1. Which fiscal periods does each file actually contain?
--   2. How many rows does each file have, and are any of them not data?
--   3. Do the unnamed columns J-L in the quarterly file hold anything?
--   4. Do WAITING and COMPLETED add up from four quarters to the fiscal year?
--
-- Files are located through data/raw/_manifest.json by resource_id, never by
-- filename (see CLAUDE.md). Every cell is read as text (all_varchar = true), so
-- results show the literal cell content, not DuckDB's type guesses.
--
-- Run from the repository root. The first run downloads DuckDB's excel
-- extension.

INSTALL excel;
LOAD excel;


-- Resolve file paths from the manifest ----------------------------------------

SET VARIABLE quarterly_path = (
    SELECT local_path
    FROM read_json('data/raw/_manifest.json')
    WHERE resource_id = 'f294562c-a6fd-4d7f-8f99-c51c91891c67'
);

SET VARIABLE annual_path = (
    SELECT local_path
    FROM read_json('data/raw/_manifest.json')
    WHERE resource_id = '6cd508eb-7e31-4c86-b070-dc698131fa9a'
);

SET VARIABLE interim_path = (
    SELECT local_path
    FROM read_json('data/raw/_manifest.json')
    WHERE resource_id = '0c430fa8-043c-48d8-8e61-ecdab63b9ef3'
);


-- Read each workbook once -----------------------------------------------------
-- Temp tables, so each workbook is parsed once instead of once per query.
--
-- stop_at_empty = false: without an explicit range, read_xlsx stops at the
-- first blank row and silently drops every row below it.

CREATE TEMP TABLE quarterly_raw AS
SELECT *
FROM read_xlsx(getvariable('quarterly_path'),
    sheet = 'Sheet1', header = true, all_varchar = true, stop_at_empty = false);

CREATE TEMP TABLE annual_raw AS
SELECT *
FROM read_xlsx(getvariable('annual_path'),
    sheet = 'Sheet1', header = true, all_varchar = true, stop_at_empty = false);

CREATE TEMP TABLE interim_raw AS
SELECT *
FROM read_xlsx(getvariable('interim_path'),
    sheet = 'Sheet1', header = true, all_varchar = true, stop_at_empty = false);


-- 1. Fiscal periods present in each file --------------------------------------
-- Every distinct value is listed, not just min and max, so gaps in the middle,
-- blank rows (NULL) and stray text in the period columns all show up.

SELECT FISCAL_YEAR, QUARTER, count(*) AS n_rows
FROM quarterly_raw
GROUP BY FISCAL_YEAR, QUARTER
ORDER BY FISCAL_YEAR, QUARTER;

SELECT FISCAL_YEAR, count(*) AS n_rows
FROM annual_raw
GROUP BY FISCAL_YEAR
ORDER BY FISCAL_YEAR;

SELECT FISCAL_YEAR, QUARTER, count(*) AS n_rows
FROM interim_raw
GROUP BY FISCAL_YEAR, QUARTER
ORDER BY FISCAL_YEAR, QUARTER;


-- 2. Rows read per file, and rows with no fiscal year -------------------------
-- rows_read is compared against each sheet's stored dimension (max_row minus
-- the header row).
--
-- A row with no fiscal year is either fully blank, or it still carries other
-- values, which would be data that has lost its period. coalesce() over every
-- other column is NULL only when all of them are NULL.

SELECT
    'quarterly' AS file,
    count(*) AS rows_read,
    count(*) FILTER (WHERE FISCAL_YEAR IS NULL) AS no_fiscal_year,
    count(*) FILTER (WHERE FISCAL_YEAR IS NULL
        AND coalesce(QUARTER, HEALTH_AUTHORITY, HOSPITAL_NAME, PROCEDURE_GROUP,
                     WAITING, COMPLETED, PERCENTILE_COMP_50TH,
                     PERCENTILE_COMP_90TH) IS NULL) AS fully_blank
FROM quarterly_raw
UNION ALL
SELECT
    'annual',
    count(*),
    count(*) FILTER (WHERE FISCAL_YEAR IS NULL),
    count(*) FILTER (WHERE FISCAL_YEAR IS NULL
        AND coalesce(HEALTH_AUTHORITY, HOSPITAL_NAME, PROCEDURE_GROUP,
                     WAITING, COMPLETED, PERCENTILE_COMP_50TH,
                     PERCENTILE_COMP_90TH) IS NULL)
FROM annual_raw
UNION ALL
SELECT
    'interim',
    count(*),
    count(*) FILTER (WHERE FISCAL_YEAR IS NULL),
    count(*) FILTER (WHERE FISCAL_YEAR IS NULL
        AND coalesce(QUARTER, HEALTH_AUTHORITY, HOSPITAL_NAME, PROCEDURE_GROUP,
                     WAITING, COMPLETED, PERCENTILE_COMP_50TH,
                     PERCENTILE_COMP_90TH) IS NULL)
FROM interim_raw;

-- Sample of rows that have no fiscal year but are not blank. In the version
-- profiled first (annual sha256 2d9f99cb...), only the annual file had rows
-- without a fiscal year.

SELECT *
FROM annual_raw
WHERE FISCAL_YEAR IS NULL
  AND coalesce(HEALTH_AUTHORITY, HOSPITAL_NAME, PROCEDURE_GROUP,
               WAITING, COMPLETED, PERCENTILE_COMP_50TH,
               PERCENTILE_COMP_90TH) IS NOT NULL
LIMIT 20;


-- 3. Unnamed columns J-L in the quarterly file --------------------------------
-- read_xlsx with header = true silently drops these columns because their
-- header cells are empty, so they are read here by column range instead.
-- An open range like 'J:L' returns Excel's maximum row count (1,048,576), so
-- only the non-null counts mean anything, not the row count.

SELECT
    count(J) AS j_non_null,
    count(K) AS k_non_null,
    count(L) AS l_non_null
FROM read_xlsx(getvariable('quarterly_path'),
    sheet = 'Sheet1', header = false, all_varchar = true,
    stop_at_empty = false, range = 'J:L');


-- 4. Additivity: fiscal year vs the sum of its quarters -----------------------
-- Province-level total rows only. Counts at that level are far above any
-- suppression threshold, so a mismatch here cannot be caused by withheld cells.
--
-- Totals are matched on exact values, not LIKE 'All %', because
-- 'All Other Procedures' is a real procedure group, not a total.
--
-- Plain CAST, not TRY_CAST: if a total cell is not a number, the query should
-- fail loudly rather than silently leave that cell out of the sum.
--
-- If COMPLETED is a flow (cases done during the period), the year equals the
-- sum of its quarters: ratio 1. If WAITING is a stock (cases on the list at a
-- point in time), the sum of four quarters comes out near four times the year.

WITH annual AS (
    SELECT
        FISCAL_YEAR,
        CAST(COMPLETED AS INTEGER) AS completed,
        CAST(WAITING AS INTEGER)   AS waiting
    FROM annual_raw
    WHERE HEALTH_AUTHORITY = 'All Health Authorities'
      AND HOSPITAL_NAME    = 'All Facilities'
      AND PROCEDURE_GROUP  = 'All Procedures'
),

quarterly AS (
    SELECT
        FISCAL_YEAR,
        string_agg(QUARTER, ',' ORDER BY QUARTER) AS quarters,
        sum(CAST(COMPLETED AS INTEGER))           AS completed,
        sum(CAST(WAITING AS INTEGER))             AS waiting
    FROM quarterly_raw
    WHERE HEALTH_AUTHORITY = 'All Health Authorities'
      AND HOSPITAL_NAME    = 'All Facilities'
      AND PROCEDURE_GROUP  = 'All Procedures'
    GROUP BY FISCAL_YEAR
)

SELECT
    FISCAL_YEAR,
    q.quarters,
    a.completed                                AS completed_year,
    q.completed                                AS completed_sum_q,
    q.completed - a.completed                  AS completed_diff,
    round(q.completed / a.completed, 3)        AS completed_ratio,
    a.waiting                                  AS waiting_year,
    q.waiting                                  AS waiting_sum_q,
    q.waiting - a.waiting                      AS waiting_diff,
    round(q.waiting / a.waiting, 3)            AS waiting_ratio
FROM annual AS a
FULL JOIN quarterly AS q USING (FISCAL_YEAR)
ORDER BY FISCAL_YEAR;
