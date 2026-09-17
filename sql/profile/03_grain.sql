-- 03_grain.sql
--
-- Profiling query (Step 2). Tests whether each file's apparent grain really is
-- unique, and fills in the dimension inventory:
--   1. Is the grain unique? One test per file: the annual file has no QUARTER
--      column, so its key is a different key.
--   2. If it is not unique: how often keys repeat, where the repeats sit, and
--      whether the repeated rows carry the same measures.
--   3. Procedure groups: the full list per file, and what it costs to mistake
--      'All Other Procedures' for a total.
--   4. Dimension integrity: NULLs, and values that differ only by case or by
--      surrounding spaces.
--
-- Files are located through data/raw/_manifest.json by resource_id, and every
-- cell is read as text, as in the other profiling files. Their setup is
-- repeated here on purpose, so each file runs on its own.
--
-- Run from the repository root:
--     python src/run_sql.py sql/profile/03_grain.sql

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


-- Data rows, one table per file -----------------------------------------------
-- One table per file, not one stacked table, because the grain test has to use
-- each file's own key. FISCAL_YEAR IS NOT NULL drops the annual file's blank
-- rows, which 01_time_coverage.sql showed are fully blank.

CREATE TEMP TABLE quarterly_rows AS
SELECT *
FROM read_xlsx(getvariable('quarterly_path'),
    sheet = 'Sheet1', header = true, all_varchar = true, stop_at_empty = false)
WHERE FISCAL_YEAR IS NOT NULL;

CREATE TEMP TABLE annual_rows AS
SELECT *
FROM read_xlsx(getvariable('annual_path'),
    sheet = 'Sheet1', header = true, all_varchar = true, stop_at_empty = false)
WHERE FISCAL_YEAR IS NOT NULL;

CREATE TEMP TABLE interim_rows AS
SELECT *
FROM read_xlsx(getvariable('interim_path'),
    sheet = 'Sheet1', header = true, all_varchar = true, stop_at_empty = false)
WHERE FISCAL_YEAR IS NOT NULL;


-- 1. Is the grain unique? -----------------------------------------------------
-- Each file is grouped by its own key. A unique grain means
-- key_combinations equals rows, and max_rows_per_key is 1.

WITH quarterly_keys AS (
    SELECT count(*) AS rows_for_key
    FROM quarterly_rows
    GROUP BY FISCAL_YEAR, QUARTER, HEALTH_AUTHORITY, HOSPITAL_NAME, PROCEDURE_GROUP
),

annual_keys AS (
    SELECT count(*) AS rows_for_key
    FROM annual_rows
    GROUP BY FISCAL_YEAR, HEALTH_AUTHORITY, HOSPITAL_NAME, PROCEDURE_GROUP
),

interim_keys AS (
    SELECT count(*) AS rows_for_key
    FROM interim_rows
    GROUP BY FISCAL_YEAR, QUARTER, HEALTH_AUTHORITY, HOSPITAL_NAME, PROCEDURE_GROUP
)

SELECT 'quarterly' AS file, (SELECT count(*) FROM quarterly_rows) AS rows,
       count(*) AS key_combinations,
       count(*) FILTER (WHERE rows_for_key > 1) AS repeated_keys,
       max(rows_for_key) AS max_rows_per_key
FROM quarterly_keys
UNION ALL
SELECT 'annual', (SELECT count(*) FROM annual_rows),
       count(*), count(*) FILTER (WHERE rows_for_key > 1), max(rows_for_key)
FROM annual_keys
UNION ALL
SELECT 'interim', (SELECT count(*) FROM interim_rows),
       count(*), count(*) FILTER (WHERE rows_for_key > 1), max(rows_for_key)
FROM interim_keys;


-- Keys that appear more than once, from all three files ------------------------
-- Each file is still grouped by its own key first. The annual file then carries
-- a NULL quarter, only so that the three results have the same shape.

CREATE TEMP TABLE repeated_keys AS
SELECT 'quarterly' AS file, FISCAL_YEAR, QUARTER, HEALTH_AUTHORITY, HOSPITAL_NAME,
       PROCEDURE_GROUP, count(*) AS rows_for_key
FROM quarterly_rows
GROUP BY FISCAL_YEAR, QUARTER, HEALTH_AUTHORITY, HOSPITAL_NAME, PROCEDURE_GROUP
HAVING count(*) > 1
UNION ALL
SELECT 'annual', FISCAL_YEAR, NULL, HEALTH_AUTHORITY, HOSPITAL_NAME,
       PROCEDURE_GROUP, count(*)
FROM annual_rows
GROUP BY FISCAL_YEAR, HEALTH_AUTHORITY, HOSPITAL_NAME, PROCEDURE_GROUP
HAVING count(*) > 1
UNION ALL
SELECT 'interim', FISCAL_YEAR, QUARTER, HEALTH_AUTHORITY, HOSPITAL_NAME,
       PROCEDURE_GROUP, count(*)
