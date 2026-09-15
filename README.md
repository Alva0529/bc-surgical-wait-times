# BC Surgical Wait Times — lakehouse build and disclosure-control reconciliation

> **Status: in progress.** Step 1 of 7 complete. See Roadmap below.

## What this is

A small end-to-end build on British Columbia's published surgical wait time
data: ingestion, a layered transformation pipeline, a dimensional model, and a
reconciliation analysis.

The point of the project is the errors this data produces without raising an
error. The query runs, the chart renders, the number looks plausible, and it is
wrong. Four are documented so far, below.

## Data source

| | |
|---|---|
| Dataset | BC Surgical Wait Times |
| Publisher | Health Sector Information Analysis and Reporting, BC Ministry of Health |
| Catalogue | BC Data Catalogue (`bc-surgical-wait-times`) |
| Coverage | Annual: fiscal 2009/10 to 2025/26. Quarterly: 2009/10 Q1 to 2024/25 Q4, then 2026/27 Q1 (interim). Files as fetched 2026-09-15. |
| Licence | Open Government Licence – British Columbia |

**No personal or identifiable health information is used anywhere in this
project.** The source files are aggregate counts published for public release,
already subject to the Ministry's disclosure control rules.

## Four ways to be wrong without an error

### 1. A year of quarterly data is missing, and the metadata says it isn't

The quarterly file is named `2009_2026` in the catalogue, and its declared
coverage runs to 2026-03-31. **The file itself ends at 2024/25 Q4.** The interim
file starts at 2026/27 Q1. None of the dataset's files contains quarterly data
for 2025/26 (as fetched on 2026-09-15).

Nothing breaks. A quarterly trend line runs straight from 2024/25 Q4 to
2026/27 Q1, and nothing on the chart says a year is missing. A `LAG()` over the
ordered quarters treats 2024/25 Q4 as the quarter before 2026/27 Q1, so a
"quarter-on-quarter change" is actually a change across five quarters.

Anyone who trusts the metadata has no reason to check. It was found only by
listing every period actually present in the file
(`sql/profile/01_time_coverage.sql`).

### 2. Totals don't equal the sum of their parts

The data is released under disclosure control. From the publisher's own
description, values below a threshold, and their wait times, are withheld. As a
result, an "all facilities" row may not match the sum of the individual
facilities.

That protection is correct and necessary. The trap is what a pipeline does with
a withheld value. It is **not zero and not missing**: it is a known-positive
quantity below a known ceiling. Collapsing it to `0` understates totals.
Collapsing it to `NULL` hides the fact that a real case volume exists. Either
way, summing the detail gives a smaller number than the published total, and
nothing says so. This pipeline carries a withheld value as a distinct state.

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

---

All four have the same shape. The default behaviour, whether that is trusting
the metadata, connecting the points or summing the column, produces a wrong
number and no error. This pipeline is built to handle each one explicitly and
never leave it to a default.

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