-- 10_fact_quarterly.sql
--
-- Gold: the quarterly facts, as views over silver_quarterly.
--
--     python src/run_sql.py sql/gold/10_fact_quarterly.sql data/warehouse.duckdb
--
-- Three views, split by what can safely be done to them:
--
--   fact_volume_quarterly      leaf rows only: one health authority, one
--                              facility, one procedure group. Summing it is
--                              always meaningful, because it holds nothing else.
--   fact_totals_quarterly      the publisher's own total rows. Look one up;
--                              never add them together.
--   fact_percentile_quarterly  published wait times at every level. Look up,
--                              never aggregate.
--
-- Why split at all: the publisher's totals are data, not something derivable.
-- Suppression means a total does not equal the sum of its parts, and the
-- percentiles exist only where they were published. So the totals have to be
-- kept — and the moment they sit beside the detail, SELECT sum(completed_cases)
-- counts every surgery twice and raises no error. Splitting makes the default
-- correct.
--
-- Why the percentiles are not split by level as well: the split exists to stop
-- double counting under a sum, and there is no legitimate sum of a percentile
-- at any level. What protects that view is that it carries no additive measure
-- at all. Filter it to the level you want and read the value.
--
-- Counts carry their bounds: a suppressed count is between 1 and 4, and
-- reconciliation sums the bounds rather than guessing. See the bounds
-- requirement in docs/data-dictionary.md.
--
-- Natural keys throughout: the facts join the dimensions on the publisher's own
-- values. docs/runbook.md records why there are no surrogate keys, and
-- docs/not-provided.md what this model deliberately leaves out.


CREATE OR REPLACE VIEW fact_volume_quarterly AS

SELECT
    fiscal_year,
    quarter,
    health_authority,
    hospital_name,
    procedure_group,

    completed        AS completed_cases,
    completed_state,
    completed_min,
    completed_max,

    waiting          AS cases_waiting_at_period_end,
    waiting_state,
    waiting_min,
    waiting_max,

    is_interim,
    source_resource_id
FROM silver_quarterly
-- Leaf rows only. Every total the publisher provides lives in the next view.
WHERE NOT is_all_health_authorities
  AND NOT is_all_facilities
  AND NOT is_all_procedures;


CREATE OR REPLACE VIEW fact_totals_quarterly AS

SELECT
    fiscal_year,
    quarter,
    health_authority,
    hospital_name,
    procedure_group,

    -- Which totals this row is a total of. Always filter on these before
    -- aggregating anything: the province row, the six health authority rows and
    -- the facility rows are all in here, and they overlap completely.
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

    is_interim,
    source_resource_id
FROM silver_quarterly
WHERE is_all_health_authorities
   OR is_all_facilities
   OR is_all_procedures;


CREATE OR REPLACE VIEW fact_percentile_quarterly AS

SELECT
    fiscal_year,
    quarter,
    health_authority,
    hospital_name,
    procedure_group,

    is_all_health_authorities,
    is_all_facilities,
    is_all_procedures,

    p50_weeks,
    p50_state,
    p90_weeks,
    p90_state,

    -- No count values here, on purpose: this view holds nothing that can be
    -- summed. completed_state is carried because it is what explains a missing
    -- percentile — suppressed with its count, or not applicable because nothing
    -- was completed.
    completed_state,

    is_interim,
    source_resource_id
FROM silver_quarterly;
