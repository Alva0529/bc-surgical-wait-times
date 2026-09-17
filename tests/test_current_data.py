"""
Current-data assertions: facts about the published files as they stand today.

These are not statements about the pipeline. They pin what the Ministry
currently publishes, so that a change upstream is noticed rather than absorbed.
**A failure here means go and look at the data, not at the code.** The pipeline
is covered by test_silver_structure.py, which runs on fixtures and must pass
whatever the data does.

Every number below was established by the profiling queries in sql/profile/ and
is written up in docs/data-dictionary.md. When one of them legitimately changes,
rerun the profiling query named in the docstring, update the documentation, and
then update the number here.

The files profiled: fetched 2026-09-15, manifest sha256 starting 077444690d6e
(quarterly), 2d9f99cbe4dd (annual), 5d801d6aabe8 (interim).
"""
import pytest

pytestmark = pytest.mark.realdata

# Rows whose blank percentiles neither documented rule explains.
UNEXPLAINED_ROWS = {"silver_quarterly": 56, "silver_annual": 39}

# Hospitals per source, excluding the 'All Facilities' total.
HOSPITALS = {"cumulative": 65, "annual": 65, "interim": 59}

PROCEDURE_GROUPS = 85

LAST_CUMULATIVE_QUARTER = ("2024/25", "Q4")
INTERIM_QUARTER = ("2026/27", "Q1")
MISSING_QUARTERS = [("2025/26", quarter) for quarter in ("Q1", "Q2", "Q3", "Q4")]


def test_unexplained_rows_have_not_spread(warehouse):
    """Pins the 95 rows that neither suppression nor 'nothing completed' explains.

    A failure means the publisher's files changed: a phenomenon nobody
    understands has grown, shrunk or moved. Rerun sql/profile/02_suppression.sql
    section 7 and revisit Open question 5 in docs/data-dictionary.md before
    changing this number.
    """
    for table, expected in UNEXPLAINED_ROWS.items():
        found = warehouse.sql(
            f"SELECT count(*) FROM {table} WHERE p50_state = 'unexplained'"
        ).fetchone()[0]

        assert found == expected, (
            f"{table} holds {found} unexplained rows, documented as {expected}"
        )


def test_counts_are_never_unexplained(warehouse):
    """Pins that '<5' is still the only way a count is withheld.

    Every count is either a number or the literal '<5'. A failure means a new
    encoding appeared in WAITING or COMPLETED, which the suppression section of
    docs/data-dictionary.md and the bounds of 1 and 4 both rest on. Rerun
    sql/profile/02_suppression.sql section 3 to see the new literal.
    """
    for table in UNEXPLAINED_ROWS:
        for measure in ("completed", "waiting"):
            found = warehouse.sql(
                f"SELECT count(*) FROM {table} WHERE {measure}_state = 'unexplained'"
            ).fetchone()[0]

            assert found == 0, (
                f"{table}.{measure} has {found} cells that are neither a number "
                f"nor '<5'"
            )


def test_hospital_counts_per_source(warehouse):
    """Pins how many hospitals each file names, and that the interim file is short.

    The interim file covers one quarter, so hospitals with no rows in it are
    missing from it: that is why the hospital dimension is built from all three
    files. A failure means the roster changed, which is ordinary — hospitals
    open, close and get renamed. Check sql/profile/03_grain.sql section 4c and
    the dimension inventory in docs/data-dictionary.md.
    """
    counted = {
        "cumulative": """
            SELECT count(DISTINCT hospital_name) FROM silver_quarterly
            WHERE NOT is_interim AND NOT is_all_facilities
        """,
        "interim": """
            SELECT count(DISTINCT hospital_name) FROM silver_quarterly
            WHERE is_interim AND NOT is_all_facilities
        """,
        "annual": """
            SELECT count(DISTINCT hospital_name) FROM silver_annual
            WHERE NOT is_all_facilities
        """,
    }

    for source, query in counted.items():
        found = warehouse.sql(query).fetchone()[0]
        assert found == HOSPITALS[source], (
            f"{source} names {found} hospitals, documented as {HOSPITALS[source]}"
        )


def test_every_file_carries_the_same_85_procedure_groups(warehouse):
    """Pins the procedure group list, which the three files agree on.

    A failure means the publisher added, removed or renamed a group, or one file
    stopped carrying all of them. Either way the gold procedure dimension and
    the inventory in docs/data-dictionary.md need revisiting; rerun
    sql/profile/03_grain.sql section 3a to see which value moved.
    """
    per_source = warehouse.sql("""
        SELECT count(DISTINCT procedure_group) FROM silver_annual
        UNION ALL
        SELECT count(DISTINCT procedure_group) FROM silver_quarterly
        WHERE NOT is_interim
        UNION ALL
        SELECT count(DISTINCT procedure_group) FROM silver_quarterly
        WHERE is_interim
    """).fetchall()

    assert [row[0] for row in per_source] == [PROCEDURE_GROUPS] * 3, (
        f"procedure group counts are {[row[0] for row in per_source]}, "
        f"documented as {PROCEDURE_GROUPS} in every file"
    )


