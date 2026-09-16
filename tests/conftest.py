"""
Test setup: build the silver tables from the committed fixture workbooks.

The silver SQL finds its source files through data/raw/_manifest.json, a path
relative to the working directory. So the fixtures are copied into data/raw/
under a temporary directory and the SQL is run from there, through
src/run_sql.py, the same entry point the project itself uses. Nothing in the SQL
or the runner knows it is being tested, which is the point: the tests exercise
the code that really runs.
"""
import shutil
import subprocess
import sys
from pathlib import Path

import duckdb
import pytest

REPO_ROOT = Path(__file__).resolve().parents[1]
FIXTURE_DIR = Path(__file__).resolve().parent / "fixtures"

SILVER_SQL = [
    REPO_ROOT / "sql" / "silver" / "01_silver_annual.sql",
    REPO_ROOT / "sql" / "silver" / "02_silver_quarterly.sql",
]

# The fixture rows are written out in tests/fixtures/build_fixtures.py. Tests
# import them from there rather than repeating a number the fixture already
# states, so editing the fixture cannot leave a test asserting the old figure.
sys.path.insert(0, str(FIXTURE_DIR))
import build_fixtures  # noqa: E402


@pytest.fixture(scope="session")
def fixture_rows():
    """The module holding the fixture's rows, for tests that need to count them."""
    return build_fixtures


@pytest.fixture(scope="session")
def silver(tmp_path_factory):
    """A read-only connection to silver tables built from the fixture workbooks.

    Session scoped: every test reads the same build, which keeps three workbook
    parses out of each test.
    """
    work_dir = tmp_path_factory.mktemp("fixture_warehouse")
    raw_dir = work_dir / "data" / "raw"
    raw_dir.mkdir(parents=True)

    for workbook in FIXTURE_DIR.glob("*.xlsx"):
        shutil.copy(workbook, raw_dir / workbook.name)
    shutil.copy(FIXTURE_DIR / "_manifest.json", raw_dir / "_manifest.json")

    database = work_dir / "fixture.duckdb"
    for sql_file in SILVER_SQL:
        result = subprocess.run(
            [sys.executable, str(REPO_ROOT / "src" / "run_sql.py"),
             str(sql_file), str(database)],
            cwd=work_dir, capture_output=True, text=True, encoding="utf-8",
        )
        # Raise with the SQL's own output. A silver build that fails to run is a
        # failure worth reading, not an exit code.
        if result.returncode != 0:
            raise RuntimeError(
                f"{sql_file.name} failed to build:\n{result.stdout}\n{result.stderr}"
            )

    connection = duckdb.connect(str(database), read_only=True)
    yield connection
    connection.close()
