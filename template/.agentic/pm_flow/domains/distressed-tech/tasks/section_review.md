---

# Task: review an analyst's result

You own desk `{{SECTION_KEY}}`. An analyst has returned work for cycle
{{CYCLE}}. Judge it against the acceptance criteria you set, not against how
much effort it represents and not against how complete it reads.

Read:

{{CONTEXT_FILES}}

Check the evidence, not the summary. An analyst stating that a case number is
confirmed is not the same as a quote from the register showing it. If the
acceptance check was not actually run, that alone is a failure.

You share a model family with the analyst you are reviewing, so reading the
record and finding it plausible is worth nothing — plausible is precisely what a
fabricated administrator name, a remembered revenue figure and a hallucinated
case number all look like. Two things substitute for that missing independence,
and both are required:

- **Re-fetch one load-bearing fact yourself and paste what came back.** Pick the
  one the rest of the record depends on: the case number, the stage, the
  deadline, the price. A claim about a court, an amount or a date enters the
  record only next to the fetch that produced it, in the same file.
- **Run the counter-search and paste the result.** Search for the record being
  wrong: a later notice, a completed sale, a withdrawn filing, a different
  administrator, a second entity with the same name. A record whose central
  claim nobody tried to break is not evidence, and reading it will not tell you
  which kind it is.

If either is impossible in this cycle, say which and why in the Evidence check
section rather than passing over it.

Reject on any of these, without softening:

- a load-bearing fact with no verbatim quote, or a quote that does not actually
  contain the fact it is cited for
- a stage or a price sourced only from an aggregator when the register, the
  notice or the administrator's own publication was reachable
- a gap filled from the model's own knowledge of the world rather than recorded
  as a gap
- a record whose `verified_at` is missing, so nobody downstream can tell how
  stale the stage is
- an entity recorded twice under two names, or two entities merged into one
  record

Do not soften a rejection to keep things moving. A wrong record that is accepted
becomes a comparable, and a wrong comparable misprices every target measured
against it. This desk escalates repeated failure to an independent panel rather
than expecting you to absorb it.

If your decision is GO or GO_WITH_CHANGES, commit before you respond: this
desk's owned paths plus its `state.md` and `handoff.md`, in one commit whose
message names the desk and what this cycle established. Nothing outside your
owned paths. Do not commit on NO_GO.

## Respond with these sections only, each as a Markdown heading

1. Assessment
2. Drift review
3. Evidence check
4. Risks
5. Decision

Under **Evidence check**, name the fact you re-fetched, paste what came back,
and state the counter-search you ran and what it returned.

Under **Risks**, name what in this record is most likely to be wrong or to go
stale first, and what would reveal it.

The Decision section must contain exactly one line, and that line must begin
with one of these exact tokens: GO, GO_WITH_CHANGES, NO_GO. A short
justification may follow the token on the same line.
