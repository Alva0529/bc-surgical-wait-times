"""
Structural assertions: things that must hold whatever the published data says.

A failure here means the pipeline is wrong, not that the data changed. Facts
about one particular release of the data are asserted separately, in
test_current_data.py, so that an upstream change cannot be mistaken for a bug in
the code.

Every test runs against silver built from the committed fixtures, so it runs
anywhere, including CI, with no access to the published files.
"""
import pytest

TABLES = ["silver_annual", "silver_quarterly"]

GRAIN = {
    "silver_annual": ["fiscal_year", "health_authority", "hospital_name",
                      "procedure_group"],
    "silver_quarterly": ["fiscal_year", "quarter", "health_authority",
                         "hospital_name", "procedure_group"],
}

COUNTS = ["completed", "waiting"]
PERCENTILES = ["p50", "p90"]
STATES = ["reported", "suppressed", "not_applicable", "unexplained"]


def value_column(measure):
    """Counts keep their own name; percentiles carry their unit in theirs."""
    return measure if measure in COUNTS else f"{measure}_weeks"


@pytest.mark.parametrize("table", TABLES)
def test_grain_is_unique(silver, table):
    """Guards against a period, facility and procedure group appearing twice.

    A failure means either the precedence rule in
    sql/silver/02_silver_quarterly.sql let both copies of a quarter through, or
    a source file stopped being unique at its own key: rerun
    sql/profile/03_grain.sql to tell those apart.
    """
    key = ", ".join(GRAIN[table])
    rows, keys = silver.sql(
        f"SELECT count(*), count(DISTINCT ({key})) FROM {table}"
    ).fetchone()

    assert rows == keys, f"{table} has {rows} rows across {keys} distinct keys"


@pytest.mark.parametrize("table", TABLES)
def test_state_columns_hold_only_the_four_known_states(silver, table):
    """Guards against a typo or a new branch inventing a fifth state.

    A failure means a CASE expression in sql/silver/ produced a state nothing
    downstream knows how to read; the value printed is the one to search for.
    """
    allowed = ", ".join(f"'{state}'" for state in STATES)

    for measure in COUNTS + PERCENTILES:
        column = f"{measure}_state"
        unknown = silver.sql(
            f"SELECT DISTINCT {column} FROM {table} WHERE {column} NOT IN ({allowed})"
        ).fetchall()

        assert unknown == [], f"{table}.{column} holds unknown states: {unknown}"


@pytest.mark.parametrize("table", TABLES)
def test_a_value_is_present_exactly_when_its_state_is_reported(silver, table):
    """Guards against a withheld cell keeping a number, or a published one losing it.

    A failure means the value column and the state column disagree in
    sql/silver/, which would let a suppressed cell be summed as if it had been
    published.
    """
    for measure in COUNTS + PERCENTILES:
        column = value_column(measure)
        disagreements = silver.sql(f"""
            SELECT count(*) FROM {table}
            WHERE ({column} IS NOT NULL) <> ({measure}_state = 'reported')
        """).fetchone()[0]

        assert disagreements == 0, (
            f"{table}: {disagreements} rows where {column} and "
            f"{measure}_state disagree"
        )


@pytest.mark.parametrize("table", TABLES)
def test_suppressed_counts_are_bounded_by_1_and_4(silver, table):
    """Guards the bounds reconciliation depends on: a hidden count is 1 to 4.

    A failure means the CASE expressions in sql/silver/ changed, or the reading
    of the suppression rule did; the two evidence chains behind 1 and 4 are in
    docs/data-dictionary.md under the bounds requirement.
    """
    for measure in COUNTS:
        wrong_when_suppressed = silver.sql(f"""
            SELECT count(*) FROM {table}
            WHERE {measure}_state = 'suppressed'
              AND ({measure}_min IS DISTINCT FROM 1 OR {measure}_max IS DISTINCT FROM 4)
        """).fetchone()[0]
        assert wrong_when_suppressed == 0, (
            f"{table}: {wrong_when_suppressed} suppressed {measure} rows "
            f"are not bounded by 1 and 4"
        )

        wrong_when_reported = silver.sql(f"""
            SELECT count(*) FROM {table}
            WHERE {measure}_state = 'reported'
              AND ({measure}_min IS DISTINCT FROM {measure}
                   OR {measure}_max IS DISTINCT FROM {measure})
        """).fetchone()[0]
        assert wrong_when_reported == 0, (
            f"{table}: {wrong_when_reported} reported {measure} rows whose "
            f"bounds do not equal the published value"
        )


@pytest.mark.parametrize("table", TABLES)
def test_percentiles_carry_no_bounds(silver, table):
    """Guards against inventing a range for a withheld wait time.

    A suppressed count is known to be 1 to 4; a suppressed percentile has no
    known range at all. A failure means someone added bounds columns for the
    percentiles, and any reconciliation using them would be arithmetic over a
    made-up interval.
    """
    columns = [row[0] for row in silver.sql(f"DESCRIBE {table}").fetchall()]

    invented = [c for c in columns
                if c.startswith(tuple(PERCENTILES)) and c.endswith(("_min", "_max"))]
    assert invented == [], f"{table} has percentile bounds columns: {invented}"


