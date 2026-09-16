# BC Surgical Wait Times — lakehouse build and disclosure-control reconciliation

> **Status: in progress.** Step 1 of 7 complete. See Roadmap below.

## What this is

A small end-to-end build on British Columbia's published surgical wait time
data: ingestion, a layered transformation pipeline, a dimensional model, and a
reconciliation analysis.

The point of the project is what goes wrong when this data is read with default
behaviour. The query runs, the chart renders, the number looks plausible, and it
is wrong. Where the published figures can be checked against each other they
hold together, to six cases in four million (see 6 below). The errors are the
reader's, not the publisher's. Six are documented so far.

## Data source

| | |
|---|---|
| Dataset | BC Surgical Wait Times |
| Publisher | Health Sector Information Analysis and Reporting, BC Ministry of Health |
| Catalogue | BC Data Catalogue (`bc-surgical-wait-times`) |
| Source system | Surgical Patient Registry, fed directly by hospitals across the province |
| Coverage | Annual: fiscal 2009/10 to 2025/26. Quarterly: 2009/10 Q1 to 2024/25 Q4, then 2026/27 Q1 (interim). Files as fetched 2026-09-15. |
| Licence | Open Government Licence – British Columbia |

This project relies on two official sources, both read on 2026-09-15. They cover
different things:

- **Data rules**: the dataset description in the BC Data Catalogue. It covers
  which files exist, when they are updated, what each measure means, and how
  small numbers are suppressed. Quoted in full in
  [`docs/data-dictionary.md`](docs/data-dictionary.md).