FROM interim_rows
GROUP BY FISCAL_YEAR, QUARTER, HEALTH_AUTHORITY, HOSPITAL_NAME, PROCEDURE_GROUP
HAVING count(*) > 1;


-- 2a. How often do keys repeat? ------------------------------------------------
-- A few keys appearing twice is a different problem from one dimension
-- combination appearing many times over. Empty if the grain is unique.

SELECT file, rows_for_key, count(*) AS keys
FROM repeated_keys
GROUP BY file, rows_for_key
ORDER BY file, rows_for_key;


-- 2b. Where do the repeats sit? ------------------------------------------------
-- By fiscal year, by procedure group, and by whether the row is a total row.

SELECT file, FISCAL_YEAR, count(*) AS repeated_keys, sum(rows_for_key) AS rows
FROM repeated_keys
GROUP BY file, FISCAL_YEAR
ORDER BY file, FISCAL_YEAR;

SELECT file, PROCEDURE_GROUP, count(*) AS repeated_keys
FROM repeated_keys
GROUP BY file, PROCEDURE_GROUP
ORDER BY repeated_keys DESC, file, PROCEDURE_GROUP;

SELECT
    file,
    HEALTH_AUTHORITY = 'All Health Authorities' AS all_health_authorities,
    HOSPITAL_NAME    = 'All Facilities'         AS all_facilities,
    PROCEDURE_GROUP  = 'All Procedures'         AS all_procedures,
    count(*) AS repeated_keys
FROM repeated_keys
GROUP BY file, all_health_authorities, all_facilities, all_procedures
ORDER BY file, repeated_keys DESC;


-- 2c. Do the repeated rows carry the same measures? ---------------------------
-- This decides what silver may do about it:
--   distinct_measure_sets = 1: the rows are copies. Silver may drop the copies,
--     but only as a written rule.
--   distinct_measure_sets > 1: the key is not the grain. Two different records
--     share it, and silver must fail rather than pick one.
--
-- The four measures are compared as a list, so that a blank cell and the text
-- '<5' stay different from each other. Joining the strings together would blur
-- them.

WITH repeated_quarterly_rows AS (
    SELECT q.*
    FROM quarterly_rows AS q
    JOIN repeated_keys AS r
      ON r.file = 'quarterly'
     AND r.FISCAL_YEAR = q.FISCAL_YEAR
     AND r.QUARTER = q.QUARTER
     AND r.HEALTH_AUTHORITY = q.HEALTH_AUTHORITY
     AND r.HOSPITAL_NAME = q.HOSPITAL_NAME
     AND r.PROCEDURE_GROUP = q.PROCEDURE_GROUP
)

SELECT
    FISCAL_YEAR, QUARTER, HEALTH_AUTHORITY, HOSPITAL_NAME, PROCEDURE_GROUP,
    count(*) AS rows,
    count(DISTINCT [WAITING, COMPLETED,
                    PERCENTILE_COMP_50TH, PERCENTILE_COMP_90TH])
        AS distinct_measure_sets,
    string_agg(WAITING, ' | ')   AS waiting_values,
    string_agg(COMPLETED, ' | ') AS completed_values
FROM repeated_quarterly_rows
GROUP BY FISCAL_YEAR, QUARTER, HEALTH_AUTHORITY, HOSPITAL_NAME, PROCEDURE_GROUP
ORDER BY distinct_measure_sets DESC, rows DESC
LIMIT 20;


-- All three files stacked, for the inventory queries ---------------------------
-- Only used below, where rows are always grouped by file.

CREATE TEMP TABLE all_rows AS
SELECT 'quarterly' AS file, FISCAL_YEAR, QUARTER, HEALTH_AUTHORITY, HOSPITAL_NAME,
       PROCEDURE_GROUP, WAITING, COMPLETED
FROM quarterly_rows
UNION ALL
SELECT 'annual', FISCAL_YEAR, NULL, HEALTH_AUTHORITY, HOSPITAL_NAME,
       PROCEDURE_GROUP, WAITING, COMPLETED
FROM annual_rows
UNION ALL
SELECT 'interim', FISCAL_YEAR, QUARTER, HEALTH_AUTHORITY, HOSPITAL_NAME,
       PROCEDURE_GROUP, WAITING, COMPLETED
FROM interim_rows;


-- 3a. Every procedure group, with its row count per file -----------------------
-- A zero shows a procedure group that one file does not have at all.

SELECT
    PROCEDURE_GROUP,
    count(*) FILTER (WHERE file = 'quarterly') AS quarterly_rows,
    count(*) FILTER (WHERE file = 'annual')    AS annual_rows,
    count(*) FILTER (WHERE file = 'interim')   AS interim_rows