@pytest.mark.parametrize("table", TABLES)
def test_all_other_procedures_is_not_treated_as_a_total(silver, table):
    """Guards the category whose name looks like a total: 'All Other Procedures'.

    Dropping it as a total removes 110,827 completed surgeries from the annual
    file and raises no error. A failure means total rows are being matched by
    pattern somewhere instead of by exact value.
    """
    mislabelled = silver.sql(f"""
        SELECT count(*) FROM {table}
        WHERE procedure_group = 'All Other Procedures' AND is_all_procedures
    """).fetchone()[0]
    assert mislabelled == 0, (
        f"{table}: 'All Other Procedures' is marked as a total in "
        f"{mislabelled} rows"
    )

    unmarked_totals = silver.sql(f"""
        SELECT count(*) FROM {table}
        WHERE procedure_group = 'All Procedures' AND NOT is_all_procedures
    """).fetchone()[0]
    assert unmarked_totals == 0, (
        f"{table}: {unmarked_totals} 'All Procedures' rows are not marked as totals"
    )


@pytest.mark.parametrize("table", TABLES)
def test_a_blank_percentile_is_classified_by_the_count_beside_it(silver, table):
    """Guards the distinction Step 5 rests on: withheld versus does not exist.

    A blank percentile means suppressed when COMPLETED is suppressed, not
    applicable when COMPLETED is a published zero, and unexplained otherwise. A
    failure means the CASE in sql/silver/ folded two of those together, which
    would let reconciliation count 'no surgery happened' as 'data was hidden'.
    """
    expected = {
        "suppressed": "completed_state = 'suppressed'",
        "not_applicable": "completed_state = 'reported' AND completed = 0",
        "unexplained": "completed_state = 'reported' AND completed >= 5",
    }

    for measure in PERCENTILES:
        for state, condition in expected.items():
            counts = silver.sql(f"""
                SELECT
                    count(*) FILTER (WHERE {measure}_state = '{state}') AS classified,
                    count(*) AS matching_rows
                FROM {table}
                WHERE {value_column(measure)} IS NULL AND {condition}
            """).fetchone()
            classified, matching_rows = counts

            # The fixture holds at least one row of each case. Without this the
            # test would pass on an empty table, which is the one situation it
            # should never pass in.
            assert matching_rows > 0, (
                f"{table}: the fixture no longer covers a blank {measure} where "
                f"{condition}; the rest of this assertion proves nothing"
            )
            assert classified == matching_rows, (
                f"{table}: {matching_rows - classified} blank {measure} rows "
                f"where {condition} are not classified as {state}"
            )


def test_the_cumulative_file_wins_a_quarter_the_interim_file_also_publishes(
    silver, fixture_rows
):
    """Guards the precedence rule, which the published files cannot test today.

    The cumulative and interim files do not currently overlap, so only the
    fixture exercises this. A failure means sql/silver/02_silver_quarterly.sql
    either kept provisional figures over settled ones, or dropped a quarter only
    the interim file publishes.
    """
    overlapping = ("2025/26", "Q1")
    interim_only = ("2025/26", "Q2")

    published_by_cumulative = next(
        row[6] for row in fixture_rows.QUARTERLY_ROWS
        if (row[0], row[1]) == overlapping and row[4] == "All Procedures"
    )

    kept, is_interim = silver.sql(f"""
        SELECT completed, is_interim FROM silver_quarterly
        WHERE fiscal_year = '{overlapping[0]}' AND quarter = '{overlapping[1]}'
          AND is_all_health_authorities AND is_all_procedures
    """).fetchone()

    assert kept == published_by_cumulative, (
        f"the overlapping quarter kept {kept}, but the cumulative file "
        f"publishes {published_by_cumulative}"
    )
    assert is_interim is False, "the overlapping quarter is still marked interim"

    interim_rows = silver.sql(f"""
        SELECT count(*), count(*) FILTER (WHERE is_interim) FROM silver_quarterly
        WHERE fiscal_year = '{interim_only[0]}' AND quarter = '{interim_only[1]}'
    """).fetchone()
    rows, marked_interim = interim_rows

    assert rows > 0, "the quarter only the interim file publishes was dropped"
    assert rows == marked_interim, (
        f"{rows - marked_interim} rows of an interim-only quarter are not "
        f"marked as interim"
    )


def test_blank_rows_are_not_loaded(silver, fixture_rows):
    """Guards against the annual file's trailing empty rows becoming data.

    The real file ends with 9,628 of them. A failure means the filter in
    sql/silver/01_silver_annual.sql stopped removing them, and every count in
    the warehouse now includes rows that hold nothing.
    """
    loaded = silver.sql("SELECT count(*) FROM silver_annual").fetchone()[0]
    assert loaded == len(fixture_rows.ANNUAL_ROWS), (
        f"silver_annual holds {loaded} rows, but the fixture defines "
        f"{len(fixture_rows.ANNUAL_ROWS)} data rows and "
        f"{fixture_rows.ANNUAL_BLANK_ROWS} blank ones"
    )

    empty = silver.sql("""
        SELECT count(*) FROM silver_annual
        WHERE coalesce(fiscal_year, health_authority, hospital_name,
                       procedure_group) IS NULL
    """).fetchone()[0]
    assert empty == 0, f"silver_annual holds {empty} rows with no dimensions"
