# BC Surgical Wait Times — lakehouse build and disclosure-control reconciliation

> **Status: in progress.** Step 1 of 7 complete. See Roadmap below.

## What this is

A small end-to-end build on British Columbia's published surgical wait time
data: ingestion, a layered transformation pipeline, a dimensional model, and a
reconciliation analysis of what the province's small-cell suppression rule costs
you analytically.

The last part is the point of the project. Public health data is released under
disclosure control — counts below a threshold are withheld so that individuals
cannot be re-identified. That protection is correct and necessary, and it also
means the published totals do not reconcile against the published detail. Anyone
building reporting on this data has to decide how to handle that, and most
pipelines silently get it wrong.

## Data source

| | |
|---|---|
| Dataset | BC Surgical Wait Times |
| Publisher | Health Sector Information Analysis and Reporting, BC Ministry of Health |
| Catalogue | BC Data Catalogue (`bc-surgical-wait-times`) |
| Coverage | Fiscal 2009/10 to current, quarterly and annual |
| Licence | Open Government Licence – British Columbia |

**No personal or identifiable health information is used anywhere in this
project.** The source files are aggregate counts published for public release,
already subject to the Ministry's disclosure control rules.

## The suppression rule

From the publisher's own description of the dataset:

- Values below a threshold, and their corresponding wait times, are withheld.
- As a result, total rows may not equal the sum of their sub-rows. An
  "all facilities" row may not match the sum of the individual facilities.
- Wait time percentiles cannot be recomputed from aggregated data, so the
  publisher provides them separately at every level of the hierarchy.

Two consequences drive the design of this pipeline:

1. A withheld value is **not zero and not missing**. It is a known-positive
   quantity below a known ceiling. Collapsing it to `0` understates totals;
   collapsing it to `NULL` loses the fact that a real case volume exists. This
   pipeline carries it as a distinct state.
2. The 50th and 90th percentile wait times are **not additive and not
   averageable** across facilities or procedure groups. Any measure that sums or
   averages them is wrong, however reasonable it looks on a dashboard.

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

### Why DuckDB

The warehouse here is a single DuckDB file so that the whole project clones and
runs on any machine with no server setup. The modelling and the analytical SQL —
star schema, CTEs, window functions — are standard and carry over to a server
engine unchanged; `sql/tsql/` holds the same DDL written for SQL Server.

## Layout