-- 02_silver_quarterly.sql
--
-- Silver: the quarterly cumulative file and the interim file, combined into one
-- table at quarterly grain, typed and reshaped, with every withheld value
-- carried as an explicit state.
--
--     python src/run_sql.py sql/silver/02_silver_quarterly.sql data/warehouse.duckdb
--
-- The measure columns work exactly as in 01_silver_annual.sql: a value, a
-- state, and for counts the bounds 1 and 4 when the state is suppressed.
--
-- Two columns are new here:
--   is_interim           the row came from the interim file, so its figures may
--                        still be revised
--   source_resource_id   the catalogue resource the row was published in
--
-- The two files can cover the same quarter. When that happens the cumulative
-- file wins and the interim rows for that quarter are dropped, because the
-- interim figures are the provisional version of the same quarter. Today they
-- do not overlap at all: they leave a gap instead, which the diagnostic queries
-- at the end of this file show. Both cases come from the same publishing
-- timing, so the rule has to be here either way. See Open question 2 in
-- docs/data-dictionary.md.

INSTALL excel;
LOAD excel;

SET VARIABLE cumulative_path = (
    SELECT local_path
    FROM read_json('data/raw/_manifest.json')
    WHERE resource_id = 'f294562c-a6fd-4d7f-8f99-c51c91891c67'
);

SET VARIABLE interim_path = (
    SELECT local_path
    FROM read_json('data/raw/_manifest.json')
    WHERE resource_id = '0c430fa8-043c-48d8-8e61-ecdab63b9ef3'
);


CREATE OR REPLACE TABLE silver_quarterly AS

WITH cumulative_raw AS (
    -- all_varchar: read what the cell actually holds, so that '<5' arrives as
    -- itself instead of as a failed conversion.
    -- stop_at_empty = false: the default stops at the first blank row.
    SELECT *
    FROM read_xlsx(getvariable('cumulative_path'),
        sheet = 'Sheet1', header = true, all_varchar = true, stop_at_empty = false)
    WHERE FISCAL_YEAR IS NOT NULL
),

interim_raw AS (
    SELECT *
    FROM read_xlsx(getvariable('interim_path'),
        sheet = 'Sheet1', header = true, all_varchar = true, stop_at_empty = false)
    WHERE FISCAL_YEAR IS NOT NULL
),

-- The precedence rule, written out in three steps ------------------------------
-- Step one: which quarters does the cumulative file already publish?

quarters_in_cumulative AS (
    SELECT DISTINCT FISCAL_YEAR, QUARTER
    FROM cumulative_raw
),

-- Step two: mark every interim row with whether its quarter is one of those.
-- The rule is a named column, so that the next step reads as the rule itself.

interim_marked AS (
    SELECT
        interim_raw.*,
        EXISTS (
            SELECT 1
            FROM quarters_in_cumulative
            WHERE quarters_in_cumulative.FISCAL_YEAR = interim_raw.FISCAL_YEAR
              AND quarters_in_cumulative.QUARTER     = interim_raw.QUARTER
        ) AS quarter_already_in_cumulative
    FROM interim_raw
),

-- Step three: keep the interim rows for quarters the cumulative file does not
-- cover yet. The dropped rows are the provisional version of a quarter that has
-- since been published in full.

interim_kept AS (
    SELECT *
    FROM interim_marked
    WHERE NOT quarter_already_in_cumulative
),

combined AS (
    SELECT
        FISCAL_YEAR, QUARTER, HEALTH_AUTHORITY, HOSPITAL_NAME, PROCEDURE_GROUP,
        WAITING, COMPLETED, PERCENTILE_COMP_50TH, PERCENTILE_COMP_90TH,
        false AS is_interim,
        'f294562c-a6fd-4d7f-8f99-c51c91891c67' AS source_resource_id
    FROM cumulative_raw

    UNION ALL

    SELECT
        FISCAL_YEAR, QUARTER, HEALTH_AUTHORITY, HOSPITAL_NAME, PROCEDURE_GROUP,
        WAITING, COMPLETED, PERCENTILE_COMP_50TH, PERCENTILE_COMP_90TH,
        true AS is_interim,
        '0c430fa8-043c-48d8-8e61-ecdab63b9ef3' AS source_resource_id
    FROM interim_kept
),

classified AS (
    SELECT
        FISCAL_YEAR      AS fiscal_year,
        QUARTER          AS quarter,
        HEALTH_AUTHORITY AS health_authority,
        HOSPITAL_NAME    AS hospital_name,
        PROCEDURE_GROUP  AS procedure_group,

        -- Total rows are recognised by exact value. 'All Other Procedures' is a
        -- procedure group, not a total.
        HEALTH_AUTHORITY = 'All Health Authorities' AS is_all_health_authorities,
        HOSPITAL_NAME    = 'All Facilities'         AS is_all_facilities,
        PROCEDURE_GROUP  = 'All Procedures'         AS is_all_procedures,

        TRY_CAST(WAITING AS INTEGER)              AS waiting,
        TRY_CAST(COMPLETED AS INTEGER)            AS completed,
        TRY_CAST(PERCENTILE_COMP_50TH AS DOUBLE)  AS p50_weeks,
        TRY_CAST(PERCENTILE_COMP_90TH AS DOUBLE)  AS p90_weeks,

        CASE
            WHEN TRY_CAST(WAITING AS INTEGER) IS NOT NULL THEN 'reported'
            WHEN WAITING = '<5'                           THEN 'suppressed'
            ELSE 'unexplained'
        END AS waiting_state,

        CASE
            WHEN TRY_CAST(COMPLETED AS INTEGER) IS NOT NULL THEN 'reported'
            WHEN COMPLETED = '<5'                           THEN 'suppressed'
            ELSE 'unexplained'
        END AS completed_state,

        PERCENTILE_COMP_50TH AS p50_literal,
        PERCENTILE_COMP_90TH AS p90_literal,

        is_interim,
        source_resource_id
    FROM combined
),

