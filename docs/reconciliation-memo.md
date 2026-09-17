# Reconciliation memo: what disclosure control costs this data

Add up BC's published surgical volumes by facility and procedure group, and you
get **2.9% fewer surgeries than the province's own published total — 116,431
cases out of 3.95 million — with nothing on screen to say so.**

The shortfall is not spread evenly, and that is the useful part. Adding up by
health authority gives the province's figure **exactly**. Adding up by facility
loses 99 cases in seventeen years. The loss appears when the data is cut by
procedure group, and it appears at the level where most analysis happens.

| Same question, four ways to add it up | Completed surgeries | What the bounds allow |
|---|---|---|
| The published province total | **3,954,980** | — |
| Summed from the six health authorities | 3,954,980 | exact |
| Summed from individual facilities | 3,954,881 | 3,954,920 – 3,955,037 |
| Summed from facility × procedure group | **3,838,549** | 3,893,778 – 4,059,465 |

*Quarterly files, 2009/10 Q1 to 2026/27 Q1.*

**The published data is not at fault, and this matters to the conclusion.**
Across 101,862 parent-child checks — every total against its own detail, at
every level, in every period, for both measures — **not one difference falls
outside what the suppression rule can account for**. The files are internally
consistent to the case. The 116,431 are the cost of reading them at a grain
finer than the publisher's suppression threshold, not evidence of a problem with
them.

## What this means for the questions you can ask

| Question | Answer from this data |
|---|---|
| How many surgeries province-wide, or by health authority? | Exact. |
| How many at one hospital, all procedures? | Exact to within 99 cases across seventeen years. |
| How many hip replacements at one hospital? | **An interval, not a number.** A third of those cells are withheld. |
| What is the wait time for a grouping the publisher did not publish? | Not available at any accuracy. Percentiles cannot be recomputed. |

The practical rule: **the geography dimension is safe, the procedure dimension
is where the data thins out.** A dashboard sliced by health authority is
reporting the province's own figures. The same dashboard sliced by procedure
group is reporting between 97% and 103% of them, and does not say which.

## Why an interval rather than an estimate

The publisher withholds "all values less than 5 and their corresponding wait
times". A withheld count is therefore between 1 and 4, and this pipeline carries
that band on every cell rather than filling in a number. Summed over a group of
withheld cells, the band gives the interval in the table above.

Nothing here estimates a hidden value. `docs/not-provided.md` says why at
length: an assumption stated in a report has an author, a date and a reason,
and the same assumption compiled into a warehouse column has none of them.

Three independent lines of evidence support reading `<5` as 1 to 4 rather than
0 to 4. They are listed in `docs/data-dictionary.md`; the third comes from this
reconciliation. Across 47,576 checks with at least one withheld child, the gap
divided by the number of withheld children ranges from **1.0 to 4.0, median
2.0**. Not one check implies an average below 1, which is what a suppressed zero
would produce.

## A second difference, which is not suppression at all

A fiscal year can also be compared against its own four quarters. That
comparison crosses two published files, and it behaves completely differently.

| Fiscal year | Rows the two files disagree about | Share | Cases |
|---|---|---|---|
| 2009/10 – 2019/20 | **0** of ~29,000 | 0% | — |
| 2020/21 | 25 | 0.94% | 19 |
| 2021/22 | 42 | 1.56% | 54 |
| 2022/23 | 67 | 2.41% | 420 |
| 2023/24 | 155 | 5.61% | 715 |
| 2024/25 | **385** | **14.02%** | **3,486** |

*Rows where the annual figure falls outside the interval its four quarters
allow, so suppression cannot account for the difference.*

Eleven years agree exactly. Then the disagreements appear and grow every single
year. **A monotonic rise by recency is the signature of restatement, not of
suppression** — suppression does not care how old a year is, while revision
does. The publisher states that the data "is subject to restating", and the two
files were produced nine months apart: the quarterly file was saved 2025-11-04,
the annual one 2026-08-10.

The practical consequence: **for 2024/25, one row in seven disagrees between the
annual and the quarterly file.** A report that draws recent figures from both
will not reconcile, and the cause has nothing to do with disclosure control.

This is why the two comparisons are computed separately. Folded together, those
3,486 restated cases would have been reported as data hidden by suppression.

## Method

Three parent-child edges, because the hierarchy has two dimensions and both have
parents:

| Edge | Parent | Children |
|---|---|---|
| Procedures within a level | `All Procedures` | the 84 procedure groups at that same level |
| Province from authorities | the province row | the six health authority rows, same procedure |
| Authority from facilities | a health authority row | its facilities, same procedure |

Each check reports the published figure, the children that were published, the
gap, the interval the suppression rule allows, and the average that gap implies
per withheld child. Both measures are checked: completed cases, and cases
waiting at period end. Wait time percentiles are not reconciled, because they
cannot be aggregated at all.

**The gap is never assumed to be suppression.** It is compared against what
suppression could account for, and anything failing that comparison is listed
rather than absorbed. That listing is currently empty for every within-file
check, which is the finding, not an absence of one.

Queries: `sql/gold/20_reconciliation_quarterly.sql`,
`21_reconciliation_annual.sql`, `22_vintage.sql`.

## What is still unexplained

**8,941 checks could not be made**, because the parent row was itself withheld.
A suppressed total has no figure to compare its children against. These are
small facilities in small procedure groups, and they are reported as
not-checkable rather than counted as passing.

**95 rows have a blank wait time that no rule explains**: the count was
published, surgeries were completed, and the percentiles are blank anyway. They
are confined to two procedure groups, `Uterine Surgery` and `Rib Resection`,
across 18 facilities and every fiscal year. The model gives them their own state
rather than filing them under suppressed or not-applicable, and a test pins
their number so that a change in them is noticed.

**The annual waiting count is exactly one below the Q4 count, in nine
consecutive years.** 2009/10 through 2017/18, every year, by one case. The value
of this observation is what it rules out: a difference of exactly one, repeated
nine times, is not random error and is not restatement — a revision that landed
on one case nine years running is not a revision. It is a definitional
difference between how the two files count the list on 31 March. Which
definition differs is unknown; that it is definitional rather than accidental is
not. From 2018/19 the difference grows (−5, −31, −45, −138, −287, −376), which
is the restatement pattern above reasserting itself over the top of it.

## Reproducing this

Every figure above comes from the files fetched 2026-09-15, stored under their
checksums: quarterly `077444690d6e…`, annual `2d9f99cbe4dd…`, interim
`5d801d6aabe8…`. The manifest records them, and the files are archived by
content, so these numbers can be recomputed from the same bytes after the
publisher restates anything.

```bash
python src/ingest.py
python src/run_sql.py sql/silver/01_silver_annual.sql data/warehouse.duckdb
python src/run_sql.py sql/silver/02_silver_quarterly.sql data/warehouse.duckdb
python src/run_sql.py sql/gold/20_reconciliation_quarterly.sql data/warehouse.duckdb
python src/run_sql.py sql/gold/22_vintage.sql data/warehouse.duckdb
```

The figures in this memo are not yet pinned by assertions. Adding them to
`tests/test_current_data.py` is the next step, so that a later release moving
any of them fails a test rather than quietly ageing this document.