FROM all_rows
GROUP BY PROCEDURE_GROUP
ORDER BY PROCEDURE_GROUP;


-- 3b. What mistaking 'All Other Procedures' for a total costs -------------------
-- Province-wide rows of the annual file, one fiscal year at a time:
--   published_total: the COMPLETED figure on the 'All Procedures' row.
--   sum_of_groups: every other procedure group added up, including
--     'All Other Procedures'. It should come close to the published total, short
--     only by the province-wide groups whose value is suppressed.
--   sum_without_all_other: the same sum with 'All Other Procedures' dropped, as
--     a filter like LIKE 'All %' would drop it.
--
-- TRY_CAST, so a suppressed '<5' becomes NULL and stays out of the sum.
-- suppressed_groups counts those cells, because they are the only other reason
-- for a gap: each one hides between 1 and 4 cases.

SELECT
    FISCAL_YEAR,
    max(TRY_CAST(COMPLETED AS INTEGER))
        FILTER (WHERE PROCEDURE_GROUP = 'All Procedures')     AS published_total,
    sum(TRY_CAST(COMPLETED AS INTEGER))
        FILTER (WHERE PROCEDURE_GROUP <> 'All Procedures')    AS sum_of_groups,
    sum(TRY_CAST(COMPLETED AS INTEGER))
        FILTER (WHERE PROCEDURE_GROUP NOT IN ('All Procedures',
                                              'All Other Procedures'))
                                                              AS sum_without_all_other,
    count(*) FILTER (WHERE PROCEDURE_GROUP <> 'All Procedures'
                       AND TRY_CAST(COMPLETED AS INTEGER) IS NULL)
                                                              AS suppressed_groups,
    -- What the published total minus each sum comes to: the first gap is what
    -- suppression hides, the second is that plus every case in
    -- 'All Other Procedures'.
    max(TRY_CAST(COMPLETED AS INTEGER))
        FILTER (WHERE PROCEDURE_GROUP = 'All Procedures')
        - sum(TRY_CAST(COMPLETED AS INTEGER))
            FILTER (WHERE PROCEDURE_GROUP <> 'All Procedures')
                                                              AS gap_from_suppression,
    max(TRY_CAST(COMPLETED AS INTEGER))
        FILTER (WHERE PROCEDURE_GROUP = 'All Procedures')
        - sum(TRY_CAST(COMPLETED AS INTEGER))
            FILTER (WHERE PROCEDURE_GROUP NOT IN ('All Procedures',
                                                  'All Other Procedures'))
                                                              AS gap_if_all_other_dropped
FROM annual_rows
WHERE HEALTH_AUTHORITY = 'All Health Authorities'
  AND HOSPITAL_NAME    = 'All Facilities'
GROUP BY FISCAL_YEAR
ORDER BY FISCAL_YEAR;

-- The same two gaps over every fiscal year in the annual file at once.

SELECT
    sum(TRY_CAST(COMPLETED AS INTEGER))
        FILTER (WHERE PROCEDURE_GROUP = 'All Procedures')      AS published_total,
    sum(TRY_CAST(COMPLETED AS INTEGER))
        FILTER (WHERE PROCEDURE_GROUP = 'All Procedures')
        - sum(TRY_CAST(COMPLETED AS INTEGER))
            FILTER (WHERE PROCEDURE_GROUP <> 'All Procedures')
                                                               AS gap_from_suppression,
    sum(TRY_CAST(COMPLETED AS INTEGER))
        FILTER (WHERE PROCEDURE_GROUP = 'All Procedures')
        - sum(TRY_CAST(COMPLETED AS INTEGER))
            FILTER (WHERE PROCEDURE_GROUP NOT IN ('All Procedures',
                                                  'All Other Procedures'))
                                                               AS gap_if_all_other_dropped
FROM annual_rows
WHERE HEALTH_AUTHORITY = 'All Health Authorities'
  AND HOSPITAL_NAME    = 'All Facilities';


-- 3c. The same two gaps at quarterly grain ------------------------------------
-- Same province-wide check on the quarterly file, one fiscal quarter at a time.
-- Suppression bites more often at quarterly grain, because the counts are
-- smaller. If the detail still adds up to the published total there, apart from
-- the suppressed groups, then suppression behaves the same way at both grains.
-- If it does not, that is something Step 5 has to know before it reconciles
-- anything.

