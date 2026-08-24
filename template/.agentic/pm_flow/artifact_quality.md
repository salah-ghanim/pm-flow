# Durable artifact quality rubric

This rubric defines deterministic findings for the durable project and section
artifacts. It contains no observations or scores from a particular project.

## Word budgets

The ranker reads this table at runtime. A file over its budget receives one
`length` finding for the number of excess words.

| File | Word budget |
|---|---:|
| `plan.md` | 1200 |
| `brief.md` | 1400 |
| `workplan.md` | 1800 |
| `state.md` | 900 |
| `handoff.md` | 500 |

## Length

`length` means the file contains more words than the budget for its file kind.
The finding states the observed count, budget, and excess. The handoff budget
matches the existing 500-word completion cap.

## Echo

`echo` means the same normalized paragraph of at least twelve words occurs in
two durable files belonging to one section, or in the project plan and a file
from a section. Repetition between two different sections is not echo. Paragraph
normalization and the minimum size come from `prompt_quality.py`.

## Shape

`shape` means a durable file is missing headings required by the engine's
artifact contract. Required headings may appear at any Markdown heading depth
from one through six. A legacy brief requires Objective, Scope, Priority, Owned
paths, Dependencies, Acceptance, and Rejection conditions. A brief that has a
Deliverables heading uses the expanded contract and also requires Current
baseline, Deliverables, User-visible scenarios, Interfaces produced, Interfaces
consumed, Non-goals, Constraints and fixed decisions, and Open questions.

The project plan, workplan, state, and handoff use the headings in their engine
templates. Shape also requires every `A<n>` identifier present in a brief to
appear in the first column of that section workplan's Acceptance coverage table;
one first-column cell may cover multiple identifiers. The resulting coverage
finding belongs to the brief.

## Boundaries

`boundaries` means a section artifact contains a path-like inline-code reference
outside the paths declared by its brief. A path is declared when it appears in
inline code anywhere in that brief, not only under Owned paths or Dependencies.
The section's four sibling durable filenames and dependency handoffs declared by
the brief are also allowed references. An inline-code reference to another live
section key is allowed only when that key is declared under Dependencies. The
project plan has portfolio scope and is not checked against a section boundary.

## Stale

`stale` means a state file repeats a normalized paragraph from its workplan's
Design summary, or a project plan begins a line with `At review`. State records
current evidence and the plan records current portfolio truth; review narration
belongs in history rather than either durable artifact.
