# Data dictionary

> **Step 2: in progress.** Layout, time coverage, measure additivity and
> hierarchy totals are documented. Suppression encoding has not been profiled
> yet.

For each file, record:

- **Grain** — one row represents what, exactly?
- **Dimension columns** — name, example values, how nulls/totals are encoded
- **Measure columns** — name, unit, and whether it is additive
- **Suppression encoding** — what literally appears in the cell when a value is
  withheld? A blank? A symbol? A sentinel number? This determines the silver layer.
- **Hierarchy totals** — how are "all facilities" / "all procedures" rows marked?
  Do they sit in the same table as the detail rows?

## Profiled version

Every finding below comes from these exact files. The Ministry restates this
data, so a later download may differ.

| File | `resource_id` | sha256 | Fetched (UTC) |
|---|---|---|---|
| 2009_2026 Quarterly | `f294562c…` | `077444690d6e…` | 2026-09-15 03:03 |
| 2009_2026 Annual | `6cd508eb…` | `2d9f99cbe4dd…` | 2026-09-15 03:03 |
| 2026_2027 Quarterly – Q1 Interim | `0c430fa8…` | `5d801d6aabe8…` | 2026-09-15 03:03 |

Queries: `sql/profile/01_time_coverage.sql`, run with
`python src/run_sql.py sql/profile/01_time_coverage.sql`.

## Layout (all three files)

- One worksheet, `Sheet1`. Header in row 1, with no title or note rows above it.
- Long format. The apparent grain is one row per period × health authority ×
  hospital × procedure group. That is read from the header and the first rows;
  whether the combination is actually unique has not been tested.

## Files

### 2009_2026 Quarterly Surgical Wait Times

- **Actual time coverage:** 2009/10 Q1 to **2024/25 Q4**. 64 consecutive
  quarters, none missing.
- **Metadata claims:** coverage to 2026-03-31 (the name `2009_2026` and the
  `temporal_extent`). The file is one full fiscal year short. See Open questions.
- **Rows:** 202,953 data rows (sheet dimension 202,954 including the header),
  3,069–3,262 per quarter. No blank rows.
- **Columns:** `FISCAL_YEAR`, `QUARTER`, `HEALTH_AUTHORITY`, `HOSPITAL_NAME`,
  `PROCEDURE_GROUP`, `WAITING`, `COMPLETED`, `PERCENTILE_COMP_50TH`,
  `PERCENTILE_COMP_90TH`.
- **Columns J–L:** the sheet dimension includes three more columns with empty
  header cells. All three are empty in every row. DuckDB's `read_xlsx` drops
  them silently when reading with a header; see the runbook.

### 2009_2026 Annual Surgical Wait Times

- **Actual time coverage:** 2009/10 to 2025/26. 17 fiscal years, none missing.
  Matches the metadata.
- **Rows:** 68,082 rows read (sheet dimension 68,083 including the header). Of
  these, **9,628 are fully blank**: every column is empty. That leaves 58,454
  data rows, 3,357–3,485 per fiscal year. Where the blank rows sit in the sheet
  (between data rows or after them) has not been checked yet.
- **Columns:** the same as the quarterly file, without `QUARTER`.

### 2026_2027 Quarterly Surgical Wait Times — Q1 Interim

- **Actual time coverage:** 2026/27 Q1 only. Matches the metadata
  (2026-04-01 to 2026-06-30).
- **Rows:** 3,203 data rows. No blank rows.
- **Columns:** the same nine columns as the quarterly file, with no extra
  columns.
- This resource is replaced every quarter (see Open questions), so the period it
  covers will change.

## Dimension columns

