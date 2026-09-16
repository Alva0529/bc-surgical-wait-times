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
