"""
Build the test fixtures: three small xlsx files shaped like the published ones,
plus a manifest that locates them by the same resource_ids as the real files.

    python tests/fixtures/build_fixtures.py

Both this script and the xlsx files it writes are committed. The xlsx is what
the tests read, so the tests exercise the real reading path, with text in a
number column, blank cells and trailing blank rows. This script is what anyone
reads to find out what is in the fixture, because a diff of an xlsx shows
nothing. When the publisher's encoding changes, edit the rows here and
regenerate. Never edit the xlsx by hand.

The rows are chosen to cover every case silver has to get right:

- each state: reported, suppressed ('<5'), not applicable (COMPLETED 0 with
  blank percentiles), unexplained (COMPLETED 5 or more with blank percentiles)
- a row where WAITING is suppressed but COMPLETED is not, whose percentiles are
  published, since the percentiles follow COMPLETED
- total rows at all three levels, and 'All Other Procedures', which is a
  category that looks like a total
- trailing blank rows in the annual file
- a quarter published in both the cumulative and the interim file, carrying
  different figures, so that the precedence rule has something to act on. The
  real files do not overlap today, so this is the only place that rule can be
  tested.
- a hospital that the interim file does not have, so that a dimension built
  from one file alone can be shown to be short
"""
import json
from pathlib import Path

from openpyxl import Workbook

# The real catalogue resource ids. The silver SQL looks files up by these, so
# the fixture manifest has to use the same ones for the tests to reach the
# fixture files without changing a line of the SQL.
QUARTERLY_ID = "f294562c-a6fd-4d7f-8f99-c51c91891c67"
ANNUAL_ID = "6cd508eb-7e31-4c86-b070-dc698131fa9a"
INTERIM_ID = "0c430fa8-043c-48d8-8e61-ecdab63b9ef3"

FIXTURE_DIR = Path(__file__).resolve().parent

ANNUAL_HEADER = [
    "FISCAL_YEAR", "HEALTH_AUTHORITY", "HOSPITAL_NAME", "PROCEDURE_GROUP",
    "WAITING", "COMPLETED", "PERCENTILE_COMP_50TH", "PERCENTILE_COMP_90TH",
]

QUARTERLY_HEADER = [
    "FISCAL_YEAR", "QUARTER", "HEALTH_AUTHORITY", "HOSPITAL_NAME",
    "PROCEDURE_GROUP", "WAITING", "COMPLETED",
    "PERCENTILE_COMP_50TH", "PERCENTILE_COMP_90TH",
]

# Annual file ------------------------------------------------------------------
# None is a blank cell. '<5' is the publisher's suppression marker.

ANNUAL_ROWS = [
    # Province totals, and the category that looks like one.
    ("2023/24", "All Health Authorities", "All Facilities", "All Procedures", 96759, 277896, 5.9, 28.4),
    ("2023/24", "All Health Authorities", "All Facilities", "All Other Procedures", 1984, 8209, 4.2, 18.7),
    ("2023/24", "All Health Authorities", "All Facilities", "Cataract Surgery", 18712, 60123, 5.7, 22.1),
    # Health authority level.
    ("2023/24", "Interior", "All Facilities", "All Procedures", 18234, 52310, 6.1, 29.5),
    # Both counts suppressed, percentiles gone with them.
    ("2023/24", "Interior", "All Facilities", "Hernia Repair - Chest Wall", "<5", "<5", None, None),
    # Hospital level.
    ("2023/24", "Interior", "Elk Valley Hospital", "All Procedures", 210, 640, 4.4, 17.2),
    # Unexplained: surgeries were completed, and the percentiles are blank anyway.
    ("2023/24", "Interior", "Elk Valley Hospital", "Uterine Surgery", 6, 15, None, None),
    # WAITING suppressed, COMPLETED published: the percentiles stay.
    ("2023/24", "Interior", "Elk Valley Hospital", "Appendectomy", "<5", 9, 1.9, 8.2),
    # Not applicable: nothing was completed, so no wait time exists.
    ("2023/24", "Northern", "G.R. Baker Memorial Hospital", "Dental Surgery", 5, 0, None, None),
    ("2023/24", "Northern", "G.R. Baker Memorial Hospital", "All Procedures", 88, 260, 5.0, 20.0),
    # A hospital the interim file does not have.
    ("2023/24", "Northern", "Kitimat General Hospital", "Biopsy in OR", 12, 34, 2.6, 9.9),

    ("2024/25", "All Health Authorities", "All Facilities", "All Procedures", 95200, 289812, 6.0, 29.1),
    ("2024/25", "All Health Authorities", "All Facilities", "All Other Procedures", 2103, 9345, 4.4, 19.2),
    ("2024/25", "Interior", "All Facilities", "Cataract Surgery", 4102, 12050, 5.2, 21.7),
    ("2024/25", "Interior", "Elk Valley Hospital", "Uterine Surgery", 8, 31, None, None),
    # Suppressed WAITING next to a published zero: still not applicable.
    ("2024/25", "Northern", "G.R. Baker Memorial Hospital", "Dental Surgery", "<5", 0, None, None),
]

