"""
Current-data assertions for the figures printed in docs/reconciliation-memo.md.

Separate from test_current_data.py because a failure here maps to a document
rather than to a layer: some sentence in the memo has gone stale, and each
docstring says which one. The memo is written for someone who will not rerun the
queries, so the numbers in it are pinned here instead.

**A failure means the data changed, not the code.** When it is a legitimate
change, the order is: rerun the query named in the docstring, edit the memo,
then edit the constant here. The constant is a copy of the document, which is
itself a copy of a query result.

The figures below were read from the files fetched 2026-09-15: quarterly
077444690d6e..., annual 2d9f99cbe4dd..., interim 5d801d6aabe8...
"""
import pytest

pytestmark = pytest.mark.realdata

# The staircase the memo opens with.
PROVINCE_PUBLISHED = 3_954_980
SUMMED_FROM_AUTHORITIES = 3_954_980
SUMMED_FROM_FACILITIES = 3_954_881
SUMMED_FROM_FACILITY_PROCEDURE = 3_838_549
FACILITY_PROCEDURE_BOUNDS = (3_893_778, 4_059_465)

# The counterweight: every total agrees with its own detail.
HIERARCHY_CHECKS = 101_862
CHECKS_OUTSIDE_BOUNDS = 0
CHECKS_NOT_CHECKABLE = 8_941
CHECKS_WITH_A_WITHHELD_CHILD = 47_576

# Completed cases, quarterly files, percent of cells withheld at each level.
WITHHELD_SHARE_BY_LEVEL = {
    "province": 0.2,
    "health authority": 11.7,
    "facility": 33.2,
}

# Rows where the annual figure falls outside what its four quarters allow, with
# the cases involved. Everything before 2020/21 agrees exactly.
VINTAGE_DISAGREEMENTS = {
    "2020/21": (25, 19),
    "2021/22": (42, 54),
    "2022/23": (67, 420),
    "2023/24": (155, 715),
    "2024/25": (385, 3_486),
}
VINTAGE_YEARS_IN_AGREEMENT = [
    "2009/10", "2010/11", "2011/12", "2012/13", "2013/14", "2014/15",
    "2015/16", "2016/17", "2017/18", "2018/19", "2019/20",
]


def test_the_staircase_the_memo_opens_with(warehouse):
    """Pins the memo's first sentence and the four-row table under it.

    116,431 cases, 2.9%, and the shape: exact by health authority, 99 cases by
    facility, the loss appearing only when the data is cut by procedure group. A
    failure means that opening is out of date. Rebuild and read
    sql/gold/20_reconciliation_quarterly.sql before editing either document.
    """
    published, by_authority, by_facility, by_leaf, leaf_lower, leaf_upper = (
        warehouse.sql("""
            SELECT
                (SELECT sum(completed) FROM silver_quarterly
                 WHERE is_all_health_authorities AND is_all_procedures),
                (SELECT sum(completed) FROM silver_quarterly
                 WHERE NOT is_all_health_authorities AND is_all_facilities
                   AND is_all_procedures),
                (SELECT sum(completed) FROM silver_quarterly
                 WHERE NOT is_all_facilities AND is_all_procedures),
                (SELECT sum(completed) FROM silver_quarterly
                 WHERE NOT is_all_health_authorities AND NOT is_all_facilities
                   AND NOT is_all_procedures),
                (SELECT sum(completed_min) FROM silver_quarterly
                 WHERE NOT is_all_health_authorities AND NOT is_all_facilities
                   AND NOT is_all_procedures),
                (SELECT sum(completed_max) FROM silver_quarterly
                 WHERE NOT is_all_health_authorities AND NOT is_all_facilities
                   AND NOT is_all_procedures)
        """).fetchone()
    )

    assert published == PROVINCE_PUBLISHED
    assert by_authority == SUMMED_FROM_AUTHORITIES, (
        "the memo says summing the health authorities gives the province figure "
        f"exactly; the two now differ by {published - by_authority}"
    )
    assert by_facility == SUMMED_FROM_FACILITIES
    assert by_leaf == SUMMED_FROM_FACILITY_PROCEDURE, (
        f"the memo's headline shortfall is "
        f"{PROVINCE_PUBLISHED - SUMMED_FROM_FACILITY_PROCEDURE} cases; it is now "
        f"{published - by_leaf}"
    )
    assert (leaf_lower, leaf_upper) == FACILITY_PROCEDURE_BOUNDS
    assert leaf_lower <= published <= leaf_upper, (
        "the published province total no longer sits inside the interval its own "
        "detail allows, which the memo states it does"
    )


