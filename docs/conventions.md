# Conventions

The rules this project is built under, and why each one is here. They are not a
template: most of them were settled by something found in the data, and the
finding is named where that is the case.

## SQL is the transformation language

Every silver and gold transformation is SQL, executed through DuckDB. pandas is
used only at the edges: reading an API response, handing a frame to MLflow,
exporting for Power BI. No transformation logic is written in pandas.

**Why.** The transformations are the argument of this project, so they have to
be readable by anyone who reads SQL, and defensible line by line. One language
for the logic also means the rules live in one place, not split between a query
and the Python that post-processes it.

## Gold is a view over silver

The gold layer is defined as SQL views. A view is materialised only when
performance actually requires it, and the reason is written into the runbook.

**Why.** A view cannot drift away from its own definition. Materialising is a
performance decision, and a performance decision that nobody wrote down becomes
a mystery table six months later.

## Data never enters git

Source files land in `data/raw/` and are ignored. Only `_manifest.json` is
committed: source URL, sha256 and fetch time for each file. CI runs on a small
committed fixture instead.

**Why.** The raw files are tens of megabytes and the publisher restates them, so
they are not a stable artefact to version. The manifest is: it says exactly
which bytes a result came from.

**The fixture must contain suppressed rows.** Suppression is where this data
breaks pipelines, so a fixture without it tests nothing that matters. See the
three-state requirement in [data-dictionary.md](data-dictionary.md).

## Downstream code locates files by `resource_id`, never by filename

Silver and everything after it read `data/raw/_manifest.json` and find a file by
its catalogue `resource_id`.

**Why.** Resource names carry a year range — `2009_2026 Quarterly Surgical Wait
Times` — so filenames change with every release, while the resource id does not.
This is recorded as an open question in the data dictionary, because it holds
only if the Ministry replaces files inside existing resources rather than
creating new ones. The evidence so far says it does.

**What it paid for.** On 2026-09-17 the storage layout changed completely:
files moved from readable names to content addressing, each stored under the
sha256 of its own bytes, and the manifest became a version history rather than a
list of current files. Downstream, that cost one line in each file that resolves
a path — an `ORDER BY last_fetched_at_utc DESC LIMIT 1` — and nothing else. No
query knew or cared where the bytes were. A rule earns its keep the day
something underneath it moves.

## Every claim points at a query

Profiling queries live in `sql/profile/`, numbered in the order they were run.
Every factual claim in the documentation names the file and section it came
from, and every finding is tied to the file version it was drawn from through
the sha256 in the manifest.

**Why.** The publisher restates this data, so a finding without a version is a
finding that cannot be checked. Numbering keeps the order of the work legible:
later queries build on what earlier ones established.

## Every step leaves a written artefact

Data dictionary, quality rules, reconciliation memo, runbook. A step is not
finished when the query runs; it is finished when what the query showed is
written down, including what it failed to settle.

**Why.** Most of the cost of this data is in knowing what it means. The
documentation carries the open questions as openly as the answers, because an
unrecorded uncertainty turns into a silent assumption in the next layer.
