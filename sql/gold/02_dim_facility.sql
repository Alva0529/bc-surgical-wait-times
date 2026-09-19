-- 02_dim_facility.sql
--
-- Gold: the facility dimension, as a view over silver.
--
--     python src/run_sql.py sql/gold/02_dim_facility.sql data/warehouse.duckdb
--
-- Built from all three published files, not one. The interim file names 59
-- facilities where the other two name 65, and the six it leaves out are not
-- idle for a quarter: they stopped reporting altogether, the most recent in
-- 2021/22 Q2 and the oldest in 2009/10 Q3. Five other facilities appear partway
-- through the series, the newest in 2021/22 Q2. The roster changes over
-- seventeen years, which is exactly why a dimension built from the current
-- quarter would fail to join most of the history.
--
-- Key: health authority and facility name together. Every real facility belongs
-- to exactly one health authority, checked over both silver tables. The one
-- name that spans them is 'All Facilities', the publisher's total, which means
-- something different under each health authority, and that composite key keeps
-- those apart without a special case.
--
-- The source flags answer a question the facts cannot: when a facility has no
-- rows in a period, was nothing done, or is the facility absent from that file
-- altogether? Those look identical in a report. in_interim_file = false says it
-- is the second, and the columns ending in _seen say when the facility was
-- reporting at all, which is what tells a closed hospital from a quiet one.
--
--
-- facility_key is the natural key written as one column: health authority, a
-- pipe, and facility name. Power BI relates tables on a single column only, and
-- a facility is identified by two. It is not a surrogate key: nothing is
-- numbered, nothing is allocated, and rebuilding the warehouse produces the
-- same value for the same facility. docs/conventions.md says why that
-- distinction matters.
--
-- What they still cannot settle: a facility that is in a file, within its range,
-- and has no rows for one period. The published data does not distinguish "no
-- surgeries" from "not reported" there, and nothing here invents the
-- difference. docs/not-provided.md records that.

CREATE OR REPLACE VIEW dim_facility AS

WITH sightings AS (
    SELECT 'quarterly' AS source, health_authority, hospital_name,
           fiscal_year, quarter
    FROM silver_quarterly
    WHERE NOT is_interim

    UNION ALL

    SELECT 'interim', health_authority, hospital_name, fiscal_year, quarter
    FROM silver_quarterly
    WHERE is_interim

    UNION ALL

    SELECT 'annual', health_authority, hospital_name, fiscal_year, NULL
    FROM silver_annual
)

SELECT
    health_authority,
    hospital_name,
    health_authority || ' | ' || hospital_name AS facility_key,
    hospital_name = 'All Facilities' AS is_total,

    bool_or(source = 'quarterly') AS in_quarterly_file,
    bool_or(source = 'interim')   AS in_interim_file,
    bool_or(source = 'annual')    AS in_annual_file,

    min(fiscal_year || ' ' || quarter) FILTER (WHERE source <> 'annual')
        AS first_quarter_seen,
    max(fiscal_year || ' ' || quarter) FILTER (WHERE source <> 'annual')
        AS last_quarter_seen,
    min(fiscal_year) FILTER (WHERE source = 'annual') AS first_fiscal_year_seen,
    max(fiscal_year) FILTER (WHERE source = 'annual') AS last_fiscal_year_seen
FROM sightings
GROUP BY health_authority, hospital_name
ORDER BY health_authority, hospital_name;


-- Diagnostic: the facilities the interim file does not name -------------------
-- This is the reason the dimension is a union: each of these has history, and
-- none of them reports any more.

SELECT health_authority, hospital_name, first_quarter_seen, last_quarter_seen
FROM dim_facility
WHERE NOT in_interim_file AND NOT is_total
ORDER BY health_authority, hospital_name;
