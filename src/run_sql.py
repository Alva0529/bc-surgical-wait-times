"""
Run a SQL file against an in-memory DuckDB database and print every result.

Usage, from the repository root:
    python src/run_sql.py sql/profile/01_time_coverage.sql
"""
import sys
from pathlib import Path

import duckdb


def main():
    # The Windows console defaults to a legacy encoding that cannot print the
    # box-drawing characters DuckDB uses for result tables.
    sys.stdout.reconfigure(encoding="utf-8")

    sql = Path(sys.argv[1]).read_text(encoding="utf-8")
    connection = duckdb.connect()

    # Running the whole file at once would only return the last result. Each
    # statement runs separately, on the same connection, so variables and temp
    # tables from earlier statements stay available to later ones.
    for statement in duckdb.extract_statements(sql):
        result = connection.sql(statement.query)
        # Statements such as SET or CREATE return nothing to print.
        if result is not None:
            result.show(max_rows=1000, max_width=1000)


if __name__ == "__main__":
    main()
