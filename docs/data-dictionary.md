# Data dictionary

> **Step 2: in progress.** Layout, grain, time coverage, measure definitions and
> additivity, hierarchy totals, the dimension inventory, suppression encoding and
> the requirements for silver are recorded. Open questions remain.

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

## Official sources

There are two sources, and they cover different things. Both were read
2026-09-15, and the passages used in this document are quoted word for word.

### Ministry of Health page: data lineage

Source:
[Surgical wait times](https://www2.gov.bc.ca/gov/content/health/accessing-health-care/surgical-wait-times),
BC Ministry of Health.

> Surgical wait times data is collected in the Surgical Patient Registry and
> comes directly from the hospitals across the province.

> The accuracy of the registry is entirely dependent on the data submitted by
> the facilities.

> The Ministry, in conjunction with the health authorities makes every effort to
> ensure the data contained on this site is accurate and timely, however it
> cannot guarantee the completeness of the information as it is gathered from a
> variety of health authority sources.

Two limits on what these passages say:

- The completeness statement refers to "the data contained on this site", which
  is the Ministry's own wait times website, not the catalogue files by name.
- The catalogue description does not name a source system. That the catalogue
  files also come from the Surgical Patient Registry is inferred: the same
  Ministry publishes both, on the same subject.

### Catalogue description: data rules

Source: the dataset description in the BC Data Catalogue (the `notes` field
returned by `package_show`). The dataset's "more info" link,
`https://swt.hlth.gov.bc.ca/`, returned HTTP 404 on 2026-09-15.

> B.C. surgical wait times for elective surgical procedures in British Columbia
> for patients of all ages. This data includes scheduled inpatient and day
> surgery cases. This data does not include unscheduled surgical cases.

> Three files are provided:
> 1. An interim quarterly file with current fiscal year quarters only;
> 2. A quarterly file with historical data; and
> 3. An annual file with historical data.

> The quarterly and annual files with historical data are updated in September
> to include data for the previous fiscal year. The complete dataset is subject
> to restating, when necessary, to reflect current reporting requirements as
> determined by the Ministry of Health in conjunction with the health
> authorities.

> The number of cases waiting is captured at a point in time, i.e., either at
> the end of the quarter or fiscal year.

> The number of cases completed captures scheduled surgeries that are completed
> within each quarter as well as within each fiscal year.

> Wait time percentiles (50th and 90th) are calculated in weeks based on
> scheduled surgeries that are completed within each quarter as well as within
> each fiscal year. They are Wait for Surgery (Wait Two) wait times, from the
> date the health authority receives the booking form to the date that the
> patient receives surgery.

> Since percentiles cannot be calculated on data that is already aggregated,
> they are provided at all levels within each file.

> All values less than 5 and their corresponding wait times are suppressed.
> Therefore, rows with total volumes may not match the sum of sub rows. For
> example, the All Facilities row may not match the sum of the individual
> facilities if there is one with a suppressed value less than 5.

> Each fiscal year begins on April 1st and ends on March 31st of the following
> calendar year. [...] Q1: April 1st - June 30th; Q2: July 1st - September 30th;
> Q3: October 1st - December 31st; Q4: January 1st - March 31st

## Layout (all three files)

- **Scope:** elective, scheduled inpatient and day surgery cases, all ages.
  Unscheduled surgical cases are not included (official description).
- One worksheet, `Sheet1`. Header in row 1, with no title or note rows above it.
- Long format.

### Grain (verified)

One row per period × health authority × hospital × procedure group. The key
differs between files, because the annual file has no `QUARTER` column:

| File | Key |
|---|---|
| Quarterly, interim | `FISCAL_YEAR`, `QUARTER`, `HEALTH_AUTHORITY`, `HOSPITAL_NAME`, `PROCEDURE_GROUP` |
| Annual | `FISCAL_YEAR`, `HEALTH_AUTHORITY`, `HOSPITAL_NAME`, `PROCEDURE_GROUP` |

Tested on the profiled versions (`sql/profile/03_grain.sql`, section 1): in all
three files the number of key combinations equals the number of data rows, and
no key occurs twice.

The test means what it says only because the dimension values are clean
(section 4 of the same file): no dimension column contains a NULL, and no value
differs from another only by case or by surrounding spaces. Had
`Burnaby Hospital` and `Burnaby Hospital ` both existed, a uniqueness test would
have passed while the data held two hospitals of the same name.

**Requirement for silver (Step 3), MUST:** a pytest asserts grain uniqueness,
one assertion per silver table, on the key above. The assertion belongs on the
silver table rather than the raw file, because it also covers whatever silver
does when the quarterly and interim files are combined (see Open question 2).

## Files

### 2009_2026 Quarterly Surgical Wait Times

- **Actual time coverage:** 2009/10 Q1 to **2024/25 Q4**. 64 consecutive
  quarters, none missing.
- **Metadata claims:** coverage to 2026-03-31 (the name `2009_2026` and the
  `temporal_extent`). The file is one full fiscal year short: it has not received
  this year's scheduled update yet. See Open questions 1 and 2.
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
  data rows, 3,357–3,485 per fiscal year. All the blank rows come after the
  data: sheet rows 2 to 58,455 hold data and not one of them is blank
  (`sql/profile/01_time_coverage.sql`, section 5). So a default `read_xlsx`
  read, which stops at the first blank row, loses nothing on this file.
- **Columns:** the same as the quarterly file, without `QUARTER`.

### 2026_2027 Quarterly Surgical Wait Times — Q1 Interim

- **Actual time coverage:** 2026/27 Q1 only. Matches the metadata
  (2026-04-01 to 2026-06-30).
- **Rows:** 3,203 data rows. No blank rows.
- **Columns:** the same nine columns as the quarterly file, with no extra
  columns.
- Officially "current fiscal year quarters only". The resource is replaced every
  quarter (see Open questions), so the period it covers will change.

## Dimension columns

| Column | Example values | Notes |
|---|---|---|
| `FISCAL_YEAR` | `2009/10` | Text. April 1 to March 31 of the next calendar year (official description). |
| `QUARTER` | `Q1` | Text. Quarterly and interim files only. Q1 April–June, Q2 July–September, Q3 October–December, Q4 January–March (official description). |
| `HEALTH_AUTHORITY` | `All Health Authorities` | Includes a total value. See Hierarchy totals. |
| `HOSPITAL_NAME` | `All Facilities` | Includes a total value. |
| `PROCEDURE_GROUP` | `Cataract Surgery`, `All Procedures`, `All Other Procedures` | Includes a total value, and one value that looks like a total but is not. |

### Dimension inventory

Counts and boundaries are recorded here; the lists themselves come back from
`sql/profile/03_grain.sql`, sections 3a and 4c.

- **`PROCEDURE_GROUP`: 85 distinct values.** `All Procedures` (the total) and 84
  categories, one of which is `All Other Procedures`. All 85 appear in all three
  files. The smallest is `Hernia Repair - Chest Wall`, with 24 rows in the
  quarterly file, 17 in the annual and 3 in the interim.
- **`HEALTH_AUTHORITY`: 6 health authorities** — Fraser, Interior, Northern,
  Provincial Health Services Authority, Vancouver Coastal, Vancouver Island —
  plus the total value `All Health Authorities`.
- **`HOSPITAL_NAME`: 65 hospitals** in the quarterly and annual files, **59** in
  the interim file, plus the total value `All Facilities`.

**Requirement for silver (Step 3), MUST: the hospital dimension is the union of
all three files.** The interim file is short 6 hospitals because it covers a
single quarter, and those hospitals have no rows in it. That is not missing
data. A hospital dimension built from one file alone would not carry the
hospitals the other files need, and historical rows would fail to join.

No dimension column contains a NULL in any file.

## Measure columns

| Column | Definition (official description) | Type seen in total rows | Additive across periods? |
|---|---|---|---|
| `WAITING` | Cases waiting, captured at a point in time: the end of the quarter or of the fiscal year | whole number | **No.** A stock. |
| `COMPLETED` | Scheduled surgeries completed within the quarter or fiscal year | whole number | Yes. A flow. |
| `PERCENTILE_COMP_50TH` | 50th percentile wait, **in weeks**, over surgeries completed in the period | decimal | No. |
| `PERCENTILE_COMP_90TH` | 90th percentile wait, **in weeks**, over surgeries completed in the period | decimal | No. |

- **Which wait the percentiles measure:** "Wait Two", from the date the health
  authority receives the booking form to the date of surgery (official
  description). They are based on completed surgeries, not on cases still
  waiting.
- Types are as seen in province-level total rows. Suppressed cells may hold
  something else. See Suppression encoding.
- The percentile cells are stored as binary floating point. Read as text, `73.4`
  comes out as `73.400000000000006`. Never compare them as strings.

### Additivity evidence

The official description defines `WAITING` as a point-in-time count and
`COMPLETED` as completions within the period. The data agrees.

This compares the fiscal-year value from the annual file with the sum of four
quarters from the quarterly file. It uses only province-level total rows
(`All Health Authorities` / `All Facilities` / `All Procedures`), where counts
are far above the suppression threshold, so withheld cells cannot explain a
difference.

- **`COMPLETED`:** equal in every year from 2009/10 to 2019/20 (difference 0).
  From 2020/21 the annual figure is slightly larger, by 3, 9, 69, 119 and 584
  cases (at most 0.2%), and the gap grows towards recent years. See Open
  question 3: the two files are different vintages.
- **`WAITING`:** the sum of four quarters is **3.83 to 4.25 times** the annual
  figure, in all 16 complete fiscal years. Adding `WAITING` across quarters does
  not produce a meaningful quantity.
- 2025/26 cannot be compared, because the quarterly file has no data for it.
- Which quarter's `WAITING` the annual figure corresponds to is documented but
  not yet checked against the data. See Open question 4.

## Hierarchy totals

- Totals sit in the same table as detail rows. They are marked by exact values:
  `All Health Authorities` in `HEALTH_AUTHORITY`, `All Facilities` in
  `HOSPITAL_NAME`, `All Procedures` in `PROCEDURE_GROUP`.
- Total rows carry their own percentiles. Percentiles "are provided at all
  levels within each file" (official description), because they cannot be
  derived from the detail rows.
- **Trap: `All Other Procedures` is not a total. Proved by arithmetic**
  (`sql/profile/03_grain.sql`, sections 3b and 3c). Province-wide rows,
  `COMPLETED`:

  | | Annual file, 2009/10–2025/26 | Quarterly file, 64 quarters |
  |---|---|---|
  | Published `All Procedures` total | 4,169,291 | 3,879,192 |
  | Gap when the 84 categories are summed | 6 | 22 |
  | Gap once `All Other Procedures` is dropped | 110,827 | 101,235 |
  | Province-wide suppressed groups | 1 per gap, 6 in total | 11 |

  Summed correctly, the detail reconciles to the published total apart from the
  suppressed groups, and every gap falls inside the 1 to 4 band that `<5` stands
  for: 6 cases from 6 suppressed groups in the annual file, 22 from 11 in the
  quarterly file. Dropping `All Other Procedures` as though it were a total
  removes 110,827 completed surgeries, and raises no error.
- **Requirement for silver (Step 3):** total rows are identified by an explicit
  list of exact values, never by pattern matching. A pytest asserts that
  `All Other Procedures` rows are kept as detail rows and not classified as
  totals.
- **Combinations of totals that exist** (`sql/profile/02_suppression.sql`,
  section 5): every file has the same six. Province (`All Health Authorities` +
  `All Facilities`), health authority (a health authority + `All Facilities`),
  and hospital (a health authority + a hospital), each with either
  `All Procedures` or a single procedure group. No row pairs
  `All Health Authorities` with a specific hospital.

## Suppression encoding

**Profiled** in `sql/profile/02_suppression.sql`, over every data row of all
three files.

- **Rule (official):** "All values less than 5 and their corresponding wait
  times are suppressed."
- **Counts (`WAITING`, `COMPLETED`): a suppressed count is the literal text
  `<5`.** It is the only non-numeric value in these columns, in every file and
  every fiscal year. No count cell is blank.
- **Zeros are published.** A literal `0` appears in every file. In the quarterly
  file alone there are 15,771 in `COMPLETED` and 19,783 in `WAITING`. No
  published count lies between 1 and 4. So `<5` stands for a count of **1 to 4**.
  This assumes the rule is applied consistently, and nothing in the files
  suggests otherwise.
- **Percentiles: a withheld percentile is a blank cell.** No text appears in the
  percentile columns. `PERCENTILE_COMP_50TH` and `PERCENTILE_COMP_90TH` are
  always blank together. So counts and percentiles use different encodings: `<5`
  for counts, a blank for percentiles.
- **A blank percentile does not always mean suppressed.** See the requirement
  below.
- **No sentinel numbers.** No negative values, and no fractional counts.
- **Percentiles of `0` weeks exist.** In the quarterly file there are 172 in P50
  and 87 in P90, in rows where `COMPLETED` is 5 or more. That is not
  suppression. Whether a zero-week wait is real or a recording artefact is a data
  quality question for Step 3.
- **Where suppression occurs:**
  - `All Procedures` rows at province and health authority level are never
    suppressed.
  - Province-wide rows for single procedure groups can be (quarterly: 11
    `COMPLETED`, 47 `WAITING`).
  - Most suppression is at hospital × procedure group level. In the quarterly
    file, 54,424 of those 163,806 rows have `COMPLETED` = `<5`.
  - Overall, 57,948 of the quarterly file's 202,953 `COMPLETED` cells (29%) are
    `<5`.
- **Why the range matters for Step 5:** every suppressed count is between 1 and
  4, so the gap between a total row and the sum of its detail rows is bounded:
  at least 1 and at most 4 per suppressed detail cell. Checked province-wide at
  both grains, where every observed gap fell inside that band. See Hierarchy
  totals.

## Requirement for silver: suppressed and not applicable are different states

**MUST.** This is the most important input from Step 2 to Step 3.

A withheld measure cell can mean two different things. Silver must keep them
apart:

| State | Meaning | True value | Effect on totals |
|---|---|---|---|
| **Reported** | A published number, including a published `0` | The number | None |
| **Suppressed** | Withheld under the small-numbers rule | Exists. A count is 1 to 4; a percentile exists but is unknown | The published total includes it. Detail rows sum short of the total, by an amount within a known range |
| **Not applicable** | There is nothing to report: a percentile wait time when no surgeries were completed | Does not exist | None. Nothing is missing from the total |

**Why this is required.** Suppose silver merges suppressed and not applicable
into one state. Step 5 then counts "no surgeries" as "data hidden", and the
reconciliation conclusions are wrong.

**How the states appear in the profiled files** (`sql/profile/02_suppression.sql`,
section 1):

- **Counts** are either reported (a whole number, `0` included) or suppressed
  (`<5`). A count has no not-applicable state.
- **Percentiles** are either reported (a number, `0` included) or blank. For a
  blank one, the state is decided by `COMPLETED` in the same row:

  | `COMPLETED` in the same row | Blank percentile is | Rows: quarterly / annual / interim |
  |---|---|---|
  | `<5` | **Suppressed** | 57,948 / 10,246 / 862 |
  | `0` | **Not applicable** | 15,771 / 1,250 / 212 |
  | 5 or more | **Neither: unexplained** | 54 / 39 / 2 |

  These three rows account for every blank percentile in every file.
- **The state is decided by `COMPLETED`, not by `WAITING`.** When `WAITING` is
  `<5` and `COMPLETED` is 5 or more, the percentiles are normally published
  (quarterly: 14,692 rows).

**Unexplained blanks.** 95 rows in total have blank percentiles even though
`COMPLETED` is 5 or more. Neither documented rule explains them. Silver must not
quietly classify them as suppressed or as not applicable: it either carries a
fourth state for them or fails loudly when it meets one. See Open question 5.

**Tests (Step 3).**

- The CI fixture includes at least one row in each state, plus one unexplained
  row. Candidates are in section 6 of `sql/profile/02_suppression.sql`.
- pytest asserts that a blank percentile next to `COMPLETED` `0` is classified
  as not applicable, and a blank percentile next to `COMPLETED` `<5` is
  classified as suppressed.
- pytest asserts that a blank percentile next to `COMPLETED` of 5 or more is not
  classified as either of those.

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
  update cycle for both is annual. The official description says these files
  "are updated", which fits, but it does not mention resources or ids.
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
  agrees with `last_modified`, so `last_modified` looks reliable. The internal
  save time is only weak evidence, because it is written by whatever tool
  exported the file.

  **Why the file ends at 2024/25 Q4: explained by the official update
  schedule.** The historical files "are updated in September to include data for
  the previous fiscal year". The annual file has already received 2025/26
  (uploaded 2026-08-12). The quarterly file has not been updated in this cycle
  yet; its last upload, 2025-11-05, presumably added 2024/25. See Open
  question 2.

  **Why the metadata already says 2026: still not explained.** The update
  schedule explains the file's contents. It does not make the metadata describe
  them: the resource's name and `temporal_extent` claim a year the file does not
  contain. Two explanations remain, neither verified, and both could be true at
  once:
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

**Status: the gap is confirmed in the profiled files and explained by the
official update schedule. It is a window between two scheduled updates, not a
permanent loss. It still needs confirming once the quarterly file is updated.
How to handle a gap and how to handle an overlap are both still open.**

#### The gap

The quarterly cumulative file ends at 2024/25 Q4. The interim file covers
2026/27 Q1. **No file contains quarterly data for 2025/26.**

**Why it exists:**

- Officially, the interim file holds "current fiscal year quarters only", and the
  historical files "are updated in September to include data for the previous
  fiscal year".
- In this cycle, the interim file moved on to 2026/27 Q1 and the annual file
  received 2025/26, both on 2026-08-12. The historical quarterly file has not
  been updated yet. So the 2025/26 quarters have left the interim file but have
  not yet arrived in the historical quarterly file. The files profiled here were
  fetched inside that window.
- "September" is approximate in practice. The annual file was updated on
  2026-08-12, in August. The quarterly file's last update was on 2025-11-05, in
  November.

**Inference, not verified: the window may recur every year.** It comes from the
two updates not being synchronised. If the interim file moves to a new fiscal
year before the historical quarterly file is updated, there is a gap, as now. If
the historical file is updated first, while the interim file still holds the
previous year's quarters, there is an overlap (see below). A gap and an overlap
are two outcomes of the same timing.

**How to confirm:** once the quarterly file has been updated, re-run the ingest
and `sql/profile/01_time_coverage.sql`, and check that the quarterly file ends
at 2025/26 Q4. A changed sha256 alone is not enough, because restating also
changes it. Last year's quarterly update came on 2025-11-05, so this may take
until November.

**Failure mode:**

- A quarterly trend line runs straight from 2024/25 Q4 to 2026/27 Q1. Nothing on
  the chart says a year is missing.
- `LAG()` over quarters ordered by period treats 2024/25 Q4 as the quarter
  before 2026/27 Q1. A "quarter-on-quarter change" is then actually a change
  across five quarters.
- **Nothing raises an error** in either case.
- The fact that it is only a window does not help: a pipeline run has no way of
  knowing it is running inside one.

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

**When it would happen:** if the historical quarterly file is updated while the
interim file still holds quarters of the previous fiscal year, those quarters
appear in both files. Today there is a gap instead. The interim file holds
"current fiscal year quarters only", which suggests a later interim release
(e.g. Q2) also contains the earlier quarters of the year. That can be confirmed
when the next interim release is published.

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

**Status: restating is officially documented. What caused these particular
differences is not verified.**

**Observed:** province-level `COMPLETED` in the annual file matches the sum of
quarters exactly up to 2019/20. From 2020/21 the annual figure is larger by 3,
9, 69, 119 and 584 cases, growing towards recent years. The two files were saved
about nine months apart: the quarterly file on 2025-11-04, the annual file on
2026-08-10 (`docProps/core.xml`).

**Officially documented:** "The complete dataset is subject to restating, when
necessary, to reflect current reporting requirements as determined by the
Ministry of Health in conjunction with the health authorities."

**Possible causes, not verified:**

- Restating to reflect reporting requirements, which the description says
  happens.
- Records arriving late and being included in the newer annual file. The
  description does not mention this.

Which one explains the differences here is not known.

**Why it matters for Step 5:** the two files cannot be expected to reconcile
exactly for recent years, even for an additive measure. Any difference between
them has to be checked against the vintage gap before it is attributed to
anything else.

**How to check:** when the quarterly file is next replaced, compare its
2020/21–2024/25 `COMPLETED` totals with this version's. That needs this version
to still exist. Raw files are currently overwritten on every ingest; see the
runbook.

### 4. What point in time does the annual `WAITING` figure represent?

**Status: officially documented. Checked against the data, which does not match
it exactly.**

**Officially documented:** "The number of cases waiting is captured at a point
in time, i.e., either at the end of the quarter or fiscal year." Read here as:
the end of the quarter in the quarterly files, and the end of the fiscal year
(March 31) in the annual file. If that reading is right, the annual figure
equals the Q4 figure, because both are counts on March 31.

**Checked** (`sql/profile/01_time_coverage.sql`, section 6, province-level total
rows). It does not hold exactly. Q4 minus the annual figure:

| Fiscal years | Q4 − annual |
|---|---|
| 2009/10 to 2017/18 | **+1 in every one of the nine years** |
| 2018/19 | −2 |
| 2019/20 | +5 |
| 2020/21 to 2024/25 | +31, +45, +138, +287, +376 |

No quarter equals the annual figure exactly in any year. Q4 is still far closer
than the others: in 2009/10 it is 1 away, while Q1 is 2,532 away. The growth
from 2020/21 onwards matches the vintage gap in Open question 3; the steady +1
in the early years does not, and is unexplained.

**Decision for gold: use the annual file's own annual figure.** Do not derive a
year's `WAITING` from Q4. The annual figure is the number the publisher
publishes; deriving it from Q4 would replace the publisher's definition with
ours.

**The difference is kept, not removed.** The one-case gap is recorded here as a
known difference between two published files. Smoothing it away would hide
exactly the kind of difference Step 5 exists to quantify.

### 5. 95 rows have blank percentiles that neither rule explains

**Status: recorded, not explained. Deliberately left unexplained.**

**What they are:** rows where `COMPLETED` is 5 or more, so the count was not
suppressed and surgeries were completed, yet both percentiles are blank. 54 in
the quarterly file, 39 in the annual file, 2 in the interim file.

**Where they sit** (`sql/profile/02_suppression.sql`, section 7):

- **Two procedure groups only:** `Uterine Surgery` (86 rows) and `Rib Resection`
  (9 rows).
- **18 hospitals**, in the Northern, Interior, Vancouver Coastal and Fraser
  health authorities. `G.R. Baker Memorial Hospital` has 21 and `Elk Valley
  Hospital` 13. Four rows are at health authority level (`Vancouver Coastal` +
  `All Facilities`), not at a single hospital.
- **Every fiscal year** from 2009/10 to 2026/27, between 1 and 11 rows a year.

No explanation is offered here, and none should be guessed at. What matters is
that the pattern is written down rather than mistaken for noise.

**Requirement for silver:** these rows must not be classified as suppressed or
as not applicable. Silver either carries a fourth state for them, or fails
loudly when it meets one. Both states have defined meanings — "a count of 1 to
4", "no value exists" — and putting an unexplained blank into either one would
make Step 5 reconcile against a number nobody has checked.
