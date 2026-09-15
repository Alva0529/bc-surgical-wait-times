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
  dropped. This is taken from DuckDB's documentation and has not been reproduced
  on these files yet. The annual file has 9,628 fully blank rows whose position
  has not been checked. Always set `stop_at_empty = false`.

- **`all_varchar = true` shows decimals with floating-point noise.** `73.4`
  reads as `73.400000000000006`. The literal text is not what Excel displays.
  Never compare numeric cells as strings.