- **Data lineage**: the Ministry of Health's
  [surgical wait times page](https://www2.gov.bc.ca/gov/content/health/accessing-health-care/surgical-wait-times).
  It says where the data comes from: "Surgical wait times data is collected in
  the Surgical Patient Registry and comes directly from the hospitals across the
  province. [...] The accuracy of the registry is entirely dependent on the data
  submitted by the facilities."

**No personal or identifiable health information is used anywhere in this
project.** The source files are aggregate counts published for public release,
already subject to the Ministry's disclosure control rules.

## Six ways to be wrong without an error

The publisher does not claim this data is complete. The Ministry's page says so
directly:

> The Ministry, in conjunction with the health authorities makes every effort to
> ensure the data contained on this site is accurate and timely, however it
> cannot guarantee the completeness of the information as it is gathered from a
> variety of health authority sources.

A pipeline that treats the published files as complete, and lets defaults fill
in whatever is missing, assumes exactly what the publisher says it cannot
guarantee. Below are four ways that goes wrong without an error.

### 1. A year of quarterly data is missing, and the metadata says it isn't

The quarterly file is named `2009_2026` in the catalogue, and its declared
coverage runs to 2026-03-31. **The file itself ends at 2024/25 Q4.** The interim
file starts at 2026/27 Q1. None of the dataset's files contains quarterly data
for 2025/26 (as fetched on 2026-09-15).

**This is not a one-off.** The publisher's own description sets it up. The
interim file holds "current fiscal year quarters only", and the historical files
"are updated in September to include data for the previous fiscal year". The two
updates are not synchronised. In this cycle, the interim file moved on to
2026/27 and the annual file received 2025/26, both on 2026-08-12. The quarterly
file has not been updated since 2025-11-05. So the 2025/26 quarters have left one
file and not yet arrived in the other.

If the updates land in the opposite order, the same window produces the opposite
error. The historical file gains a year while the interim file still holds it,
and those quarters appear twice. **A gap and an overlap are two outcomes of the
same timing window, and that window can open every year.**

Nothing breaks either way. In a gap, a quarterly trend line runs straight across
the missing year. A `LAG()` over the ordered quarters treats 2024/25 Q4 as the
quarter before 2026/27 Q1, so a "quarter-on-quarter change" is actually a change
across five quarters. In an overlap, a `UNION ALL` of the two files counts the
same quarter twice, and it looks like a surge in surgical volume.

Anyone who trusts the metadata has no reason to check, and a pipeline has no way
of knowing it is running inside the window. The gap was found only by listing
every period actually present in the file (`sql/profile/01_time_coverage.sql`).

### 2. Totals don't equal the sum of their parts

The data is released under disclosure control. From the publisher's
description: "All values less than 5 and their corresponding wait times are
suppressed. Therefore, rows with total volumes may not match the sum of sub
rows."

That protection is correct and necessary. The trap is what a pipeline does with
a withheld value. It is **not zero and not missing**: it is a count of 1 to 4.
Zero is not suppressed — a literal `0` appears 15,771 times in the quarterly
file's `COMPLETED` column, while no published count anywhere lies between 1 and
4. Collapsing a withheld value to `0` understates totals. Collapsing it to
`NULL` makes it look like a cell that was never reported. Either way, the detail
no longer adds up to the published total, and nothing says so. This pipeline
carries a withheld value as a distinct state, with a known range.

### 3. Percentiles can't be added or averaged

The 50th and 90th percentile wait times cannot be recomputed from aggregated
data, so the publisher provides them separately at every level of the hierarchy.
They are **not additive and not averageable** across facilities, procedure
groups or periods. A dashboard that averages them shows a wait time nobody
actually waited, however reasonable it looks.

### 4. `WAITING` is a snapshot, so adding it up across periods means nothing

`COMPLETED` counts cases done during a period: four quarters add up to the
fiscal year, exactly in every year from 2009/10 to 2019/20 and within 0.2%
since. `WAITING` counts
cases on the list at a point in time: four quarters add up to **3.8 to 4.3 times
the annual figure**, in every one of the 16 complete fiscal years.

The two columns sit side by side in the same table, both whole numbers. A BI tool
sums both by default.

### 5. One suppression rule, two encodings, two different failures

The same rule is written into the files two different ways. A suppressed count
is the literal text `<5`. A suppressed percentile is an empty cell. Same file,
same rule, two encodings — and they behave nothing alike.

**The count columns contain text.** DuckDB's `read_xlsx` reads the column as a
number and stops at the first `<5` cell (F35 of the quarterly file). pandas
keeps the column as `object`, and `df['COMPLETED'].sum()` raises a `TypeError`.
Both refuse to guess, which is the good case. Tell either one to ignore the
errors and all 57,948 suppressed counts turn into the same `NULL` used for a
value that was never reported: with `ignore_errors = true`, DuckDB totals
23,152,333 completed cases and says nothing.

**The percentile columns are numbers with blanks.** They load cleanly
everywhere. Every aggregate skips the blanks on its own:
`avg(PERCENTILE_COMP_50TH)` over the quarterly file returns 8.25 weeks, computed
from 129,180 of 202,953 rows. The 73,773 rows left out are the suppressed ones
and the ones where nothing was completed — the small facilities. Nothing in the
result mentions that a third of the file did not take part. And by 3 above, an
average of percentiles was never a wait time anybody had.

The counts announce the problem. The percentiles never do.

### 6. `All Other Procedures` looks like a total and is not

`PROCEDURE_GROUP` holds 85 values: `All Procedures`, which is the total, and 84
real categories. One of those categories is called `All Other Procedures` — the
residual bucket, everything not in a named group. A filter written as
`LIKE 'All %'`, which is how "drop the total rows" usually gets written, drops it
along with the total.

Province-wide in the annual file, fiscal 2009/10 to 2025/26:

| | Completed surgeries |
|---|---|
| Published `All Procedures` total | 4,169,291 |
| Short by, adding up the 84 categories | **6** |
| Short by, once `All Other Procedures` is dropped as a "total" | **110,827** |

Six cases in seventeen years. Each of those six sits in a year where exactly one
procedure group was suppressed province-wide, and each gap is between 1 and 4 —
the range `<5` stands for. The quarterly file behaves the same way: 22 cases
across 64 quarters, from 11 suppressed groups, every gap inside the same bound.

So the published detail reconciles to the published totals, once suppression is
accounted for. The 110,827 are not in the data. They are what one plausible line
of SQL costs.

---

All six have the same shape. The default behaviour — trusting the metadata,
connecting the points, summing the column, letting a blank drop out of an
average, pattern-matching a label — produces a wrong number and no error. This
pipeline is built to handle each one explicitly and never leave it to a default.

None of this is a complaint about the data. Where the published figures can be
checked against each other, they hold: the detail adds up to the published
totals to within six cases in 4,169,291, and every gap that remains is one
suppressed group of 1 to 4 cases. The Ministry publishes what it says it
publishes, under a suppression rule it documents. What this project is about is
how that data gets read.

## Roadmap

- [x] **1. Ingest** — resolve files through the catalogue API, land them
  unchanged, record source URL, checksum, and fetch time
- [ ] **2. Data dictionary** — document grain, columns, and the suppression
  encoding as published
- [ ] **3. Silver** — typed and reshaped, with suppression carried as an
  explicit state; data quality rules expressed as tests
- [ ] **4. Gold** — dimensional model (health authority, facility, procedure
  group, fiscal period)
- [ ] **5. Reconciliation** — quantify the gap between published totals and the
  sum of published detail, by level and period
- [ ] **6. Report** — Power BI dashboard on the gold views
- [ ] **7. Forecast** — case backlog trend, experiments tracked in MLflow

## Running it

Requires Python 3.12. No database server to install — the warehouse runs in
DuckDB as a local file.

```bash
uv venv --python 3.12
.venv\Scripts\activate
uv pip install -r requirements.txt

python src/ingest.py
```

Raw files land in `data/raw/` and are not committed. `data/raw/_manifest.json`
records what was fetched.

Profiling queries run the same way, from the repository root:

```bash
python src/run_sql.py sql/profile/01_time_coverage.sql
```

### Why DuckDB

The warehouse here is a single DuckDB file so that the whole project clones and
runs on any machine with no server setup. The modelling and the analytical SQL —
star schema, CTEs, window functions — are standard and carry over to a server
engine unchanged; `sql/tsql/` holds the same DDL written for SQL Server.

## Layout

```
data/raw/            source files, not committed
data/raw/_manifest.json   source URL, sha256 and fetch time for each file
docs/                data dictionary, conventions, runbook
sql/profile/         numbered profiling queries; every claim in the docs names one
src/ingest.py        resolves the files through the catalogue API and lands them
src/run_sql.py       runs a .sql file and prints every result
```

[`docs/conventions.md`](docs/conventions.md) has the rules the build follows and
why each one is there.