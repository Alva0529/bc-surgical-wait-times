-- 03_dim_health_authority.sql
--
-- Gold: the health authority dimension, as a view over silver.
--
--     python src/run_sql.py sql/gold/03_dim_health_authority.sql data/warehouse.duckdb
--
-- Six health authorities, plus 'All Health Authorities', the publisher's
-- province-wide total. The total is a member of the dimension rather than
-- something computed, because the published province figures are not the sum of
-- the six: suppression keeps them apart, and the percentiles exist only where
-- they were published.
--
-- is_total is the column that keeps a query honest. Summing over this dimension
-- without excluding it counts the province twice.
--
-- Built from all three files for the same reason as dim_facility, though all
-- three name the same authorities today. The source flags say which files an
-- authority appears in, so an authority that stops being published shows up as
-- a row saying so rather than vanishing.

CREATE OR REPLACE VIEW dim_health_authority AS

WITH sightings AS (
    SELECT 'quarterly' AS source, health_authority, fiscal_year, quarter
    FROM silver_quarterly
    WHERE NOT is_interim

    UNION ALL

    SELECT 'interim', health_authority, fiscal_year, quarter
    FROM silver_quarterly
    WHERE is_interim

    UNION ALL

    SELECT 'annual', health_authority, fiscal_year, NULL
    FROM silver_annual
)

SELECT
    health_authority,
    health_authority = 'All Health Authorities' AS is_total,

    bool_or(source = 'quarterly') AS in_quarterly_file,
    bool_or(source = 'interim')   AS in_interim_file,
    bool_or(source = 'annual')    AS in_annual_file,

    min(fiscal_year || ' ' || quarter) FILTER (WHERE source <> 'annual')
        AS first_quarter_seen,
    max(fiscal_year || ' ' || quarter) FILTER (WHERE source <> 'annual')
        AS last_quarter_seen
FROM sightings
GROUP BY health_authority
ORDER BY health_authority;
