# Power BI: the semantic model, in text

The report is built in Power BI Desktop, which is a GUI. This file is the part
of it that can be reviewed: every relationship, every hidden column, every
measure, and the reason for each. The project is saved as `.pbip`, so the model
itself lands in git as TMDL text; this document says what that text is supposed
to say and why.

**The report exists to enforce three things SQL cannot.** A SQL view cannot stop
anyone typing `SUM`. A semantic model can: a column whose summarisation is off
cannot be dragged onto a chart as a total, and a hidden column cannot be dragged
at all. Everything below serves that.

## Loading

```bash
python src/run_sql.py sql/export/01_export_for_power_bi.sql data/warehouse.duckdb
```

Nine Parquet files land in `data/export/`, about 3.6 MB. They are not committed:
the data stays out of git, and a fresh clone runs the line above to recreate
them. Power BI Desktop → Get Data → Parquet, one file per table.

| Table | Rows | What it is |
|---|---|---|
| `dim_quarter` | 69 | Every quarter from the first published to the last, including the four nobody published |
| `dim_facility` | 72 | 65 facilities plus 7 total members |
| `dim_health_authority` | 7 | 6 authorities plus the province total |
| `dim_procedure_group` | 85 | 84 categories plus `All Procedures` |
| `fact_volume_quarterly` | 166,385 | Leaf rows only. The one table that is safe to sum |
| `fact_totals_quarterly` | 39,771 | The publisher's own totals. Look up, never add |
| `fact_percentile_quarterly` | 206,156 | Published wait times at every level. No summable column in it |
| `reconciliation_quarterly` | 80,452 | One row per check: published, reported, bounds, gap |
| `about` | 1 | Provenance line for the page footer |

## Relationships

Single column each way, because Power BI relates on one column only. The
facility key and the period label are the natural keys written as one column —
deterministic, unchanged by a rebuild, and not surrogate keys. `dim_facility`
explains that at the top of `sql/gold/02_dim_facility.sql`.

| From | Column | To | Column | Cardinality |
|---|---|---|---|---|
| `fact_volume_quarterly` | `period_label` | `dim_quarter` | `period_label` | many-to-one |
| `fact_volume_quarterly` | `facility_key` | `dim_facility` | `facility_key` | many-to-one |
| `fact_volume_quarterly` | `procedure_group` | `dim_procedure_group` | `procedure_group` | many-to-one |
| `fact_volume_quarterly` | `health_authority` | `dim_health_authority` | `health_authority` | many-to-one |
| `fact_percentile_quarterly` | same four | | | many-to-one |
| `fact_totals_quarterly` | same four | | | many-to-one |
| `reconciliation_quarterly` | same four | | | many-to-one |

`about` stays unrelated: one row, read by a footer card.

**`reconciliation_quarterly` is related, with a condition.** Slicing the checks
by quarter, authority or procedure group is exactly how the staircase is read,
so the relationships earn their place. But its rows are three overlapping
decompositions of the same data — a province check, the authority checks beneath
it and the facility checks beneath those — so **every visual built on it filters
`edge` first**. Summed across edges it counts the same surgeries three times.

That is the one table in the model where the guard is a discipline rather than a
structure, and it is the reason the column is called `edge` and sits first in
the view. The fact tables are split by level precisely so that they need no such
discipline.

**Set `dim_quarter[period_label]` to sort by `ends_on`.** Without it the axis
sorts as text, which happens to be right today and will stop being right the
first time a label changes shape.

## Columns: hidden, and not summarised

The field list is the interface. Anything visible in it will eventually be
dragged onto a chart, so only two kinds of thing stay visible: dimension
attributes, and measures.

**Hide every column in every fact table.** All of them. The facts are reached
through measures only.

**Set Summarization to "Don't summarize"** on these, before hiding them, so that
the setting survives if someone unhides one later:

| Table | Column | Why |
|---|---|---|
| `fact_percentile_quarterly` | `p50_weeks`, `p90_weeks` | A percentile cannot be summed or averaged at any level. This is the single most important setting in the model |
| `fact_volume_quarterly` | `cases_waiting_at_period_end` | Additive across facilities, not across time. Only the measure below knows the difference |
| `fact_volume_quarterly` | `completed_min`, `completed_max`, `waiting_min`, `waiting_max` | Summable, but only in the bound measures, where they are paired |
| `fact_totals_quarterly` | `completed_cases`, `cases_waiting_at_period_end` | These are the publisher's totals at several levels at once. Summing them counts the province, its authorities and its facilities together |

