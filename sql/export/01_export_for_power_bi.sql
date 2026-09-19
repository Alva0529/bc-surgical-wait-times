-- 01_export_for_power_bi.sql
--
-- Export the gold layer as Parquet, for Power BI to import.
--
--     python src/run_sql.py sql/export/01_export_for_power_bi.sql data/warehouse.duckdb
--
-- Power BI has no official DuckDB connector, so the report reads files rather
-- than the warehouse. This is a snapshot for a tool, not a performance
-- decision, and docs/runbook.md sets the rules it has to meet: reproducible,
-- and carrying the sha256 of the published files it came from.
--
-- **Parquet, never CSV.** CSV writes NULL and the empty string identically. The
-- entire point of this pipeline is that a blank cell has three possible
-- meanings, carried in a state column beside a value that is NULL when and only
-- when nothing was published. Exporting through CSV would erase that in the
-- last step. Parquet keeps types and nulls exactly, and is a tenth of the size.
--
-- COPY is SQL, so nothing here needs pandas.
--
-- What is exported: the four dimensions, the three quarterly fact views, the
-- quarterly reconciliation, and a one-row provenance table. The annual views are
-- left out: the report is about the quarterly series, and importing a second
-- grain would double the model without adding to it.

-- Provenance, so that a screenshot carries its own origin ---------------------
-- A dashboard image outlives the machine it was made on. This table puts the
-- fetch date and the file checksums on the report page itself.

CREATE OR REPLACE VIEW export_about AS

WITH sources AS (
    SELECT
        resource_name,
        sha256,
        first_fetched_at_utc,
        last_fetched_at_utc,
        row_number() OVER (PARTITION BY resource_id
                           ORDER BY last_fetched_at_utc DESC) AS recency
    FROM read_json('data/raw/_manifest.json')
),

current_sources AS (
    SELECT resource_name, sha256, first_fetched_at_utc, last_fetched_at_utc
    FROM sources
    WHERE recency = 1
)

-- Two dates, because they mean different things. first_fetched is when this
-- version of the file appeared, which is the vintage of every number on the
-- report. last_fetched is only when it was last confirmed unchanged.
SELECT
    'BC Surgical Wait Times · file version '
        || strftime(max(CAST(first_fetched_at_utc AS TIMESTAMP)), '%Y-%m-%d')
        || ', confirmed unchanged '
        || strftime(max(CAST(last_fetched_at_utc AS TIMESTAMP)), '%Y-%m-%d')
        || ' · quarterly ' || min(left(sha256, 12))
        || ' · report built ' || strftime(now(), '%Y-%m-%d')
        AS provenance_line,
    count(*)                               AS source_files,
    string_agg(resource_name || ' (' || left(sha256, 12) || ')', E'\n'
               ORDER BY resource_name)     AS source_detail
FROM current_sources;


-- The exports ------------------------------------------------------------------

COPY (SELECT * FROM dim_quarter)
    TO 'data/export/dim_quarter.parquet' (FORMAT PARQUET);

COPY (SELECT * FROM dim_facility)
    TO 'data/export/dim_facility.parquet' (FORMAT PARQUET);

COPY (SELECT * FROM dim_health_authority)
    TO 'data/export/dim_health_authority.parquet' (FORMAT PARQUET);

COPY (SELECT * FROM dim_procedure_group)
    TO 'data/export/dim_procedure_group.parquet' (FORMAT PARQUET);

COPY (SELECT * FROM fact_volume_quarterly)
    TO 'data/export/fact_volume_quarterly.parquet' (FORMAT PARQUET);

COPY (SELECT * FROM fact_totals_quarterly)
    TO 'data/export/fact_totals_quarterly.parquet' (FORMAT PARQUET);

COPY (SELECT * FROM fact_percentile_quarterly)
    TO 'data/export/fact_percentile_quarterly.parquet' (FORMAT PARQUET);

COPY (SELECT * FROM reconciliation_quarterly)
    TO 'data/export/reconciliation_quarterly.parquet' (FORMAT PARQUET);

COPY (SELECT * FROM export_about)
    TO 'data/export/about.parquet' (FORMAT PARQUET);


-- The export manifest ----------------------------------------------------------
-- Row counts for what went out, and the checksums of the published files it all
-- came from. The parquet files' own checksums are not recorded: what a number
-- on a dashboard has to be traceable to is the published data, and that is what
-- the sha256 below identifies.

COPY (
    WITH sources AS (
        SELECT
            resource_id, resource_name, sha256,
            first_fetched_at_utc, last_fetched_at_utc,
            row_number() OVER (PARTITION BY resource_id
                               ORDER BY last_fetched_at_utc DESC) AS recency
        FROM read_json('data/raw/_manifest.json')
    ),

    exported AS (
        SELECT 'dim_quarter' AS view_name, count(*) AS rows FROM dim_quarter
        UNION ALL SELECT 'dim_facility', count(*) FROM dim_facility
        UNION ALL SELECT 'dim_health_authority', count(*) FROM dim_health_authority
        UNION ALL SELECT 'dim_procedure_group', count(*) FROM dim_procedure_group
        UNION ALL SELECT 'fact_volume_quarterly', count(*) FROM fact_volume_quarterly
        UNION ALL SELECT 'fact_totals_quarterly', count(*) FROM fact_totals_quarterly
        UNION ALL SELECT 'fact_percentile_quarterly', count(*) FROM fact_percentile_quarterly
        UNION ALL SELECT 'reconciliation_quarterly', count(*) FROM reconciliation_quarterly
        UNION ALL SELECT 'about', count(*) FROM export_about
    )

    SELECT
        strftime(now(), '%Y-%m-%dT%H:%M:%S%z') AS exported_at,
        (SELECT list({'view': view_name, 'rows': rows} ORDER BY view_name)
         FROM exported)                        AS exports,
        (SELECT list({'resource_name': resource_name,
                      'sha256': sha256,
                      'version_first_fetched_at_utc': first_fetched_at_utc,
                      'confirmed_unchanged_at_utc': last_fetched_at_utc}
                     ORDER BY resource_name)
         FROM sources WHERE recency = 1)       AS published_files
) TO 'data/export/_export_manifest.json' (FORMAT JSON, ARRAY true);


-- What went out ----------------------------------------------------------------

SELECT view_name, rows FROM (
    SELECT 'dim_quarter' AS view_name, count(*) AS rows FROM dim_quarter
    UNION ALL SELECT 'dim_facility', count(*) FROM dim_facility
    UNION ALL SELECT 'dim_health_authority', count(*) FROM dim_health_authority
    UNION ALL SELECT 'dim_procedure_group', count(*) FROM dim_procedure_group
    UNION ALL SELECT 'fact_volume_quarterly', count(*) FROM fact_volume_quarterly
    UNION ALL SELECT 'fact_totals_quarterly', count(*) FROM fact_totals_quarterly
    UNION ALL SELECT 'fact_percentile_quarterly', count(*) FROM fact_percentile_quarterly
    UNION ALL SELECT 'reconciliation_quarterly', count(*) FROM reconciliation_quarterly
    UNION ALL SELECT 'about', count(*) FROM export_about
) ORDER BY view_name;

SELECT provenance_line FROM export_about;