# The real annual file ends with thousands of rows in which every cell is empty.
ANNUAL_BLANK_ROWS = 3

# Quarterly cumulative file ----------------------------------------------------
# 2025/26 Q1 is also in the interim file, with different figures.

QUARTERLY_ROWS = [
    ("2024/25", "Q4", "All Health Authorities", "All Facilities", "All Procedures", 95576, 73117, 6.2, 30.0),
    ("2024/25", "Q4", "All Health Authorities", "All Facilities", "All Other Procedures", 2260, 2372, 4.3, 18.9),
    ("2024/25", "Q4", "Interior", "All Facilities", "All Procedures", 17980, 13640, 6.3, 30.4),
    ("2024/25", "Q4", "Interior", "Elk Valley Hospital", "Uterine Surgery", 7, 9, None, None),
    ("2024/25", "Q4", "Interior", "Elk Valley Hospital", "Appendectomy", "<5", "<5", None, None),
    ("2024/25", "Q4", "Northern", "G.R. Baker Memorial Hospital", "Dental Surgery", 6, 0, None, None),
    ("2024/25", "Q4", "Northern", "Kitimat General Hospital", "Biopsy in OR", 9, 11, 2.4, 9.1),

    # The overlapping quarter, as published in the cumulative file. These are the
    # figures silver has to keep.
    ("2025/26", "Q1", "All Health Authorities", "All Facilities", "All Procedures", 97000, 74000, 6.3, 30.3),
    ("2025/26", "Q1", "Interior", "Elk Valley Hospital", "Appendectomy", 7, 12, 2.0, 8.0),
    ("2025/26", "Q1", "Northern", "G.R. Baker Memorial Hospital", "All Procedures", 91, 240, 5.1, 19.8),
]

# Interim file -----------------------------------------------------------------
# 2025/26 Q1 repeats the quarter above with provisional figures, which silver
# must drop. 2025/26 Q2 is the interim file's own quarter, which silver keeps.

INTERIM_ROWS = [
    ("2025/26", "Q1", "All Health Authorities", "All Facilities", "All Procedures", 96000, 70000, 6.9, 31.0),
    ("2025/26", "Q1", "Interior", "Elk Valley Hospital", "Appendectomy", 6, 10, 2.4, 9.1),
    ("2025/26", "Q1", "Northern", "G.R. Baker Memorial Hospital", "All Procedures", 89, 232, 5.4, 20.2),

    ("2025/26", "Q2", "All Health Authorities", "All Facilities", "All Procedures", 98500, 71500, 7.1, 32.4),
    ("2025/26", "Q2", "All Health Authorities", "All Facilities", "All Other Procedures", 2410, 2190, 4.6, 19.9),
    ("2025/26", "Q2", "Interior", "Elk Valley Hospital", "Appendectomy", "<5", 8, 2.2, 8.8),
    ("2025/26", "Q2", "Interior", "Elk Valley Hospital", "Uterine Surgery", 5, 13, None, None),
    ("2025/26", "Q2", "Northern", "G.R. Baker Memorial Hospital", "Dental Surgery", "<5", "<5", None, None),
]


def write_workbook(path, header, rows, blank_rows=0):
    """Write one sheet named Sheet1, like the published files."""
    workbook = Workbook()
    sheet = workbook.active
    sheet.title = "Sheet1"

    sheet.append(header)
    for row in rows:
        sheet.append(list(row))
    for _ in range(blank_rows):
        sheet.append([None] * len(header))

    workbook.save(path)
    return path.name


def main():
    annual = write_workbook(
        FIXTURE_DIR / "annual_fixture.xlsx", ANNUAL_HEADER, ANNUAL_ROWS,
        blank_rows=ANNUAL_BLANK_ROWS,
    )
    quarterly = write_workbook(
        FIXTURE_DIR / "quarterly_fixture.xlsx", QUARTERLY_HEADER, QUARTERLY_ROWS,
    )
    interim = write_workbook(
        FIXTURE_DIR / "interim_fixture.xlsx", QUARTERLY_HEADER, INTERIM_ROWS,
    )

    # Same shape as the real manifest, and the same resource ids. local_path is
    # relative, because the tests copy this directory to data/raw/ under a
    # temporary working directory and run the silver SQL there.
    manifest = [
        {
            "resource_id": QUARTERLY_ID,
            "resource_name": "Quarterly fixture",
            "local_path": f"data/raw/{quarterly}",
        },
        {
            "resource_id": ANNUAL_ID,
            "resource_name": "Annual fixture",
            "local_path": f"data/raw/{annual}",
        },
        {
            "resource_id": INTERIM_ID,
            "resource_name": "Interim fixture",
            "local_path": f"data/raw/{interim}",
        },
    ]
    (FIXTURE_DIR / "_manifest.json").write_text(json.dumps(manifest, indent=2))

    print(f"wrote {annual} ({len(ANNUAL_ROWS)} rows + {ANNUAL_BLANK_ROWS} blank)")
    print(f"wrote {quarterly} ({len(QUARTERLY_ROWS)} rows)")
    print(f"wrote {interim} ({len(INTERIM_ROWS)} rows)")
    print("wrote _manifest.json")


if __name__ == "__main__":
    main()
