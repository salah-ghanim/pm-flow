# Project sections

This is a generated, bounded portfolio view for the root project coordinator.
Per-section files are authoritative; run `pm_flow.sh list-sections` to refresh this index.
The root coordinator should read this file and the linked handoffs, not section transcripts.

| Section | Priority | Status | Summary | PM handoff | Run | Updated (UTC) |
| --- | --- | --- | --- | --- | --- | --- |
| a2a-binding | nice-to-have | planned | Workplan defined; waiting for agent-bindings before the A2A contract task. | [handoff](../sections/a2a-binding/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T222651Z-a2a-binding-704e9e0c` | 2026-08-23T12:39:02Z |
| agent-bindings | must-have | planned | Workplan defined; ACP transport contract is the next task. | [handoff](../sections/agent-bindings/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T211931Z-agent-bindings-e34faa2d` | 2026-08-23T12:39:02Z |
| agents-md | nice-to-have | done | Section completed and validated across 003 cycle(s) | [handoff](../sections/agents-md/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T153706Z-agents-md-79b36bec` | 2026-08-23T08:48:34Z |
| codex-usage | must-have | active | Lifecycle works; next task is tracked replay, then host canary and cost verification. | [handoff](../sections/codex-usage/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T153704Z-codex-usage-5f13a050` | 2026-08-23T12:39:02Z |
| green-suite | must-have | done | Suite runs to completion and exits zero; the guard was never broken, it was never called. | [handoff](../sections/green-suite/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T153703Z-green-suite-51f4bdcf` | 2026-08-22T17:21:33Z |
| installer | must-have | done | A stock install lands every module, ignores the store and bytecode, and preserves state on reinstall. | [handoff](../sections/installer/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T153705Z-installer-3c68b20d` | 2026-08-22T18:14:05Z |
| otel-semconv | must-have | planned | Workplan defined; waits for codex-usage to release telemetry integration. | [handoff](../sections/otel-semconv/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T222645Z-otel-semconv-ccea9f8c` | 2026-08-23T12:39:02Z |
| packaging | must-have | done | Installed-package boundary complete; all A1-A8 evidence is on main. | [handoff](../sections/packaging/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T162623Z-packaging-8802916e` | 2026-08-23T12:35:30Z |
| persona-cards | nice-to-have | planned | Workplan defined; portable card schema is the next task. | [handoff](../sections/persona-cards/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T222656Z-persona-cards-77d91306` | 2026-08-23T12:39:02Z |
| persona-packs | must-have | active | All workplan tasks are GO through cycle 009; formal completion review remains. | [handoff](../sections/persona-packs/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T153706Z-persona-packs-538690db` | 2026-08-23T12:39:02Z |
| repo-hooks | nice-to-have | planned | Workplan defined; commit-message checker is the next task. | [handoff](../sections/repo-hooks/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260823T112028Z-repo-hooks-c5acd437` | 2026-08-23T12:39:02Z |
| store-ledger | must-have | planned | Workplan defined; idempotent legacy import is the next task. | [handoff](../sections/store-ledger/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T153705Z-store-ledger-40f91f03` | 2026-08-23T12:39:02Z |
| topology-compare | must-have | planned | Workplan defined; immutable topology documents are the next task. | [handoff](../sections/topology-compare/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T211919Z-topology-compare-d633e224` | 2026-08-23T12:39:02Z |
| trace-commands | must-have | planned | Rebaselined against packaged layout; waiting on otel-semconv. | [handoff](../sections/trace-commands/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T153704Z-trace-commands-f5a2c0a5` | 2026-08-23T12:36:34Z |
| worktree-isolation | must-have | done | Each section dispatches in its own git worktree; accepted work merges back, rejected work never reaches the main tree. | [handoff](../sections/worktree-isolation/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T153705Z-worktree-isolation-211e7a74` | 2026-08-22T18:12:36Z |

Allowed statuses: `planned`, `active`, `blocked`, `done`, `cancelled`.
Priority is `must-have` or `nice-to-have`; a section created before priorities existed reads as `must-have`.
A handoff is capped at 500 words and 8192 bytes and carries only outcomes, decisions, interfaces, risks, what is unproven, and the next action.
A handoff is a claim. Check the artifact it names before acting on it.
