# Runbook

## Running SQL files

From the repository root:

```bash
python src/run_sql.py sql/profile/01_time_coverage.sql
```

The script runs every statement in the file, in order, on one in-memory DuckDB
connection, and prints each result.

The first run downloads DuckDB's excel extension (`INSTALL excel`). This needs
network access, on CI as well.

## Official sources

The official text quoted in `README.md` and `docs/data-dictionary.md` was read
on 2026-09-15. When a new release lands, re-read both sources and update the
quotes if the wording has changed.

- **Data rules:** the catalogue dataset description. Read it through the API
  (`package_show` with `id=bc-surgical-wait-times`, field `notes`).
- **Data lineage:** the Ministry of Health page,
  https://www2.gov.bc.ca/gov/content/health/accessing-health-care/surgical-wait-times

### Known broken link

- The catalogue's "more info" link for this dataset,
  `https://swt.hlth.gov.bc.ca/`, returned **HTTP 404** on 2026-09-15 (so did
  `/about`). It is still listed in the catalogue metadata. Do not rely on it for
  documentation. Use the Ministry page above instead.

## Gold: why the dimensions have no surrogate keys

Asked directly: this was priced, not forgotten.

A surrogate key is worth having when it is stable. A key generated inside a view
is not: `row_number()` renumbers as soon as a hospital is added upstream, and
anything that stored the old numbers — an export, a report, a cached model —
silently points at the wrong row. Making the keys stable means materialising the
dimensions, which spends the property that gold is a set of views over silver,
and adds tables that can drift from their own definitions.

What it would buy at this size: 6 health authorities, 65 hospitals, 85 procedure
groups, 69 quarters, and fact tables of 206,000 and 58,000 rows. An integer join
instead of a short-string join over that is not measurable in DuckDB.

So gold joins on the publisher's own values. The cost is honest: text keys are
wider, and a renamed hospital looks like a new one — which is a real
consideration for the facility dimension, and is why the current-data assertions
pin the hospital count.

**When this should be revisited:** the T-SQL port (step 8), where a conventional
star schema is expected, or the first time a query is measurably slow. Either
way the decision comes with the materialisation rules below.

## Materialising a gold view

Gold is views. Materialise one only when all three of these are true:

1. **There is a measurement.** The query, its timing before and after, and the
   date. Not an impression that something felt slow.
2. **There is a rebuild command**, written here. A materialised table whose
   origin nobody knows is worse than a slow view.
3. **There is a drift test.** An assertion that the table still equals the view
   definition it was built from. Materialising copies a definition into data,
   and a copy goes stale without saying so.

Exporting gold for Power BI is not this. That is a snapshot for a tool, not a
performance decision, and it carries its own rule: it must be reproducible and
must record the manifest sha256 of the files it came from, so a number on a
dashboard can be traced to a specific version of the published data.

## Tests

```bash
python -m pytest
```

Two kinds of assertion, kept in separate files because a failure means something
different in each:

- **`tests/test_silver_structure.py`** builds silver from the committed fixtures
  and asserts things that must hold whatever the data says. A failure means the
  pipeline is wrong. Runs anywhere, including CI.
- **`tests/test_current_data.py`** reads `data/warehouse.duckdb` and pins facts
  about the published files as they stand: 95 unexplained rows, 65 hospitals,
  the gap at 2025/26, and the rest. A failure means **the data changed, not the
  code**. Each assertion's docstring names the profiling query to rerun.

Without a warehouse the second kind skips, and the run says so in a block of its
own rather than a single `s`.

**After every ingest**, rebuild silver and run them:

```bash
python src/ingest.py
python src/run_sql.py sql/silver/01_silver_annual.sql data/warehouse.duckdb
python src/run_sql.py sql/silver/02_silver_quarterly.sql data/warehouse.duckdb
python src/run_sql.py sql/gold/01_dim_period.sql data/warehouse.duckdb
python src/run_sql.py sql/gold/02_dim_facility.sql data/warehouse.duckdb
python src/run_sql.py sql/gold/03_dim_health_authority.sql data/warehouse.duckdb
python src/run_sql.py sql/gold/04_dim_procedure_group.sql data/warehouse.duckdb
python src/run_sql.py sql/gold/10_fact_quarterly.sql data/warehouse.duckdb
python src/run_sql.py sql/gold/11_fact_annual.sql data/warehouse.duckdb
python -m pytest -m realdata
```

This list is also held in `tests/conftest.py` as `BUILD_SQL`, and pytest prints
it from there when the current-data assertions skip. That copy derives its
commands from the list of files; this one is typed, so check both when a build
step is added.

When one of those assertions fails legitimately, the order is: rerun the
profiling query, update `docs/data-dictionary.md`, then update the number in the
test. The number in the test is a copy of the documentation, never the other way
round.

## Ingest (`src/ingest.py`)

### Known risks

- **Filename collisions overwrite silently.** Local filenames are derived from
  the resource name (lowercased, every run of non-alphanumeric characters
  replaced by `-`). Two resources whose names differ only in punctuation or
  case, e.g. `2009_2026 Annual` and `2009-2026 annual`, map to the same file.
  The second download overwrites the first without an error, and the manifest
  ends up with two records pointing at one path. The three current resources
  do not collide, so this is not handled yet.