with_percentile_states AS (
    SELECT
        *,
        -- A blank percentile is read through COMPLETED in the same row:
        --   COMPLETED suppressed      -> the wait time went with it
        --   COMPLETED published as 0  -> no surgery was completed, so no wait
        --                                time exists
        --   anything else             -> unexplained
        CASE
            WHEN p50_weeks IS NOT NULL            THEN 'reported'
            WHEN p50_literal IS NOT NULL          THEN 'unexplained'
            WHEN completed_state = 'suppressed'   THEN 'suppressed'
            WHEN completed_state = 'reported'
                 AND completed = 0                THEN 'not_applicable'
            ELSE 'unexplained'
        END AS p50_state,

        CASE
            WHEN p90_weeks IS NOT NULL            THEN 'reported'
            WHEN p90_literal IS NOT NULL          THEN 'unexplained'
            WHEN completed_state = 'suppressed'   THEN 'suppressed'
            WHEN completed_state = 'reported'
                 AND completed = 0                THEN 'not_applicable'
            ELSE 'unexplained'
        END AS p90_state
    FROM classified
)

SELECT
    fiscal_year,
    quarter,
    health_authority,
    hospital_name,
    procedure_group,

    is_all_health_authorities,
    is_all_facilities,
    is_all_procedures,

    completed,
    completed_state,
    CASE completed_state WHEN 'reported' THEN completed WHEN 'suppressed' THEN 1 END
        AS completed_min,
    CASE completed_state WHEN 'reported' THEN completed WHEN 'suppressed' THEN 4 END
        AS completed_max,

    waiting,
    waiting_state,
    CASE waiting_state WHEN 'reported' THEN waiting WHEN 'suppressed' THEN 1 END
        AS waiting_min,
    CASE waiting_state WHEN 'reported' THEN waiting WHEN 'suppressed' THEN 4 END
        AS waiting_max,

    p50_weeks,
    p50_state,
    p90_weeks,
    p90_state,

    is_interim,
    source_resource_id
FROM with_percentile_states;


-- Diagnostic: what each file covers, and what the table covers ----------------
-- Run for the record, not by the build. The output is the evidence behind what
-- the data dictionary says about the gap.

SELECT
    CASE WHEN is_interim THEN 'interim' ELSE 'cumulative' END AS source,
    min(fiscal_year || ' ' || quarter) AS first_quarter,
    max(fiscal_year || ' ' || quarter) AS last_quarter,
    count(DISTINCT fiscal_year || ' ' || quarter) AS quarters,
    count(*) AS rows
FROM silver_quarterly
GROUP BY is_interim
UNION ALL
SELECT
    'combined',
    min(fiscal_year || ' ' || quarter),
    max(fiscal_year || ' ' || quarter),
    count(DISTINCT fiscal_year || ' ' || quarter),
    count(*)
FROM silver_quarterly
ORDER BY source;


-- Diagnostic: quarters missing between the first and the last -----------------
-- Every quarter from the first published one to the last is generated, then the
-- ones the table has are taken away. What is left is a gap: a quarter that sits
-- between two published quarters and was published by nobody.
--
-- Quarters after the last published one are left out. The fiscal year the data
-- ends in is still running, so its remaining quarters are not missing, they have
-- not happened yet. Counting them as gaps would bury the real gap in noise.
--
-- A fiscal year is written '2009/10', so it is built back from its start year.

WITH span AS (
    SELECT
        min(CAST(left(fiscal_year, 4) AS INTEGER)) AS first_year,
        max(CAST(left(fiscal_year, 4) AS INTEGER)) AS last_year,
        min(fiscal_year || ' ' || quarter)         AS first_quarter,
        max(fiscal_year || ' ' || quarter)         AS last_quarter
    FROM silver_quarterly
),

every_quarter AS (
    SELECT
        printf('%d/%02d', start_year, (start_year + 1) % 100) AS fiscal_year,
        quarter
    FROM span,
         generate_series(span.first_year, span.last_year) AS years(start_year),
         (VALUES ('Q1'), ('Q2'), ('Q3'), ('Q4')) AS quarters(quarter)
),

published AS (
    SELECT DISTINCT fiscal_year, quarter
    FROM silver_quarterly
)

SELECT
    every_quarter.fiscal_year,
    every_quarter.quarter
FROM every_quarter
CROSS JOIN span
LEFT JOIN published
    ON published.fiscal_year = every_quarter.fiscal_year
   AND published.quarter     = every_quarter.quarter
WHERE published.fiscal_year IS NULL
  AND every_quarter.fiscal_year || ' ' || every_quarter.quarter
      BETWEEN span.first_quarter AND span.last_quarter
ORDER BY every_quarter.fiscal_year, every_quarter.quarter;
