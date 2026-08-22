## Objective

- Run the same work under two agent team designs and report what each cost,
  where each escalated, and how long each took.

## Scope

This is the plan's headline sentence and no section delivers it. `plan.md`
promises that "a person should be able to run the same work under two different
agent team designs, see what each cost and where each escalated, swap one
agent's system prompt for somebody else's, re-run, and know whether it helped."
Everything else in this project is a precondition for that sentence.

A topology is already addressable: `config.json` binds each role to a cli, a
model and a difficulty, `consultant` is already a list of independent seats, and
the store records a run, its attempts and its spans. What is missing is a way to
name two of those arrangements, run the same project under each, and put the
two records side by side.

In scope:

- A named topology: a config overlay that renames nothing and replaces only role
  bindings and seat counts. Stored as data, not as an edited `config.json`.
- `pm-flow compare <topology-a> <topology-b>` — run the same project under each
  and emit one table.
- The metrics `plan.md` already committed to, because they are the ones where
  the effect size is large and measurement is not a matter of opinion: cost,
  tokens, cycles-to-done, rescue rate, abandonment rate, escalation depth.
- The statistical caveat printed with the result, not buried in a document.
  Separating a real quality difference from model noise takes on the order of
  ten thousand trajectories per arm; three runs cannot do it, and a user who is
  not told that will over-read the table.

Out of scope: quality scoring, Inspect AI integration, any hosted comparison
service, and any claim that a two-run difference is significant.

## Priority

- must-have. Without it the project's stated objective is undelivered and pm-flow
  is one more orchestrator in a field of 150.

## Owned paths

- To be set against the packaged layout once `packaging` lands. Expect
  `src/pm_flow/**` for the comparison and the topology model, and the store
  schema for whatever the comparison needs to read.

## Dependencies

- packaging
- store-ledger

## Acceptance

- Two topologies are defined without editing a shared `config.json`, and running
  one does not mutate the other's definition.
- The same project runs under both and the store holds two distinguishable runs.
- One command emits a table of cost, tokens, cycles-to-done, rescue rate,
  abandonment rate and escalation depth for both.
- The output states, in the output itself, what a difference of this sample size
  can and cannot support.
- A topology names no model that the machine does not have without failing
  clearly, before any dispatch is made.

## Rejection conditions

- A topology is expressed by editing `config.json` in place.
- The comparison reports a quality verdict, or any wording that implies one
  arrangement is better when the evidence is a handful of runs.
- Comparison requires a hosted service or a backend the user did not start.
- The metrics are computed from anything other than the recorded run.
