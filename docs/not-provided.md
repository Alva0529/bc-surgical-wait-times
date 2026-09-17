# What this model deliberately does not provide

Every entry here is something a reader might reasonably expect to find, that is
missing on purpose. Each says what is absent, why, and what to do if you really
need it.

The list exists because an absence looks exactly like an oversight. Without it,
the next person to open this warehouse finds no average wait time, assumes it
was forgotten, and writes one — which is the error the model was shaped to
avoid.

---

## No `avg_wait_weeks`, and no average of any percentile

**Absent:** any column or view that averages `p50_weeks` or `p90_weeks` across
facilities, procedure groups or periods.

**Why.** A percentile cannot be recomputed from aggregated data, which is why
the publisher provides one at every level of the hierarchy rather than expecting
anyone to derive it. The average of ten facilities' 90th percentiles is not the
90th percentile of their patients: it weights a hospital with 8 cases the same
as one with 8,000, and the result is a wait time nobody experienced.

**If you need a wait time at a higher level:** look it up. The publisher already
calculated it, and the model carries it at every level it was published at. That
is what the percentile views are for — lookup, never arithmetic.

**If you need something the publisher did not publish**, for example a
percentile for a group of hospitals that is not one of their groupings, it
cannot be computed from this data at all. It needs the case-level records, which
are not public.

In business terms: "what is the average wait in the Interior?" is not a question
this data answers by averaging its hospitals. "What was the 90th percentile wait
for hip replacement in the Interior in 2024/25?" is, and the publisher has
already worked it out.

---

## No aggregation of `waiting` across periods

**Absent:** any view that sums or averages `cases_waiting_at_period_end` over
more than one period, including any annual `waiting` figure derived from four
quarters.

**Why.** `waiting` is a count at a point in time: the patients on the list at the
end of that quarter or fiscal year. A patient still waiting across three
quarters is counted in all three. Adding the quarters up gives roughly four
times the annual figure — 3.83 to 4.25 times, measured across all 16 complete
fiscal years — and the result means nothing at all.

**If you need a year's `waiting`:** take it from the annual file, where the
publisher states it as of March 31. It is in `silver_annual`, and the gold
annual views carry it.

**If you need a figure across a span of quarters:** decide which single
point in time you mean, and take that quarter's value. "How many were waiting
during 2023/24" is not a question this measure can answer; "how many were
waiting on 31 March 2024" is.

---

## No surrogate keys

**Absent:** integer key columns on the dimensions. A facility is identified by
its name, a period by `'2009/10'` and `'Q1'`.

**Why.** Surrogate keys have to be stable to be worth anything, and a key
generated inside a view is not: add one hospital upstream and every number
shifts, breaking anything that stored the old ones. Making them stable means
materialising the dimensions, which trades away the property that gold is a set
of views over silver. At this size — 6 health authorities, 65 hospitals, 85
procedure groups, 69 quarters — an integer join buys nothing measurable. The
trade was made deliberately, not skipped.

**If you need them**, for example to port the model to SQL Server, where a
conventional star schema is expected: materialise the dimensions, generate the
keys there, and add the drift test described in `runbook.md` so the materialised
copy cannot fall out of step with its definition. That is planned work, step 8
of the roadmap.

In business terms: "will the reference I saved for this hospital still mean the
same hospital next quarter?" With the publisher's own name as the key, yes,
until the publisher renames it — and the tests pin the facility roster so a
rename shows up as a failure rather than as a hospital that quietly appears new.

---

## No fact view mixing detail rows with the publisher's total rows

**Absent:** a single fact table holding both hospital-level rows and the
`All Facilities` / `All Procedures` / `All Health Authorities` rows.

**Why.** The publisher's totals are data, not derivable: suppression means they
do not equal the sum of their parts, and the percentiles exist only at the
levels where they were published. So the totals have to be kept. But once they
sit in the same table as the detail, the most ordinary query in the world —
`SELECT sum(completed) FROM fact` — counts every surgery twice, and raises no
error.

Splitting the views by level makes the default correct: summing the detail view
sums detail, because that view holds nothing else.

**If you need to compare a published total against the sum of its parts:** that
is the reconciliation, and it has its own view. It joins the two deliberately,
which is the point — it is the one place where mixing them is the intent rather
than the accident.

In business terms: "how many surgeries were completed in BC in 2024/25?" has two
defensible answers — the figure the Ministry publishes, and the total of what
individual hospitals reported. They differ by whatever suppression hides. Asking
one table for both is what produces a third number, twice the size, that answers
neither.