Keep visible in the dimensions: `fiscal_year`, `quarter`, `period_label`,
`is_published`, `is_interim`, `health_authority`, `hospital_name`, `is_total`,
`procedure_group`, `is_residual`, and the `in_*_file` flags. Hide `facility_key`
and the `_seen` columns — they are machinery.

## Where the measures live

**All of them in one table, called `Measures`.** Create it with Home → Enter
Data, a single column named `placeholder`, no rows, then hide that column. The
table exists only to hold measures.

Two reasons, and the first is practical rather than tidy. Every column of every
fact table is hidden above, and Power BI drops a table from the field list when
it has no visible column and no measure. Put the measures in the fact tables and
the tables reappear, each holding a mixture of hidden machinery and the things
people are meant to use. Put them in `Measures` and the field list reads as what
it is: dimension attributes to slice by, and measures to show.

Second, a measure's home table suggests where its number comes from, and here
that suggestion would be wrong as often as right. `Shortfall vs published`
reads two fact tables. `Cases waiting (period end)` reads a fact table and a
dimension. Filing them under one of their inputs would state something untrue
about the other.

Set a display folder on each, so the list stays readable as it grows:

| Measure | Display folder | Format |
|---|---|---|
| `Completed cases` | Volume | Whole number, thousands separator |
| `Completed (lower bound)` | Volume\Bounds | Whole number |
| `Completed (upper bound)` | Volume\Bounds | Whole number |
| `Completed (range)` | Volume\Bounds | Text |
| `Withheld cells` | Volume\Suppression | Whole number |
| `Withheld share` | Volume\Suppression | Percentage, 1 decimal |
| `Cases waiting (period end)` | Waiting | Whole number, thousands separator |
| `P50 weeks (published)` | Wait times | Decimal, 1 place |
| `P90 weeks (published)` | Wait times | Decimal, 1 place |
| `Wait time note` | Wait times | Text |
| `Published total` | Reconciliation | Whole number, thousands separator |
| `Shortfall vs published` | Reconciliation | Whole number, thousands separator |
| `Checks made` | Reconciliation | Whole number, thousands separator |
| `Checks outside bounds` | Reconciliation | Whole number |

The DAX below references its source tables by name, so each definition works
wherever it is pasted; the home table only decides where it appears.

## Measures

### Volume

```dax
Completed cases = SUM(fact_volume_quarterly[completed_cases])
```

Plain sum, and safe, because `fact_volume_quarterly` holds leaf rows only. That
is a property of the view, not of this measure, and it is asserted in
`tests/test_silver_structure.py`.

```dax
Completed (lower bound) = SUM(fact_volume_quarterly[completed_min])
Completed (upper bound) = SUM(fact_volume_quarterly[completed_max])

Completed (range) =
VAR Lower = [Completed (lower bound)]
VAR Upper = [Completed (upper bound)]
RETURN IF(Lower = Upper, FORMAT(Lower, "#,0"),
          FORMAT(Lower, "#,0") & " – " & FORMAT(Upper, "#,0"))
```

A withheld count is between 1 and 4, so a group of them is between one and four
times their number. `Completed (range)` prints a single number when nothing is
withheld and an interval when something is, which is the honest answer in both
cases. Never fill in a value: `docs/not-provided.md` says why at length.

```dax
Withheld cells =
CALCULATE(
    COUNTROWS(fact_volume_quarterly),
    fact_volume_quarterly[completed_state] = "suppressed"
)

Withheld share =
DIVIDE([Withheld cells], COUNTROWS(fact_volume_quarterly))
```

### Waiting: semi-additive

```dax
Cases waiting (period end) =
CALCULATE(
    SUM(fact_volume_quarterly[cases_waiting_at_period_end]),
    LASTNONBLANK(dim_quarter[ends_on], CALCULATE(COUNTROWS(fact_volume_quarterly)))
)
```

`WAITING` counts the people on the list at one moment. Adding facilities is
legitimate — different people. Adding quarters is not: the same person waiting
three quarters is counted three times, and four quarters come to 3.8–4.3 times
the annual figure. This measure sums across everything except time, where it
takes the last period in the current selection.

Select a year and it gives the position at year end, which is what the
publisher's annual figure means. Select 2009/10 to 2024/25 and it gives the
position at the end of that span, not a sixteen-year total, because there is no
such thing.

### Percentiles: lookup, never arithmetic

