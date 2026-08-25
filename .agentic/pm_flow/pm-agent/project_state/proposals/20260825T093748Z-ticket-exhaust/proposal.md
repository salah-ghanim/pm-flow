## Assessment

The request is for a one-way "exhaust" of section state into GitHub Issues — files stay the truth, the tracker is a view — plus letting `init-section` take an issue reference as a request, with `gh` isolated from role prompts. The owner's design reasoning is sound (idempotent sync, CCPM as the cautionary example, tracker never blocks a tick), but the question this phase settles is whether the plan needs it.

Probes run:

- Read `project_state/plan.md`, `project_state/sections.md`, and the request.
- `ls .agentic/pm_flow/pm-agent/sections` — 18 workspaces, none for tracker sync, none named `boundary-schema`.
- `ls -R project_state/proposals` — the `20260825T093424Z-boundary-schema` proposal has a response but no `decision.txt`, no `proposal.md`, no briefs; `grep "## Decision"` on its `proposal.response.json` shows the officer answered `CUT`, yet the registry has no `boundary-schema` row and no section workspace or run exists. It is not a live section as of this dispatch.
- `grep -n "json\|export\|boundary\|ticket" template/.agentic/pm_flow/pm_flow.sh` — the only export is `trace export` (OTLP spans); there is no structured section-state export and no ticket, issue, or `gh` integration anywhere in the template.

What it would serve: nothing in the plan. The objective sentence is about running the same work under two team designs and measuring the difference. None of the seven completion criteria under "What must be true when this is done" mentions ticket systems, trackers, or any human-facing view beyond the trace backends; the plan even classes "a board to watch them" as the commodity the field already has, not this product's differentiator. The cancelled sections set the precedent: `repo-hooks` and `a2a-binding` were both cut for advancing no plan bullet. Nothing already covers the request — the decline rests on plan need, not overlap.

Two supporting facts, not the primary ground:

- The request's hard dependency — boundary-schema's validated JSON export, which the owner fixed as the only legal input (no markdown parsing) — is not a live section in the registry, so a cut today could not legally declare the one dependency without which its acceptance cannot pass.
- The owner priced it correctly at nice-to-have, which concedes no completion criterion needs it.

## Section: ticket-exhaust

Not applicable.

## Decision

DECLINE — no plan bullet serves it: neither the objective sentence nor any "What must be true when this is done" criterion names tracker visibility, so "What must be true" would have to gain a criterion (section state visible in an external tracker) through a visible plan change before this can be a section of this product; additionally its fixed input, `boundary-schema`'s validated JSON export, is not yet a live section in the registry. Re-propose once the plan says so and `boundary-schema` is registered.