| Column | Example values | Notes |
|---|---|---|
| `FISCAL_YEAR` | `2009/10` | Text. BC fiscal year, April 1 to March 31. |
| `QUARTER` | `Q1` | Text. Quarterly and interim files only. Q1 is April–June (the interim file's Q1 extent is 2026-04-01 to 2026-06-30). |
| `HEALTH_AUTHORITY` | `All Health Authorities` | Includes a total value. See Hierarchy totals. |
| `HOSPITAL_NAME` | `All Facilities` | Includes a total value. |
| `PROCEDURE_GROUP` | `Cataract Surgery`, `All Procedures`, `All Other Procedures` | Includes a total value, and one value that looks like a total but is not. |

Values other than totals for `HEALTH_AUTHORITY` and `HOSPITAL_NAME` have not been
profiled yet. The first rows of every file are province-level totals.

## Measure columns

| Column | Type seen in total rows | Additive across periods? |
|---|---|---|
| `WAITING` | whole number | **No.** Behaves as a point-in-time count (a stock). |
| `COMPLETED` | whole number | Yes, quarters add up to the fiscal year (a flow). |
| `PERCENTILE_COMP_50TH` | decimal | No. Percentiles cannot be recomputed from aggregates (publisher). |
| `PERCENTILE_COMP_90TH` | decimal | No, as above. |

- Types are as seen in province-level total rows. Suppressed cells may hold
  something else. See Suppression encoding.
- The unit of the percentile columns has not been confirmed.
- The percentile cells are stored as binary floating point. Read as text, `73.4`
  comes out as `73.400000000000006`. Never compare them as strings.

### Additivity evidence

This compares the fiscal-year value from the annual file with the sum of four
quarters from the quarterly file. It uses only province-level total rows
(`All Health Authorities` / `All Facilities` / `All Procedures`), where counts
are far above any suppression threshold, so withheld cells cannot explain a
difference.

- **`COMPLETED`:** equal in every year from 2009/10 to 2019/20 (difference 0).
  From 2020/21 the annual figure is slightly larger, by 3, 9, 69, 119 and 584
  cases (at most 0.2%), and the gap grows towards recent years. See Open
  questions: the two files are different vintages.
- **`WAITING`:** the sum of four quarters is **3.83 to 4.25 times** the annual
  figure, in all 16 complete fiscal years. Adding `WAITING` across quarters does
  not produce a meaningful quantity.
- 2025/26 cannot be compared, because the quarterly file has no data for it.
- What point in time the annual `WAITING` figure represents is not known yet.
  See Open questions.

## Hierarchy totals

- Totals sit in the same table as detail rows. They are marked by exact values:
  `All Health Authorities` in `HEALTH_AUTHORITY`, `All Facilities` in
  `HOSPITAL_NAME`, `All Procedures` in `PROCEDURE_GROUP`.
- **Trap: `All Other Procedures` is not a total.** It is a residual procedure
  group. Province-wide in 2009/10 Q1 it has 1,552 cases waiting, against 69,587
  for `All Procedures`. A filter like `LIKE 'All %'` would classify it as a total
  and drop a real category, with no error. This is based on the name and the
  magnitude, and has not been checked against the full list of `PROCEDURE_GROUP`
  values yet.
- **Requirement for silver (Step 3):** total rows are identified by an explicit
  list of exact values, never by pattern matching. A pytest asserts that
  `All Other Procedures` rows are kept as detail rows and not classified as
  totals.
- Which combinations of totals exist (for example, one health authority with
  `All Facilities`) has not been profiled yet.

## Suppression encoding

**Not profiled yet.** No suppressed cell appears in the first 15 rows of any
file, but that says nothing: those rows are all province-level totals, where
counts are far above any threshold. A dedicated scan comes next. It will also
check where the annual file's blank rows sit.

## Open questions

### 1. When the Ministry publishes new data, does it update the existing resource or create a new one?

**Status: supported by catalogue metadata (checked 2026-09-14), not proven.**

Downstream layers locate files by `resource_id` from `data/raw/_manifest.json`
(see the project constraints in `CLAUDE.md`). That only works if a resource
keeps its `resource_id` from one release to the next, which is true only if
the Ministry replaces the file inside an existing resource and does not create
a new resource.

**Original hypothesis:** the quarterly and annual files are rolling, cumulative
files, so each release overwrites the same resource. The Q1 Interim file is
temporary, which would explain why it was published as a separate resource.

**Evidence.** Catalogue API `package_show`, queried 2026-09-14:

| Resource | `resource_id` | `created` | `last_modified` | `resource_update_cycle` | `temporal_extent` |
|---|---|---|---|---|---|
| 2009_2026 Quarterly | `f294562c…` | 2015-11-24 | 2025-11-05 | annually | 2009-04-01 to 2026-03-31 |
| 2009_2026 Annual | `6cd508eb…` | 2015-11-24 | 2026-08-12 | annually | 2009-04-01 to 2026-03-31 |
| 2026_2027 Quarterly – Q1 Interim | `0c430fa8…` | 2016-08-23 | 2026-08-12 | quarterly | 2026-04-01 to 2026-06-30 |

**What it shows:**

- **Quarterly and annual: hypothesis supported.** Both resources were created in
  2015, but their names and temporal extents now run to 2026. The same resources
  have been carried through about ten years of releases. The publisher's stated
  update cycle for both is annual.
- **Interim: hypothesis refuted.** The resource was created in 2016, and its
  update cycle is quarterly. It is not a one-off file for 2026/27 Q1. It is a
  long-lived resource whose file is replaced every quarter with the latest
  interim release.
- **What this means for locating by `resource_id`:** it should work for all three
  resources. Note that `0c430fa8…` stands for "the current interim release", not
  for "2026/27 Q1". The period it covers changes every quarter, so silver must
  read the period from the data, not infer it from the resource.

**Limits of this evidence:**

- `created` and `last_modified` hold only the latest values, not a history. They
  show that these resources are old. They do not prove that every past release
  went into the same resource.
- **The quarterly file's metadata does not match its contents.** Its
  `last_modified` is 2025-11-05, but its name and `temporal_extent` claim
  coverage through 2026-03-31. Profiling shows the file actually ends at
  2024/25 Q4. The save time inside the file (`docProps/core.xml`: 2025-11-04)
  agrees with `last_modified`. So `last_modified` looks reliable, and the file
  simply covers less than the metadata says. The internal save time is only weak
  evidence, because it is written by whatever tool exported the file.

  **Why the metadata says 2026 is not known.** Two explanations, neither
  verified, and both could be true at once:
  - The metadata describes the intended coverage of this rolling resource, and
    the file describes what it actually contains. Metadata and files drifting
    apart is common in public data.
  - The resource metadata was edited on 2026-08-12, when the annual and interim
    files were uploaded (all three resources show `metadata_modified`
    2026-08-12), but no new quarterly file was uploaded.

**Still to confirm:** after the next release, compare `resource_id`s in the
manifest against the committed version in git history.

**If the Ministry creates new resources after all, silver needs a different way
to find files.** `resource_id` alone would break on every release. Options to
decide between at that point:

- A small committed mapping from a stable logical name (e.g. `quarterly`,
  `annual`) to the current `resource_id`, updated by hand each release. Silver
  fails loudly if a mapped id is missing from the manifest.
- Matching on the resource name (e.g. contains "Annual Surgical Wait Times")
  and picking the one with the latest year range. No manual step, but it
  depends on naming conventions the Ministry has not committed to.

Either way, the `resource_id` constraint in `CLAUDE.md` would need to be
revised.

### 2. Quarterly coverage: a gap today, possibly an overlap later

**Status: the gap is confirmed in the profiled files. How to handle a gap and
how to handle an overlap are both still open.**

#### The gap

The quarterly cumulative file ends at 2024/25 Q4. The interim file covers
2026/27 Q1. **No file contains quarterly data for 2025/26.** Unknown: whether
the Ministry will publish it later, and whether earlier interim releases held
some of those quarters before they were replaced.

**Failure mode:**

- A quarterly trend line runs straight from 2024/25 Q4 to 2026/27 Q1. Nothing on
  the chart says a year is missing.
- `LAG()` over quarters ordered by period treats 2024/25 Q4 as the quarter
  before 2026/27 Q1. A "quarter-on-quarter change" is then actually a change
  across five quarters.
- **Nothing raises an error** in either case.

**Proposed handling (to decide in Steps 3–4):**

- The fiscal period dimension lists every quarter from the first to the last,
  whether it was published or not. A missing quarter is an explicit row marked as
  not published, not an absent row.
- Period-over-period measures are calculated against that complete list of
  periods, not against whichever rows happen to exist.
- A data quality rule fails when the set of missing quarters differs from the
  documented one. A known gap is documented once; a new gap fails loudly.

#### A possible overlap later

**Which files:** the quarterly cumulative file (`f294562c…`) and the interim
file (`0c430fa8…`). Both have the same nine columns, and both appear to be at
quarterly grain. The annual file is at annual grain. It should never be unioned
with quarterly rows at all, so that is a separate issue.

**When it would happen:** the interim resource holds the latest quarter(s) of
the current fiscal year. If the cumulative file is extended to cover a quarter
the interim file still holds, that quarter appears in both files. Today they
don't overlap: there is a gap between them instead. Also unknown: in what order
the two resources are updated, and whether a later interim release (e.g. Q2)
also contains the earlier quarters of the year.

**Failure mode.** Suppose silver builds the quarterly table as a `UNION ALL` of
the two files:

- Every row for the overlapping quarter appears twice: once from the cumulative
  file and once from the interim file.
- **Nothing raises an error.** A union does not check for duplicate keys, so the
  query succeeds.
- Switching to `UNION` (which removes duplicate rows) does not fix it. Interim
  figures can be revised before the cumulative release, so the two copies are
  not identical rows and both survive.
- The result: case counts for that quarter are roughly doubled, and every
  grouping has two P50/P90 values for that quarter. Only that one quarter is
  wrong. On a trend chart it looks like a real surge in surgical volume, not a
  bug.

This is exactly the kind of silent error this project exists to expose. The
handling must be explicit and must not rely on default behaviour.

**Proposed handling (to decide in the silver step):**

- **An explicit precedence rule, written in the silver SQL.** For any quarter
  present in the cumulative file, keep the cumulative rows and drop the interim
  rows. Use interim rows only for quarters the cumulative file does not yet
  cover. Record on each row which resource it came from, so downstream can see
  whether a quarter's figures are interim.
- **A data quality rule that fails the build** if any combination of quarter and
  grouping keys appears more than once in silver. The exact key columns will be
  confirmed once the grain has been tested. This turns a silent over-count into
  a failing test.

### 3. The quarterly and annual files are different vintages

**Status: the difference is observed. The explanation is unverified.**

**Observed:** province-level `COMPLETED` in the annual file matches the sum of
quarters exactly up to 2019/20. From 2020/21 the annual figure is larger by 3,
9, 69, 119 and 584 cases, growing towards recent years. The two files were saved
about nine months apart: the quarterly file on 2025-11-04, the annual file on
2026-08-10 (`docProps/core.xml`).

**Hypothesis:** records arrive late or get restated between releases. The newer
annual file includes cases recorded after the quarterly file was produced, and
recent years are affected most.

**Why it matters for Step 5:** the two files cannot be expected to reconcile
exactly for recent years, even for an additive measure. Any difference between
them has to be checked against the vintage gap before it is attributed to
anything else.

**How to check:** when the quarterly file is next replaced, compare its
2020/21–2024/25 `COMPLETED` totals with this version's. That needs this version
to still exist. Raw files are currently overwritten on every ingest; see the
runbook.

### 4. What point in time does the annual `WAITING` figure represent?

**Status: open.**

**Known:** the sum of four quarters is about four times the annual figure, so
the annual figure is on the scale of a single quarter's `WAITING`.

**Unknown:** which point in time it is. It could be the fiscal year end (the Q4
figure), an average, or some other snapshot date. The snapshot date behind the
quarterly figures is not known either.

**Why it matters:** the gold model has to choose which snapshot represents a
year when it rolls quarters up. `WAITING` cannot be summed across time.

**How to check:** compare the annual `WAITING` with each quarter's `WAITING` for
the same year at province level, and look for the publisher's definition.
