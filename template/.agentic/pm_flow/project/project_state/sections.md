# Project sections

This is the bounded portfolio view for the root project coordinator.

Run `./.agentic/pm_flow/pm_flow.sh list-sections` after creating or updating a
section. The command derives this file from per-section state.

The root coordinator reads this file and the linked section handoffs. It does
not load section transcripts, section PM conversations, or developer
conversations into the root context.

| Section | Status | Summary | PM handoff | Run | Updated (UTC) |
| --- | --- | --- | --- | --- | --- |
| _none_ | — | Create a section with `init-section`. | — | — | — |

Allowed statuses: `planned`, `active`, `blocked`, `done`, `cancelled`.

Each handoff is capped at 500 words and 8192 bytes and contains only outcomes,
decisions, interfaces, risks, and the next action. `done` and `cancelled` are
terminal for PM review preparation; publish an `active` or `planned` handoff to
reopen a section deliberately.
