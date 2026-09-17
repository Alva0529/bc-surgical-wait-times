-- 22_vintage.sql
--
-- Gold: the same fact in two files, compared.
--
--     python src/run_sql.py sql/gold/22_vintage.sql data/warehouse.duckdb
--
-- 20 and 21 reconcile inside one file, where every difference has one candidate
-- cause: suppression. This one crosses files — a fiscal year against its own
-- four quarters — where suppression is not the only candidate and probably not
-- the main one. The two files were produced nine months apart (the quarterly
-- file saved 2025-11-04, the annual 2026-08-10), and the publisher states that
-- the dataset "is subject to restating, when necessary, to reflect current
-- reporting requirements".
--
-- Keeping this separate from 20 and 21 is the point. Folding it in would let a
-- restatement be counted as hidden data, and the reconciliation would then
-- report a suppression cost that is partly nine months of revisions.
--
-- Two comparisons, because the two measures behave differently:
--
--   completed_cases   a flow. The year should equal the sum of its quarters.
--                     Where quarterly cells are suppressed the sum falls short,
--                     so the year is compared against the quarterly bounds
--                     rather than the quarterly sum: inside them, suppression
--                     alone explains the difference; outside them, it cannot.
--
--   cases_waiting     a point-in-time count. A year is not the sum of its
--                     quarters, it is the count on 31 March, which is also what
--                     Q4 counts. So the comparison is against Q4, not a sum.
--                     docs/not-provided.md explains why no sum is offered.
--
-- Only fiscal years the quarterly file covers in full appear: a year with fewer
-- than four quarters is not comparable, and 2025/26 has no quarters at all.
-- Like 20 and 21, this is a report rather than a fact table. Its rows are
-- findings.

CREATE OR REPLACE VIEW vintage_annual_vs_quarterly AS

WITH quarterly_year AS (
    SELECT
        fiscal_year,
        health_authority,
        hospital_name,
        procedure_group,

        count(*)                                              AS quarters,
        count(*) FILTER (WHERE completed_state = 'suppressed') AS quarters_suppressed,

        sum(completed)     AS completed_reported,
        sum(completed_min) AS completed_lower,
        sum(completed_max) AS completed_upper,

        -- The year-end snapshot, for the measure that is not a sum.
        max(waiting)       FILTER (WHERE quarter = 'Q4') AS waiting_q4,
        max(waiting_state) FILTER (WHERE quarter = 'Q4') AS waiting_q4_state
    FROM silver_quarterly
    GROUP BY fiscal_year, health_authority, hospital_name, procedure_group
)

SELECT
    annual.fiscal_year,
    annual.health_authority,
    annual.hospital_name,
    annual.procedure_group,

    annual.is_all_health_authorities,
    annual.is_all_facilities,
    annual.is_all_procedures,

    quarterly_year.quarters_suppressed,

    annual.completed        AS completed_annual,
    annual.completed_state  AS completed_annual_state,
    quarterly_year.completed_reported,
    quarterly_year.completed_lower,
    quarterly_year.completed_upper,
    annual.completed - quarterly_year.completed_reported AS completed_gap,
    annual.completed BETWEEN quarterly_year.completed_lower
                         AND quarterly_year.completed_upper
        AS completed_explained_by_suppression,

    annual.waiting       AS waiting_annual,
    annual.waiting_state AS waiting_annual_state,
    quarterly_year.waiting_q4,
    quarterly_year.waiting_q4_state,
    annual.waiting - quarterly_year.waiting_q4 AS waiting_minus_q4

FROM silver_annual AS annual
JOIN quarterly_year
    ON  quarterly_year.fiscal_year      = annual.fiscal_year
    AND quarterly_year.health_authority = annual.health_authority
    AND quarterly_year.hospital_name    = annual.hospital_name
    AND quarterly_year.procedure_group  = annual.procedure_group
-- A partial year would look like a shortfall and mean nothing.
WHERE quarterly_year.quarters = 4;


-- Diagnostic: the province total, year by year --------------------------------
-- The headline version of the comparison. completed_explained_by_suppression is
-- false where the two files genuinely disagree.

SELECT
    fiscal_year,
    completed_annual,
    completed_reported,
    completed_gap,
    quarters_suppressed,
    completed_explained_by_suppression,
    waiting_annual,
    waiting_q4,
    waiting_minus_q4
FROM vintage_annual_vs_quarterly
WHERE is_all_health_authorities AND is_all_procedures
ORDER BY fiscal_year;


-- Diagnostic: how many rows the two files disagree about, by year -------------
-- Suppression cannot explain these. If the cause is restatement, recent years
-- should carry more of them than old ones.

SELECT
    fiscal_year,
    count(*)                                                        AS comparable_rows,
    count(*) FILTER (WHERE NOT completed_explained_by_suppression)  AS files_disagree,
    round(100.0 * count(*) FILTER (WHERE NOT completed_explained_by_suppression)
          / count(*), 2)                                            AS pct,
    sum(completed_gap) FILTER (WHERE NOT completed_explained_by_suppression)
                                                                    AS disagreement_cases
FROM vintage_annual_vs_quarterly
WHERE completed_annual_state = 'reported'
GROUP BY fiscal_year
ORDER BY fiscal_year;
