-- 21_reconciliation_annual.sql
--
-- Gold: what suppression costs, at fiscal year grain.
--
--     python src/run_sql.py sql/gold/21_reconciliation_annual.sql data/warehouse.duckdb
--
-- The same three edges, the same columns and the same reasoning as
-- 20_reconciliation_quarterly.sql, which is where all of it is written out. The
-- only difference is the grain: no quarter column, and the annual file as the
-- source.
--
-- These are the checks that stay inside one file. The comparison that crosses
-- files — a fiscal year against the sum of its four quarters — is a different
-- question with a different cause, and lives in 22_vintage.sql.

CREATE OR REPLACE VIEW reconciliation_annual AS

WITH
-- The parent rows of each edge ------------------------------------------------
parents AS (
    SELECT 'procedures within a level' AS edge, *
    FROM silver_annual
    WHERE is_all_procedures

    UNION ALL

    SELECT 'province from authorities', *
    FROM silver_annual
    WHERE is_all_health_authorities

    UNION ALL

    SELECT 'authority from facilities', *
    FROM silver_annual
    WHERE NOT is_all_health_authorities AND is_all_facilities
),

-- The child rows of each edge, each labelled with the parent it belongs to -----
-- Only the labelling differs between edges. Everything after this is written
-- once.
children_rows AS (
    SELECT
        'procedures within a level' AS edge,
        fiscal_year, health_authority, hospital_name,
        'All Procedures' AS procedure_group,
        completed, completed_state, completed_min, completed_max,
        waiting, waiting_state, waiting_min, waiting_max
    FROM silver_annual
    WHERE NOT is_all_procedures

    UNION ALL

    SELECT
        'province from authorities',
        fiscal_year, 'All Health Authorities', 'All Facilities',
        procedure_group,
        completed, completed_state, completed_min, completed_max,
        waiting, waiting_state, waiting_min, waiting_max
    FROM silver_annual
    WHERE NOT is_all_health_authorities AND is_all_facilities

    UNION ALL

    SELECT
        'authority from facilities',
        fiscal_year, health_authority, 'All Facilities',
        procedure_group,
        completed, completed_state, completed_min, completed_max,
        waiting, waiting_state, waiting_min, waiting_max
    FROM silver_annual
    WHERE NOT is_all_health_authorities AND NOT is_all_facilities
),

-- Both measures, one row each ---------------------------------------------------
-- Long rather than wide: a check is about one measure, and a row per measure
-- keeps the result readable instead of carrying two parallel sets of columns.
measures AS (
    SELECT * FROM (VALUES
        ('completed_cases'),
        ('cases_waiting_at_period_end')
    ) AS m(measure)
),

children AS (
    SELECT
        edge,
        fiscal_year, health_authority, hospital_name, procedure_group,
        measure,
        count(*) AS children,
        count(*) FILTER (WHERE state = 'suppressed') AS children_suppressed,
        -- A child whose bounds are unknown makes the interval below incomplete.
        -- Counts are only ever reported or suppressed today, so this should be
        -- zero, and it is reported rather than assumed.
        count(*) FILTER (WHERE lower_bound IS NULL AND state <> 'reported')
            AS children_without_bounds,
        sum(value)       AS reported,
        sum(lower_bound) AS lower_bound,
        sum(upper_bound) AS upper_bound
    FROM (
        SELECT
            children_rows.edge,
            children_rows.fiscal_year,
            children_rows.health_authority, children_rows.hospital_name,
            children_rows.procedure_group,
            measures.measure,
            CASE measures.measure
                WHEN 'completed_cases' THEN completed      ELSE waiting       END AS value,
            CASE measures.measure
                WHEN 'completed_cases' THEN completed_state ELSE waiting_state END AS state,
            CASE measures.measure
                WHEN 'completed_cases' THEN completed_min  ELSE waiting_min   END AS lower_bound,
            CASE measures.measure
                WHEN 'completed_cases' THEN completed_max  ELSE waiting_max   END AS upper_bound
        FROM children_rows
        CROSS JOIN measures
    )
    GROUP BY edge, fiscal_year, health_authority, hospital_name,
             procedure_group, measure
),

published AS (
    SELECT
        parents.edge,
        parents.fiscal_year,
        parents.health_authority, parents.hospital_name, parents.procedure_group,
        measures.measure,
        CASE measures.measure
            WHEN 'completed_cases' THEN completed       ELSE waiting       END AS published,
        CASE measures.measure
            WHEN 'completed_cases' THEN completed_state ELSE waiting_state END AS parent_state
    FROM parents
    CROSS JOIN measures
)

SELECT
    published.edge,
    published.fiscal_year,
    published.health_authority,
    published.hospital_name,
    published.procedure_group,
    published.measure,

    published.parent_state,
    published.published,

    children.children,
    children.children_suppressed,
    children.children_without_bounds,

    children.reported,
    children.lower_bound,
    children.upper_bound,

    published.published - children.reported AS gap,
    published.published BETWEEN children.lower_bound AND children.upper_bound
        AS within_bounds,
    round((published.published - children.reported)
          / nullif(children.children_suppressed, 0), 2) AS implied_average

-- Parents lead: a published total with no children at all is itself a finding,
-- and an inner join would hide it.
FROM published
LEFT JOIN children
    ON  children.edge             = published.edge
    AND children.fiscal_year      = published.fiscal_year
    AND children.health_authority = published.health_authority
    AND children.hospital_name    = published.hospital_name
    AND children.procedure_group  = published.procedure_group
    AND children.measure          = published.measure;


-- Diagnostic: how many checks pass, by edge -----------------------------------
-- within_bounds is NULL when the parent itself was suppressed, so the check
-- could not be made. That is not a failure, and it is counted separately.

SELECT
    edge,
    measure,
    count(*)                                        AS checks,
    count(*) FILTER (WHERE within_bounds)           AS within_bounds,
    count(*) FILTER (WHERE NOT within_bounds)       AS outside_bounds,
    count(*) FILTER (WHERE within_bounds IS NULL)   AS not_checkable
FROM reconciliation_annual
GROUP BY edge, measure
ORDER BY edge, measure;


-- Diagnostic: the checks that fail --------------------------------------------
-- A gap outside what suppression can account for. These are the rows the memo
-- has to explain, not round off.

SELECT
    edge, fiscal_year, health_authority, hospital_name, procedure_group,
    measure, published, reported, lower_bound, upper_bound, gap,
    children, children_suppressed
FROM reconciliation_annual
WHERE NOT within_bounds
ORDER BY abs(gap) DESC
LIMIT 20;
