-- 11_fact_annual.sql
--
-- Gold: the annual facts, as views over silver_annual.
--
--     python src/run_sql.py sql/gold/11_fact_annual.sql data/warehouse.duckdb
--
-- The same three views as 10_fact_quarterly.sql, at fiscal year grain:
-- fact_volume_annual, fact_totals_annual, fact_percentile_annual. The reasoning
-- behind the split is written out there.
--
-- Kept separate from the quarterly views rather than unioned with a period_type
-- column, because a year and its own four quarters in one table is an addition
-- waiting to happen. A year of completed cases is the sum of its quarters; add
-- both and every surgery is counted twice.
--
-- cases_waiting_at_period_end means March 31 here and the quarter end there,
-- which is the publisher's definition and the reason it is never summed across
-- periods. docs/not-provided.md says what to do instead.
--
-- Two single-column keys for the report layer: facility_key and period_label.
-- Power BI relates tables on one column, and both of those dimensions are
-- identified by two. Both are deterministic joins of the natural key, not
-- surrogate keys — see sql/gold/02_dim_facility.sql.


CREATE OR REPLACE VIEW fact_volume_annual AS

SELECT
    fiscal_year,
    health_authority,
    hospital_name,
    procedure_group,
    health_authority || ' | ' || hospital_name AS facility_key,

    completed        AS completed_cases,
    completed_state,
    completed_min,
    completed_max,

    waiting          AS cases_waiting_at_period_end,
    waiting_state,
    waiting_min,
    waiting_max,

    source_resource_id
FROM silver_annual
WHERE NOT is_all_health_authorities
  AND NOT is_all_facilities
  AND NOT is_all_procedures;


CREATE OR REPLACE VIEW fact_totals_annual AS

SELECT
    fiscal_year,
    health_authority,
    hospital_name,
    procedure_group,
    health_authority || ' | ' || hospital_name AS facility_key,

    is_all_health_authorities,
    is_all_facilities,
    is_all_procedures,
    CASE
        WHEN is_all_health_authorities THEN 'province'
        WHEN is_all_facilities         THEN 'health authority'
        ELSE 'facility'
    END AS total_level,

    completed        AS completed_cases,
    completed_state,
    completed_min,
    completed_max,

    waiting          AS cases_waiting_at_period_end,
    waiting_state,
    waiting_min,
    waiting_max,

    source_resource_id
FROM silver_annual
WHERE is_all_health_authorities
   OR is_all_facilities
   OR is_all_procedures;


CREATE OR REPLACE VIEW fact_percentile_annual AS

SELECT
    fiscal_year,
    health_authority,
    hospital_name,
    procedure_group,
    health_authority || ' | ' || hospital_name AS facility_key,

    is_all_health_authorities,
    is_all_facilities,
    is_all_procedures,

    p50_weeks,
    p50_state,
    p90_weeks,
    p90_state,

    completed_state,

    source_resource_id
FROM silver_annual;