- **Raw files are overwritten on every run, and old versions are not kept.**
  Each run writes over the files in `data/raw/` and rewrites the manifest. The
  Ministry restates this data. Once a file is restated, the version that
  earlier results were computed from is gone. The sha256 in the manifest (kept
  in git history) can prove which version was read, but cannot bring that
  version back.

  **Why this matters for Step 5:** reconciliation conclusions must be
  reproducible and traceable to a specific query and a specific file. With
  overwriting, they are reproducible only until the next restatement. After
  that, the manifest can show "this is the version I read", but the version
  itself no longer exists. **Before Step 5, decide whether to archive raw files
  by sha256 or by fetch time instead of overwriting them.** Not handled yet.

## Reading xlsx files with DuckDB

### Pitfalls: each of these loses data without an error

- **`header = true` drops columns whose header cell is empty.** No warning. Seen
  on the quarterly file: columns J–L are missing from the result. They are empty
  in the profiled version, so nothing was lost there, but the next version
  might not be. To check such columns, read them with `header = false` and a
  column range, e.g. `range = 'J:L'`. An open range like that returns Excel's
  maximum row count (1,048,576), so use it for non-null counts only.

- **Without an explicit `range`, reading stops at the first blank row.**
  `stop_at_empty` then defaults to true, and every row below the blank row is
  dropped. Always set `stop_at_empty = false`.

  This comes from DuckDB's documentation and has still not been reproduced here.
  The annual file's 9,628 blank rows all sit after its data
  (`sql/profile/01_time_coverage.sql`, section 5), so a default read of it loses
  nothing. That is a fact about this file today, not about the reader.

### A green suite proves nothing on its own

Tests that pass and tests that check nothing look identical in CI: both are
green. After writing a set of assertions, break the logic each one covers,
confirm that assertion fails and that the others do not, then restore.

The structural assertions were checked that way. A lower bound of 0 instead of
1, a percentile falling back to `suppressed` instead of `unexplained`, and
totals matched with `LIKE 'All %'`: each broke exactly one assertion, which is
also how you find out the assertions are not covering for one another.

An assertion can pass because the rows it looks at are not there at all. Where
that is possible, assert first that the rows exist — the percentile
classification test does this, and says so in its failure message.

### It has already caught one: a false green in this repository

This is not a habit kept on principle. On 2026-09-16 it caught an assertion that
was broken the moment it was written, and green the whole time.

**The assertion.** `test_dim_facility_covers_every_facility_in_the_facts`, which
exists to enforce that the facility dimension is the union of all three
published files. It asserts that every (health authority, facility) pair in
either fact table has exactly one row in `dim_facility`.

**How it was found.** The mutation was to delete the annual file from the union
in `sql/gold/02_dim_facility.sql`, and to expect the assertion to fail. It
passed. Every facility in the annual fixture also appeared in the quarterly
fixture, so a dimension built from the quarterly files alone still covered
everything the assertion looked at.

**Why that mattered.** The assertion would have stayed green until a facility
appeared that only the annual file names — which is the real situation: six
facilities stopped reporting years ago and are in the historical files only. The
test guarding the union would have failed to notice the union being dropped,
and every row belonging to those six would have fallen out of the model in
silence.

**The fix.** The fixture now carries a facility that only the annual file names,
matching the shape of the real data. The same mutation then failed the
assertion, and only that one.

### A mutation that changes nothing proves nothing either

The first attempt at breaking the leaf fact view loosened one of its three
filter conditions, and the suite stayed green. The assertion was fine: the
mutation was a no-op. Province rows carry `All Facilities` as their facility, so
the two remaining conditions still excluded every row the loosened one would
have let through.

A mutation that leaves the output identical says nothing about the assertion. So
check what the mutation did before drawing a conclusion from a green run —
a row count either side is enough. Removing the filter outright failed two
assertions, which is what the check was after.

Three practical notes. Commit before breaking anything: `git checkout --` cannot
restore a file git has never seen, and a mutation left behind in an untracked
file is worse than no check at all. This was learned the same afternoon, on
these same two files. And break one thing at a time, so that the assertions can
be seen not to be covering for each other.

### A rule that cries wolf is not a rule

The gap diagnostic in `sql/silver/02_silver_quarterly.sql` first reported seven
missing quarters: the four that really are missing, and the three remaining
quarters of the fiscal year in progress. Those three are not missing. They have
not happened yet.

Left as it was, that query would have produced three false alarms every year,
for ever. Whoever read it would have learned to skim past the output, including
in the year a real gap appeared. Filtering to quarters before the last published
one cut the output to the four that matter.

Every quality rule written from here on gets the same question before it is
committed: **does it fire when nothing is wrong?** A rule that does is not a
rule. It is noise that trains people to ignore it.

### A note on reading results

When those blank rows were first checked, the outcome table written beforehand
listed three possible row counts and missed a fourth: "the default skips blank
rows wherever they are" produces exactly the same count as "the blank rows are
at the end". The observation, 58,454 rows read, fitted both. A second query,
over the sheet rows that hold data, was needed to tell them apart.

Writing an exhaustive table of possible outcomes before running a query is
harder than explaining the result afterwards. This one was not exhaustive, and
the first reading of it would have been wrong.

- **`all_varchar = true` shows decimals with floating-point noise.** `73.4`
  reads as `73.400000000000006`. The literal text is not what Excel displays.
  Never compare numeric cells as strings.
