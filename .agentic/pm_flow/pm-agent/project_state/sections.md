# Project sections

This is a generated, bounded portfolio view for the root project coordinator.
Per-section files are authoritative; run `pm-flow list-sections` to refresh this index.
The root coordinator should read this file and the linked handoffs, not section transcripts.

| Section | Priority | Status | Summary | PM handoff | Run | Updated (UTC) |
| --- | --- | --- | --- | --- | --- | --- |
| a2a-binding | nice-to-have | cancelled | Cut by a portfolio review: no plan bullet names A2A (the binding criterion is ACP); waits on an unstarted section; its own stated risk is an unauthenticated endpoint that spends budget. Product no ... | [handoff](../sections/a2a-binding/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T222651Z-a2a-binding-704e9e0c` | 2026-08-23T13:50:53Z |
| agent-bindings | must-have | done | Section completed and validated across 006 cycle(s) | [handoff](../sections/agent-bindings/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T211931Z-agent-bindings-e34faa2d` | 2026-08-24T11:29:06Z |
| agents-md | nice-to-have | done | Section completed and validated across 003 cycle(s) | [handoff](../sections/agents-md/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T153706Z-agents-md-79b36bec` | 2026-08-23T08:48:34Z |
| artifact-quality | nice-to-have | done | Section completed and validated across 005 cycle(s) | [handoff](../sections/artifact-quality/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260823T141454Z-artifact-quality-f90f5dc7` | 2026-08-24T22:35:00Z |
| codex-usage | must-have | done | Section completed and validated across 008 cycle(s) | [handoff](../sections/codex-usage/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T153704Z-codex-usage-5f13a050` | 2026-08-23T19:37:09Z |
| green-suite | must-have | done | Suite runs to completion and exits zero; the guard was never broken, it was never called. | [handoff](../sections/green-suite/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T153703Z-green-suite-51f4bdcf` | 2026-08-22T17:21:33Z |
| installer | must-have | done | A stock install lands every module, ignores the store and bytecode, and preserves state on reinstall. | [handoff](../sections/installer/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T153705Z-installer-3c68b20d` | 2026-08-22T18:14:05Z |
| otel-semconv | must-have | active | Reopened by portfolio review 007: tests/otel_semconv_test.sh exits 1 on main (secondary span reports v1.37.0 against the test's v1.36.0 pin); acceptance unchanged. | [handoff](../sections/otel-semconv/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T222645Z-otel-semconv-ccea9f8c` | 2026-08-24T23:52:18Z |
| packaging | must-have | done | Installed-package boundary complete; all A1-A8 evidence is on main. | [handoff](../sections/packaging/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T162623Z-packaging-8802916e` | 2026-08-23T12:35:30Z |
| persona-cards | nice-to-have | done | Section completed and validated across 005 cycle(s) | [handoff](../sections/persona-cards/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T222656Z-persona-cards-77d91306` | 2026-08-24T23:31:54Z |
| persona-packs | must-have | done | Section completed and validated across 012 cycle(s) | [handoff](../sections/persona-packs/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T153706Z-persona-packs-538690db` | 2026-08-23T18:05:37Z |
| repo-hooks | nice-to-have | cancelled | Cut by a portfolio review: advances no plan bullet; the driver already writes Conventional Commits; its failure mode (hook refusing the driver's subject) stops the flow. Product no longer guarantee... | [handoff](../sections/repo-hooks/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260823T112028Z-repo-hooks-c5acd437` | 2026-08-23T13:50:53Z |
| run-detach | nice-to-have | active | Reopened by portfolio review 007: install.sh joined Owned paths for three registry entries; T1a is assignable and packaged_layout_test.sh is the gate. | [handoff](../sections/run-detach/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260824T002233Z-run-detach-e8ce00e3` | 2026-08-24T23:52:17Z |
| store-ledger | must-have | done | Section completed and validated across 007 cycle(s) | [handoff](../sections/store-ledger/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T153705Z-store-ledger-40f91f03` | 2026-08-24T08:33:28Z |
| topology-compare | must-have | done | Section completed and validated across 007 cycle(s) | [handoff](../sections/topology-compare/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T211919Z-topology-compare-d633e224` | 2026-08-24T19:10:05Z |
| trace-commands | must-have | done | Section completed and validated across 004 cycle(s) | [handoff](../sections/trace-commands/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T153704Z-trace-commands-f5a2c0a5` | 2026-08-24T10:32:16Z |
| worktree-isolation | must-have | done | Each section dispatches in its own git worktree; accepted work merges back, rejected work never reaches the main tree. | [handoff](../sections/worktree-isolation/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T153705Z-worktree-isolation-211e7a74` | 2026-08-22T18:12:36Z |

Allowed statuses: `planned`, `active`, `blocked`, `done`, `cancelled`.
Priority is `must-have` or `nice-to-have`; a section created before priorities existed reads as `must-have`.
A handoff is capped at 500 words and 8192 bytes and carries only outcomes, decisions, interfaces, risks, what is unproven, and the next action.
A handoff is a claim. Check the artifact it names before acting on it.