def test_no_hierarchy_check_falls_outside_the_bounds(warehouse):
    """Pins the memo's counterweight: 101,862 checks, not one outside the bounds.

    This is the sentence that keeps the headline shortfall from reading as
    fault-finding: the published files are internally consistent to the case. A
    failure means a published total and its own detail stopped agreeing within
    what suppression allows, and the diagnostic at the end of
    sql/gold/20_reconciliation_quarterly.sql lists the rows.
    """
    checks, outside, not_checkable, with_withheld = warehouse.sql("""
        SELECT
            (SELECT count(*) FROM reconciliation_quarterly)
              + (SELECT count(*) FROM reconciliation_annual),
            (SELECT count(*) FROM reconciliation_quarterly WHERE NOT within_bounds)
              + (SELECT count(*) FROM reconciliation_annual WHERE NOT within_bounds),
            (SELECT count(*) FROM reconciliation_quarterly WHERE within_bounds IS NULL)
              + (SELECT count(*) FROM reconciliation_annual WHERE within_bounds IS NULL),
            (SELECT count(*) FROM reconciliation_quarterly
             WHERE implied_average IS NOT NULL)
    """).fetchone()

    assert outside == CHECKS_OUTSIDE_BOUNDS, (
        f"{outside} checks now fall outside the bounds; the memo says none do"
    )
    assert checks == HIERARCHY_CHECKS
    assert not_checkable == CHECKS_NOT_CHECKABLE
    assert with_withheld == CHECKS_WITH_A_WITHHELD_CHILD


def test_the_implied_average_stays_inside_the_band(warehouse):
    """Pins the memo's third evidence chain for reading '<5' as 1 to 4.

    The memo reports a gap per withheld child running 1.0 to 4.0 with a median
    of 2.0, and notes that no check implies an average below 1, which a
    suppressed zero would produce. A failure means that argument no longer
    holds; the suppression section of docs/data-dictionary.md lists the other
    two chains and needs revisiting with it.
    """
    lowest, highest, middle = warehouse.sql("""
        SELECT round(min(implied_average), 2), round(max(implied_average), 2),
               round(median(implied_average), 2)
        FROM reconciliation_quarterly WHERE implied_average IS NOT NULL
    """).fetchone()

    assert lowest >= 1.0, (
        f"a check implies {lowest} cases per withheld cell, below the 1 the "
        f"published rule guarantees"
    )
    assert highest <= 4.0
    assert (lowest, highest, middle) == (1.0, 4.0, 2.0)


def test_the_share_of_withheld_cells_by_level(warehouse):
    """Pins the shape the memo leads with: the loss is in the procedure dimension.

    "A third of those cells are withheld" in the memo's table of answerable
    questions is the 33.2% here. A failure means suppression moved between
    levels, which changes which questions the data can answer — the paragraph
    after the staircase table is what goes stale.
    """
    shares = dict(warehouse.sql("""
        SELECT
            CASE WHEN is_all_health_authorities THEN 'province'
                 WHEN is_all_facilities         THEN 'health authority'
                 ELSE 'facility' END AS level,
            round(100.0 * count(*) FILTER (WHERE completed_state = 'suppressed')
                  / count(*), 1)
        FROM silver_quarterly
        WHERE NOT is_all_procedures
        GROUP BY level
    """).fetchall())

    assert shares == WITHHELD_SHARE_BY_LEVEL


def test_the_vintage_curve(warehouse):
    """Pins the memo's second table: eleven years agreeing, then a rising curve.

    The rise by recency is the memo's evidence that these differences are
    restatement and not suppression, so the curve matters more than any single
    figure in it. A failure most likely means the quarterly file finally
    received its yearly update, in which case rerun sql/gold/22_vintage.sql and
    expect the whole curve to move.
    """
    curve = warehouse.sql("""
        SELECT fiscal_year,
               count(*) FILTER (WHERE NOT completed_explained_by_suppression),
               coalesce(sum(completed_gap)
                        FILTER (WHERE NOT completed_explained_by_suppression), 0)
        FROM vintage_annual_vs_quarterly
        WHERE completed_annual_state = 'reported'
        GROUP BY fiscal_year
        ORDER BY fiscal_year
    """).fetchall()
    measured = {year: (rows, int(cases)) for year, rows, cases in curve}

    for year in VINTAGE_YEARS_IN_AGREEMENT:
        assert measured[year] == (0, 0), (
            f"{year} agreed exactly between the two files; it now disagrees in "
            f"{measured[year][0]} rows"
        )

    for year, expected in VINTAGE_DISAGREEMENTS.items():
        assert measured[year] == expected, (
            f"{year}: the memo records {expected[0]} disagreeing rows and "
            f"{expected[1]} cases; the files now give {measured[year]}"
        )
