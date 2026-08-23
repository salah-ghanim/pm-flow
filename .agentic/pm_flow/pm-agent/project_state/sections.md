# Project sections

This is a generated, bounded portfolio view for the root project coordinator.
Per-section files are authoritative; run `pm-flow list-sections` to refresh this index.
The root coordinator should read this file and the linked handoffs, not section transcripts.

| Section | Priority | Status | Summary | PM handoff | Run | Updated (UTC) |
| --- | --- | --- | --- | --- | --- | --- |
| a2a-binding | nice-to-have | cancelled | Cut by a portfolio review: no plan bullet names A2A (the binding criterion is ACP); waits on an unstarted section; its own stated risk is an unauthenticated endpoint that spends budget. Product no ... | [handoff](../sections/a2a-binding/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T222651Z-a2a-binding-704e9e0c` | 2026-08-23T13:50:53Z |
| agent-bindings | must-have | planned | Not started; T1 is the ACP client against a protocol-faithful test agent. | [handoff](../sections/agent-bindings/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T211931Z-agent-bindings-e34faa2d` | 2026-08-23T12:39:02Z |
| agents-md | nice-to-have | done | Section completed and validated across 003 cycle(s) | [handoff](../sections/agents-md/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T153706Z-agents-md-79b36bec` | 2026-08-23T08:48:34Z |
| artifact-quality | nice-to-have | planned | Not started; T1 is the rubric and scorer. A separate process; scores only in project metadata. | [handoff](../sections/artifact-quality/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260823T141454Z-artifact-quality-f90f5dc7` | 2026-08-23T14:14:54Z |
| codex-usage | must-have | active | Engine work on main; T3 tracks the replay test, then complete. | [handoff](../sections/codex-usage/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T153704Z-codex-usage-5f13a050` | 2026-08-23T13:33:00Z |
| green-suite | must-have | done | Suite runs to completion and exits zero; the guard was never broken, it was never called. | [handoff](../sections/green-suite/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T153703Z-green-suite-51f4bdcf` | 2026-08-22T17:21:33Z |
| installer | must-have | done | A stock install lands every module, ignores the store and bytecode, and preserves state on reinstall. | [handoff](../sections/installer/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T153705Z-installer-3c68b20d` | 2026-08-22T18:14:05Z |
| otel-semconv | must-have | planned | Not started; T1 pins the convention revision in one module. | [handoff](../sections/otel-semconv/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T222645Z-otel-semconv-ccea9f8c` | 2026-08-23T12:39:02Z |
| packaging | must-have | done | Installed-package boundary complete; all A1-A8 evidence is on main. | [handoff](../sections/packaging/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T162623Z-packaging-8802916e` | 2026-08-23T12:35:30Z |
| persona-cards | nice-to-have | planned | Not started; waits on persona-packs. | [handoff](../sections/persona-cards/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T222656Z-persona-cards-77d91306` | 2026-08-23T12:39:02Z |
| persona-packs | must-have | active | T1–T5 done on main; the next scope call declares COMPLETE. | [handoff](../sections/persona-packs/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T153706Z-persona-packs-538690db` | 2026-08-23T12:39:02Z |
| repo-hooks | nice-to-have | cancelled | Cut by a portfolio review: advances no plan bullet; the driver already writes Conventional Commits; its failure mode (hook refusing the driver's subject) stops the flow. Product no longer guarantee... | [handoff](../sections/repo-hooks/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260823T112028Z-repo-hooks-c5acd437` | 2026-08-23T13:50:53Z |
| store-ledger | must-have | planned | Not started; T1 is the idempotent legacy import. | [handoff](../sections/store-ledger/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T153705Z-store-ledger-40f91f03` | 2026-08-23T12:39:02Z |
| topology-compare | must-have | planned | Not started; waits on store-ledger for cost totals. | [handoff](../sections/topology-compare/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T211919Z-topology-compare-d633e224` | 2026-08-23T12:39:02Z |
| trace-commands | must-have | planned | Not started; T1 checkpoints export on acknowledgement. | [handoff](../sections/trace-commands/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T153704Z-trace-commands-f5a2c0a5` | 2026-08-23T12:36:34Z |
| worktree-isolation | must-have | done | Each section dispatches in its own git worktree; accepted work merges back, rejected work never reaches the main tree. | [handoff](../sections/worktree-isolation/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T153705Z-worktree-isolation-211e7a74` | 2026-08-22T18:12:36Z |

Allowed statuses: `planned`, `active`, `blocked`, `done`, `cancelled`.
Priority is `must-have` or `nice-to-have`; a section created before priorities existed reads as `must-have`.
A handoff is capped at 500 words and 8192 bytes and carries only outcomes, decisions, interfaces, risks, what is unproven, and the next action.
A handoff is a claim. Check the artifact it names before acting on it.
