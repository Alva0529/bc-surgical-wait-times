-- 01_dim_period.sql
--
-- Gold: the period dimensions, as views over silver.
--
--     python src/run_sql.py sql/gold/01_dim_period.sql data/warehouse.duckdb
--
-- Two views, not one. A fiscal year and a fiscal quarter are different grains,
-- and a dimension holding both invites a query that adds a year to its own four
-- quarters. The quarterly facts join dim_quarter, the annual facts join
-- dim_fiscal_year, and nothing has to remember a rule.
--
-- Both list every period from the first published one to the last, published or
-- not. A period nobody published is a row with is_published = false, not an
-- absent row. That is the whole point of the dimension: it turns a warning in
-- the documentation into a fact in the model. A trend line drawn from this
-- dimension cannot run straight across 2025/26 without showing that the year is
-- empty.
--
-- Periods after the last published one are left out. The fiscal year in
-- progress has not happened yet, so its remaining quarters are not missing, and
-- a dimension that called them missing would cry wolf every year.
--
-- Natural keys: a period is identified by the values the publisher uses,
-- '2009/10' and 'Q1'. docs/runbook.md records why there are no surrogate keys.
--
-- Quarter boundaries are the publisher's: Q1 April to June, Q2 July to
-- September, Q3 October to December, Q4 January to March of the next calendar
-- year.

CREATE OR REPLACE VIEW dim_quarter AS

WITH published AS (
    SELECT
        fiscal_year,
        quarter,
        -- A quarter is interim if its rows came from the interim file, whose
        -- figures can still be revised.
        bool_or(is_interim) AS is_interim
    FROM silver_quarterly
    GROUP BY fiscal_year, quarter
),

span AS (
    SELECT
        min(CAST(left(fiscal_year, 4) AS INTEGER)) AS first_year,
        max(CAST(left(fiscal_year, 4) AS INTEGER)) AS last_year
    FROM published
),

calendar AS (
    SELECT
        printf('%d/%02d', start_year, (start_year + 1) % 100) AS fiscal_year,
        'Q' || quarter_number                                 AS quarter,
        CASE quarter_number
            WHEN 1 THEN make_date(start_year, 4, 1)
            WHEN 2 THEN make_date(start_year, 7, 1)
            WHEN 3 THEN make_date(start_year, 10, 1)
            WHEN 4 THEN make_date(start_year + 1, 1, 1)
        END AS starts_on,
        CASE quarter_number
            WHEN 1 THEN make_date(start_year, 6, 30)
            WHEN 2 THEN make_date(start_year, 9, 30)
            WHEN 3 THEN make_date(start_year, 12, 31)
            WHEN 4 THEN make_date(start_year + 1, 3, 31)
        END AS ends_on
    FROM span,
         generate_series(span.first_year, span.last_year) AS years(start_year),
         generate_series(1, 4) AS quarters(quarter_number)
),

-- The end of the last quarter anybody published. Everything after it is the
-- future, not a gap.
last_published AS (
    SELECT max(calendar.ends_on) AS ends_on
    FROM calendar
    JOIN published
        ON published.fiscal_year = calendar.fiscal_year
       AND published.quarter     = calendar.quarter
)

SELECT
    calendar.fiscal_year,
    calendar.quarter,
    calendar.fiscal_year || ' ' || calendar.quarter AS period_label,
    calendar.starts_on,
    calendar.ends_on,
    published.quarter IS NOT NULL         AS is_published,
    coalesce(published.is_interim, false) AS is_interim
FROM calendar
LEFT JOIN published
    ON published.fiscal_year = calendar.fiscal_year
   AND published.quarter     = calendar.quarter
CROSS JOIN last_published
WHERE calendar.ends_on <= last_published.ends_on
ORDER BY calendar.starts_on;


CREATE OR REPLACE VIEW dim_fiscal_year AS

WITH published AS (
    SELECT DISTINCT fiscal_year
    FROM silver_annual
),

span AS (
    SELECT
        min(CAST(left(fiscal_year, 4) AS INTEGER)) AS first_year,
        max(CAST(left(fiscal_year, 4) AS INTEGER)) AS last_year
    FROM published
),

calendar AS (
    SELECT
        printf('%d/%02d', start_year, (start_year + 1) % 100) AS fiscal_year,
        make_date(start_year, 4, 1)                           AS starts_on,
        make_date(start_year + 1, 3, 31)                      AS ends_on
    FROM span,
         generate_series(span.first_year, span.last_year) AS years(start_year)
)

-- Built the same way as dim_quarter, though the annual file has no gaps today.
-- A year that stops being published should appear as a row saying so, not
-- disappear.
SELECT
    calendar.fiscal_year,
    calendar.starts_on,
    calendar.ends_on,
    published.fiscal_year IS NOT NULL AS is_published
FROM calendar
LEFT JOIN published
    ON published.fiscal_year = calendar.fiscal_year
ORDER BY calendar.starts_on;


-- Diagnostic: the periods the model says nobody published ----------------------

SELECT fiscal_year, quarter, starts_on, ends_on
FROM dim_quarter
WHERE NOT is_published
ORDER BY starts_on;

SELECT
    count(*)                                AS quarters,
    count(*) FILTER (WHERE is_published)    AS published,
    count(*) FILTER (WHERE is_interim)      AS interim,
    min(period_label)                       AS first_quarter,
    max(period_label)                       AS last_quarter
FROM dim_quarter;