def test_quarterly_coverage_and_the_gap(warehouse):
    """Pins where the quarterly series starts, stops and breaks.

    A whole fiscal year of quarterly data, 2025/26, is published by no file: the
    cumulative file has not had its yearly update yet while the interim file has
    already moved on. A failure most likely means that update landed, which is
    the event Open question 2 in docs/data-dictionary.md is waiting for. Rerun
    the diagnostics at the end of sql/silver/02_silver_quarterly.sql.
    """
    last_cumulative = warehouse.sql("""
        SELECT fiscal_year, quarter FROM silver_quarterly
        WHERE NOT is_interim
        ORDER BY fiscal_year DESC, quarter DESC LIMIT 1
    """).fetchone()
    assert last_cumulative == LAST_CUMULATIVE_QUARTER, (
        f"the cumulative file now ends at {last_cumulative}, "
        f"documented as ending at {LAST_CUMULATIVE_QUARTER}"
    )

    interim_quarters = warehouse.sql("""
        SELECT DISTINCT fiscal_year, quarter FROM silver_quarterly WHERE is_interim
    """).fetchall()
    assert interim_quarters == [INTERIM_QUARTER], (
        f"the interim file now covers {interim_quarters}, "
        f"documented as covering {[INTERIM_QUARTER]}"
    )

    published = warehouse.sql(
        "SELECT DISTINCT fiscal_year, quarter FROM silver_quarterly"
    ).fetchall()
    still_missing = [quarter for quarter in MISSING_QUARTERS
                     if quarter not in published]
    assert still_missing == MISSING_QUARTERS, (
        f"of the documented gap {MISSING_QUARTERS}, only {still_missing} is "
        f"still missing"
    )


def test_published_totals_sit_inside_the_summed_bounds(warehouse):
    """Pins the result that makes reconciliation a conclusion rather than a guess.

    Adding up the per-cell bounds of the 84 procedure categories has to bracket
    the published All Procedures total, in every fiscal year. A failure means
    either the suppression rule changed or a published total no longer agrees
    with its own detail; sql/profile/03_grain.sql section 3b is the query that
    establishes this, and the bounds requirement in docs/data-dictionary.md is
    what rests on it.
    """
    outside = warehouse.sql("""
        WITH province AS (
            SELECT * FROM silver_annual
            WHERE is_all_health_authorities AND is_all_facilities
        ),
        by_year AS (
            SELECT
                fiscal_year,
                max(completed) FILTER (WHERE is_all_procedures)         AS published,
                sum(completed_min) FILTER (WHERE NOT is_all_procedures) AS lower_bound,
                sum(completed_max) FILTER (WHERE NOT is_all_procedures) AS upper_bound
            FROM province
            GROUP BY fiscal_year
        )
        SELECT fiscal_year, published, lower_bound, upper_bound
        FROM by_year
        WHERE published NOT BETWEEN lower_bound AND upper_bound
        ORDER BY fiscal_year
    """).fetchall()

    assert outside == [], (
        f"published totals fall outside the summed bounds in {outside}"
    )


def test_the_only_unpublished_quarters_are_the_documented_gap(warehouse):
    """Pins the gap as the model states it: 2025/26 Q1 to Q4 and nothing else.

    This is the documented gap turned into rows. A failure most likely means the
    cumulative file received its yearly update and the year filled in, which is
    the event Open question 2 in docs/data-dictionary.md waits for. Rerun the
    ingest, rebuild, and read the diagnostics in sql/gold/01_dim_period.sql
    before changing this list.
    """
    unpublished = warehouse.sql("""
        SELECT fiscal_year, quarter FROM dim_quarter
        WHERE NOT is_published ORDER BY starts_on
    """).fetchall()

    assert unpublished == MISSING_QUARTERS, (
        f"dim_quarter reports {unpublished} as unpublished, documented as "
        f"{MISSING_QUARTERS}"
    )


def test_the_facilities_missing_from_the_interim_file_are_retired_ones(warehouse):
    """Pins why the facility dimension is a union of all three files.

    Six facilities are in the historical files and not in the interim one, and
    none of them is merely idle: each stopped reporting before the interim
    quarter, the most recent in 2021/22 Q2. A failure means the roster changed —
    a facility closed, opened or was renamed — which is ordinary, and worth
    knowing about. Rerun the diagnostic at the end of
    sql/gold/02_dim_facility.sql.
    """
    absent = warehouse.sql("""
        SELECT hospital_name, last_quarter_seen FROM dim_facility
        WHERE NOT is_total AND NOT in_interim_file
        ORDER BY hospital_name
    """).fetchall()

    assert len(absent) == HOSPITALS["annual"] - HOSPITALS["interim"], (
        f"{len(absent)} facilities are absent from the interim file, documented "
        f"as {HOSPITALS['annual'] - HOSPITALS['interim']}"
    )

    interim_label = f"{INTERIM_QUARTER[0]} {INTERIM_QUARTER[1]}"
    still_active = [row for row in absent if row[1] >= interim_label]
    assert still_active == [], (
        f"these facilities are absent from the interim file but were reporting "
        f"in {interim_label}: {still_active}"
    )
