-- 01_silver_annual.sql
--
-- Silver: the annual file, typed and reshaped, with every withheld value
-- carried as an explicit state.
--
--     python src/run_sql.py sql/silver/01_silver_annual.sql data/warehouse.duckdb
--
-- Every measure becomes two or four columns:
--   <measure>        the published number. NULL unless the state is 'reported'.
--   <measure>_state  reported | suppressed | not_applicable | unexplained
--   <measure>_min    counts only: the smallest value the cell can stand for
--   <measure>_max    counts only: the largest
--
-- What the states mean, and why a blank percentile needs its neighbours to be
-- read before it can be classified, is in docs/data-dictionary.md. In short:
-- suppressed means a value exists and is hidden; not_applicable means no value
-- exists, because no surgeries were completed; unexplained means neither rule
-- fits and nothing here may quietly decide which one it is.
--
-- A suppressed count is bounded by 1 and 4. Those bounds are columns rather
-- than a rule in some later query, so that reconciliation can sum them
-- directly, and so that one edit here moves every downstream number if that
-- reading of the rule ever changes.
--
-- Percentiles get no bounds: a withheld percentile has no known range.

INSTALL excel;
LOAD excel;

SET VARIABLE annual_path = (
    SELECT local_path
    FROM read_json('data/raw/_manifest.json')
    WHERE resource_id = '6cd508eb-7e31-4c86-b070-dc698131fa9a'
);


CREATE OR REPLACE TABLE silver_annual AS

WITH raw AS (
    -- all_varchar: read what the cell actually holds, so that '<5' arrives as
    -- itself instead of as a failed conversion.
    -- stop_at_empty = false: the default stops at the first blank row.
    SELECT *
    FROM read_xlsx(getvariable('annual_path'),
        sheet = 'Sheet1', header = true, all_varchar = true, stop_at_empty = false)
    -- The file ends with 9,628 rows in which every column is empty.
    WHERE FISCAL_YEAR IS NOT NULL
),

classified AS (
    SELECT
        FISCAL_YEAR      AS fiscal_year,
        HEALTH_AUTHORITY AS health_authority,
        HOSPITAL_NAME    AS hospital_name,
        PROCEDURE_GROUP  AS procedure_group,

        -- Total rows are recognised by exact value. 'All Other Procedures' is a
        -- procedure group, not a total, so no pattern match is used anywhere in
        -- this pipeline.
        HEALTH_AUTHORITY = 'All Health Authorities' AS is_all_health_authorities,
        HOSPITAL_NAME    = 'All Facilities'         AS is_all_facilities,
        PROCEDURE_GROUP  = 'All Procedures'         AS is_all_procedures,

        TRY_CAST(WAITING AS INTEGER)              AS waiting,
        TRY_CAST(COMPLETED AS INTEGER)            AS completed,
        TRY_CAST(PERCENTILE_COMP_50TH AS DOUBLE)  AS p50_weeks,
        TRY_CAST(PERCENTILE_COMP_90TH AS DOUBLE)  AS p90_weeks,

        -- A count is either a number or the literal '<5'. Anything else is
        -- unexplained and must not be folded into either of those.
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
        PERCENTILE_COMP_90TH AS p90_literal
    FROM raw
),

with_percentile_states AS (
    SELECT
        *,
        -- A blank percentile is read through COMPLETED in the same row:
        --   COMPLETED suppressed      -> the wait time went with it
        --   COMPLETED published as 0  -> no surgery was completed, so no wait
        --                                time exists
        --   anything else             -> unexplained
        -- Text in a percentile column has never appeared; if it does, it is
        -- unexplained rather than silently dropped.
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

    -- Which published resource the row came from. Constant here, and the column
    -- that tells quarterly rows apart from interim ones in the next table.
    '6cd508eb-7e31-4c86-b070-dc698131fa9a' AS source_resource_id
FROM with_percentile_states;