```dax
P50 weeks (published) =
VAR RowsInContext = COUNTROWS(fact_percentile_quarterly)
VAR Value = SELECTEDVALUE(fact_percentile_quarterly[p50_weeks])
RETURN IF(RowsInContext = 1, Value, BLANK())

P90 weeks (published) =
VAR RowsInContext = COUNTROWS(fact_percentile_quarterly)
VAR Value = SELECTEDVALUE(fact_percentile_quarterly[p90_weeks])
RETURN IF(RowsInContext = 1, Value, BLANK())
```

**This is the enforcement that only exists here.** The publisher calculates a
percentile at every level it publishes, because a percentile cannot be rebuilt
from aggregates. So the model looks one up, and when the selection covers more
than one published row it returns nothing rather than an average of them.

A blank on screen invites "the data is missing", so pair it with:

```dax
Wait time note =
VAR RowsInContext = COUNTROWS(fact_percentile_quarterly)
RETURN
SWITCH(
    TRUE(),
    RowsInContext = 0, "No published row for this selection",
    RowsInContext > 1, "Published only at the levels the Ministry publishes — "
                       & "narrow the selection to one facility, procedure and quarter",
    ISBLANK([P50 weeks (published)]),
        "Withheld: " & SELECTEDVALUE(fact_percentile_quarterly[p50_state]),
    BLANK()
)
```

The third branch is the three-state distinction reaching the screen: a blank
percentile reads `suppressed`, `not_applicable` or `unexplained`, and the user
is told which.

### Reconciliation

```dax
Published total =
CALCULATE(
    SUM(fact_totals_quarterly[completed_cases]),
    fact_totals_quarterly[is_all_health_authorities] = TRUE,
    fact_totals_quarterly[is_all_procedures] = TRUE
)

Shortfall vs published =
[Published total] - [Completed cases]
```

`Published total` filters to one level explicitly. Written without those two
filters it would add the province to its own authorities and facilities.

```dax
Checks outside bounds =
CALCULATE(
    COUNTROWS(reconciliation_quarterly),
    reconciliation_quarterly[within_bounds] = FALSE
)

Checks made = COUNTROWS(reconciliation_quarterly)
```

Two cards side by side: 101,862 and 0. The second number is why the first page
is a finding and not an accusation.

## The page

One page, four visuals, and a footer.

**1. The staircase — the reason the report exists.** A horizontal bar chart of
four bars: the published province total, then the same figure summed from
authorities, from facilities, and from facility × procedure group. A reference
line at the published total. The bars carry `Completed (range)` as a label, so
the interval shows. Title: *the same question, four ways to add it up*.

Beside it, two cards: **101,862 checks · 0 outside bounds**, and the shortfall,
**116,431**. They belong next to each other. Alone, the first is an all-clear
nobody needs and the second is fault-finding.

**2. Withheld share by level.** Three bars: 0.2%, 11.7%, 33.2%. This answers the
question the staircase provokes — why does it only bend at the last step — and
the answer is that the loss lives in the procedure dimension, not the geography.

**3. The quarterly series, with the hole in it.** A line of `Completed cases` by
`period_label`, with the four unpublished quarters of 2025/26 visible as a
break. Use `dim_quarter[is_published]` to shade or to mark them; do not let the
line join across. This is `dim_period` earning its place: the gap is a row in
the model, so the chart cannot quietly smooth over it.

**4. Wait times, as a lookup.** A table of `P50 weeks (published)` and
`P90 weeks (published)` by health authority for one selected quarter and
procedure group, with `Wait time note` as a column. Slice to a level the
publisher does not publish and the values blank out with the note explaining
why. That refusal is the point of the visual.

**Footer:** a card bound to `about[provenance_line]`. It reads something like
*BC Surgical Wait Times · file version 2026-09-15, confirmed unchanged
2026-09-17 · quarterly 077444690d6e · report built 2026-09-19*. A screenshot
travels; this is how it keeps its provenance.

The vintage curve is not on the page. It belongs to
`docs/reconciliation-memo.md`, and putting it here would split the page's
argument in two.

## Saving and what goes in git

Save as **`.pbip`** (Power BI Project), with TMDL and PBIR enabled, into
`powerbi/`. That writes the semantic model and the report layout as text files,
so the measures and the summarisation settings above can be diffed and reviewed.

**The `.pbix` is not committed.** It is a binary that git cannot diff, that
grows the history by its whole size on every save, and that nobody without
Power BI Desktop can open.

**Screenshots are the primary deliverable**, in `docs/images/`: the full page,
and a close-up of the staircase with its two cards. The README embeds the full
page. Someone who never opens Power BI should still see the result.