SELECT
    FISCAL_YEAR,
    QUARTER,
    max(TRY_CAST(COMPLETED AS INTEGER))
        FILTER (WHERE PROCEDURE_GROUP = 'All Procedures')      AS published_total,
    count(*) FILTER (WHERE PROCEDURE_GROUP <> 'All Procedures'
                       AND TRY_CAST(COMPLETED AS INTEGER) IS NULL)
                                                               AS suppressed_groups,
    max(TRY_CAST(COMPLETED AS INTEGER))
        FILTER (WHERE PROCEDURE_GROUP = 'All Procedures')
        - sum(TRY_CAST(COMPLETED AS INTEGER))
            FILTER (WHERE PROCEDURE_GROUP <> 'All Procedures')
                                                               AS gap_from_suppression,
    max(TRY_CAST(COMPLETED AS INTEGER))
        FILTER (WHERE PROCEDURE_GROUP = 'All Procedures')
        - sum(TRY_CAST(COMPLETED AS INTEGER))
            FILTER (WHERE PROCEDURE_GROUP NOT IN ('All Procedures',
                                                  'All Other Procedures'))
                                                               AS gap_if_all_other_dropped
FROM quarterly_rows
WHERE HEALTH_AUTHORITY = 'All Health Authorities'
  AND HOSPITAL_NAME    = 'All Facilities'
GROUP BY FISCAL_YEAR, QUARTER
ORDER BY FISCAL_YEAR, QUARTER;

-- Over all 64 quarters at once, and the largest single-quarter gap.

SELECT
    sum(TRY_CAST(COMPLETED AS INTEGER))
        FILTER (WHERE PROCEDURE_GROUP = 'All Procedures')      AS published_total,
    count(*) FILTER (WHERE PROCEDURE_GROUP <> 'All Procedures'
                       AND TRY_CAST(COMPLETED AS INTEGER) IS NULL)
                                                               AS suppressed_groups,
    sum(TRY_CAST(COMPLETED AS INTEGER))
        FILTER (WHERE PROCEDURE_GROUP = 'All Procedures')
        - sum(TRY_CAST(COMPLETED AS INTEGER))
            FILTER (WHERE PROCEDURE_GROUP <> 'All Procedures')
                                                               AS gap_from_suppression,
    sum(TRY_CAST(COMPLETED AS INTEGER))
        FILTER (WHERE PROCEDURE_GROUP = 'All Procedures')
        - sum(TRY_CAST(COMPLETED AS INTEGER))
            FILTER (WHERE PROCEDURE_GROUP NOT IN ('All Procedures',
                                                  'All Other Procedures'))
                                                               AS gap_if_all_other_dropped
FROM quarterly_rows
WHERE HEALTH_AUTHORITY = 'All Health Authorities'
  AND HOSPITAL_NAME    = 'All Facilities';


-- 4a. NULLs in the dimension columns -------------------------------------------

SELECT
    file,
    count(*)                                        AS rows,
    count(*) FILTER (WHERE FISCAL_YEAR IS NULL)     AS fiscal_year_null,
    count(*) FILTER (WHERE QUARTER IS NULL)         AS quarter_null,
    count(*) FILTER (WHERE HEALTH_AUTHORITY IS NULL) AS health_authority_null,
    count(*) FILTER (WHERE HOSPITAL_NAME IS NULL)   AS hospital_null,
    count(*) FILTER (WHERE PROCEDURE_GROUP IS NULL) AS procedure_group_null
FROM all_rows
GROUP BY file
ORDER BY file;


-- 4b. Values that differ only by case or surrounding spaces --------------------
-- A uniqueness test cannot see this: 'Burnaby Hospital' and 'Burnaby Hospital '
-- are two different keys to SQL and one hospital to a reader. Values are shown
-- inside brackets so that a trailing space is visible.

WITH dimension_cells AS (
    SELECT file, column_name, value
    FROM (
        SELECT file, FISCAL_YEAR, QUARTER, HEALTH_AUTHORITY, HOSPITAL_NAME,
               PROCEDURE_GROUP
        FROM all_rows
    )
    UNPIVOT (
        value FOR column_name IN
            (FISCAL_YEAR, QUARTER, HEALTH_AUTHORITY, HOSPITAL_NAME, PROCEDURE_GROUP)
    )
)

SELECT
    file,
    column_name,
    lower(trim(value))                              AS normalised_value,
    count(DISTINCT value)                           AS raw_variants,
    string_agg(DISTINCT '[' || value || ']', '  ')  AS variants
FROM dimension_cells
GROUP BY file, column_name, normalised_value
HAVING count(DISTINCT value) > 1
ORDER BY file, column_name, normalised_value;


-- 4c. Health authorities, and how many hospitals each one has -------------------
-- 'All Facilities' is left out of the hospital count: it is a total, not a
-- hospital.

SELECT
    file,
    HEALTH_AUTHORITY,
    count(DISTINCT HOSPITAL_NAME) FILTER (WHERE HOSPITAL_NAME <> 'All Facilities')
        AS hospitals,
    count(*) AS rows
FROM all_rows
GROUP BY file, HEALTH_AUTHORITY
ORDER BY file, HEALTH_AUTHORITY;
