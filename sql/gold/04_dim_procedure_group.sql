-- 04_dim_procedure_group.sql
--
-- Gold: the procedure group dimension, as a view over silver.
--
--     python src/run_sql.py sql/gold/04_dim_procedure_group.sql data/warehouse.duckdb
--
-- 85 values: 'All Procedures', the publisher's total, and 84 categories.
--
-- Two flags, because two of these names begin with the same word and mean
-- opposite things:
--   is_total      'All Procedures'. Summing the dimension without excluding it
--                 counts every surgery twice.
--   is_residual   'All Other Procedures'. A real category, everything not in a
--                 named group. Excluding it as though it were a total drops
--                 110,827 completed surgeries from the annual file, silently.
--
-- The flags exist so that no downstream query ever has to look at the name.
-- A filter written against the name is a filter that can be written as
-- LIKE 'All %', and that is the mistake this dimension is shaped to prevent.

CREATE OR REPLACE VIEW dim_procedure_group AS

WITH sightings AS (
    SELECT 'quarterly' AS source, procedure_group, fiscal_year, quarter
    FROM silver_quarterly
    WHERE NOT is_interim

    UNION ALL

    SELECT 'interim', procedure_group, fiscal_year, quarter
    FROM silver_quarterly
    WHERE is_interim

    UNION ALL

    SELECT 'annual', procedure_group, fiscal_year, NULL
    FROM silver_annual
)

SELECT
    procedure_group,
    procedure_group = 'All Procedures'       AS is_total,
    procedure_group = 'All Other Procedures' AS is_residual,

    bool_or(source = 'quarterly') AS in_quarterly_file,
    bool_or(source = 'interim')   AS in_interim_file,
    bool_or(source = 'annual')    AS in_annual_file,

    min(fiscal_year || ' ' || quarter) FILTER (WHERE source <> 'annual')
        AS first_quarter_seen,
    max(fiscal_year || ' ' || quarter) FILTER (WHERE source <> 'annual')
        AS last_quarter_seen
FROM sightings
GROUP BY procedure_group
ORDER BY procedure_group;
