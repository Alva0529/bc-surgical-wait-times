# BC Surgical Wait Times — lakehouse build and disclosure-control reconciliation

[![tests](https://github.com/Alva0529/bc-surgical-wait-times/actions/workflows/ci.yml/badge.svg)](https://github.com/Alva0529/bc-surgical-wait-times/actions/workflows/ci.yml)

> **Status: in progress.** Steps 1 to 5 complete, the Power BI report next.
> See Roadmap below.

## What this is

A small end-to-end build on British Columbia's published surgical wait time
data: ingestion, a layered transformation pipeline, a dimensional model, and a
reconciliation analysis.

The point of it is what goes wrong when this data is read the obvious way. The
query runs, the chart renders, the number looks plausible, and it is wrong.

## Two numbers

**Adding the published data up by facility and procedure group gives 116,431
fewer surgeries than the province's own total — 2.9% of seventeen years of
surgery — with nothing on screen to say so.** Counts below 5 are withheld for
privacy, and at that grain a third of the cells are withheld.

**The data is not at fault, and that is half the finding.** Across 101,862
checks of every published total against its own detail, at every level and in
every period, not one difference falls outside what the suppression rule allows.
The shortfall is the price of reading the files finer than they were published,
and [the reconciliation memo](docs/reconciliation-memo.md) prices it by level:
by health authority, the province's figure comes back exactly.

---

**Open the same file with default settings, sum the completed column, and you
get 23,152,333 surgeries. The real figure is 3,879,192.**

Two ordinary mistakes, one number. The file carries the publisher's own
subtotals beside the detail, so each case is counted about six times over. And a
suppressed count is the literal text `<5`, so the column refuses to load as a
number — until the reader passes the flag that ignores errors, at which point
57,948 withheld counts become `NULL` and the sum quietly excludes them.

Nothing raises an error at any point.

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

Each of these produces a number that looks right, and none of them raises
anything. The pipeline handles each explicitly rather than by default; the
write-up of each is linked beside it.

| | The obvious reading | What it actually does |
|---|---|---|
| **1** | Trust the metadata: the quarterly file says it covers 2025/26 | It ends at 2024/25 Q4. No file publishes that year, so a trend line runs straight across it and `LAG()` calls a five-quarter jump a quarter-on-quarter change. Gap and overlap are two outcomes of the same publishing window. [Open question 2](docs/data-dictionary.md) |
| **2** | Read a withheld count as zero, or as missing | It is a count of 1 to 4. Zeros are published — 15,771 of them — so the detail sums short of the published total by an amount nothing reports. [Bounds requirement](docs/data-dictionary.md) |
| **3** | Average the wait-time percentiles | A percentile cannot be rebuilt from aggregates. Ten facilities' 90th percentiles averaged is a wait nobody had. [not-provided.md](docs/not-provided.md) |
| **4** | Sum `WAITING` across quarters, as one sums `COMPLETED` | It is a snapshot, not a flow: four quarters come to 3.8–4.3 times the annual figure. The two columns sit side by side, both whole numbers. [not-provided.md](docs/not-provided.md) |
| **5** | Read both kinds of measure column the same way | One suppression rule, two encodings: `<5` in the counts, an empty cell in the percentiles. The counts refuse to load, which is the good case. The percentiles load and vanish from every average — `avg()` returns 8.25 weeks from 129,180 of 202,953 rows. [Runbook pitfalls](docs/runbook.md) |
| **6** | Drop total rows with `LIKE 'All %'` | `All Other Procedures` is a category, not a total. Dropping it removes 110,827 completed surgeries from the annual file. [Hierarchy totals](docs/data-dictionary.md) |

One thing this pipeline will not do is fill in a withheld value. Not
proportionally, not at the midpoint of 1 and 4, not at all. A suppressed count
is carried as the interval the publisher's own rule guarantees.
[`docs/not-provided.md`](docs/not-provided.md) lists everything else left out on
purpose, and why. The short version: "assuming every suppressed cell is 2" is a
defensible sentence in a report, because the assumption travels with the number
— it has an author, a date and a reason. A column called
`completed_cases_estimated`, sitting in a warehouse six months later, carries
none of that. An estimate that leaves its context behind stops being an estimate
and becomes a fact.

## Roadmap

- [x] **1. Ingest** — resolve files through the catalogue API, land them
  unchanged, record source URL, checksum, and fetch time
- [x] **2. Data dictionary** — document grain, columns, and the suppression
  encoding as published
- [x] **3. Silver** — typed and reshaped, with suppression carried as an
  explicit state; data quality rules expressed as tests
- [x] **4. Gold** — dimensional model (health authority, facility, procedure
  group, fiscal period)
- [x] **5. Reconciliation** — quantify the gap between published totals and the
  sum of published detail, by level and period
- [ ] **6. Report** — Power BI dashboard on the gold views
- [ ] **7. Forecast** — case backlog trend, experiments tracked in MLflow
- [ ] **8. T-SQL port** — the same DDL and gold views written for SQL Server in
  `sql/tsql/`, to show the model carries over to a server engine

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

The tests need no data: they build the silver layer from small committed
fixtures, so a fresh clone can run them.

```bash
python -m pytest
```

Assertions that pin facts about the published files, rather than the pipeline,
are marked `realdata` and skip without a warehouse. See
[`docs/runbook.md`](docs/runbook.md).

### Why DuckDB

The warehouse here is a single DuckDB file so that the whole project clones and
runs on any machine with no server setup. The modelling and the analytical SQL —
star schema, CTEs, window functions — are standard and carry over to a server
engine unchanged. A T-SQL port of the same DDL is planned, in `sql/tsql/`; see
step 8 of the roadmap.

## Layout

```
data/raw/            source files, not committed
data/raw/_manifest.json   source URL, sha256 and fetch time for each file
docs/                data dictionary, conventions, runbook, what is left out on purpose
sql/profile/         numbered profiling queries; every claim in the docs names one
src/ingest.py        resolves the files through the catalogue API and lands them
src/run_sql.py       runs a .sql file and prints every result
```

[`docs/conventions.md`](docs/conventions.md) has the rules the build follows and
why each one is there. [`docs/not-provided.md`](docs/not-provided.md) has what
the model deliberately does not give you, and what to do instead — an average of
percentiles, a `waiting` figure summed across quarters, and two others.