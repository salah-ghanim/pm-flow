# Project sections

This is a generated, bounded portfolio view for the root project coordinator.
Per-section files are authoritative; run `pm_flow.sh list-sections` to refresh this index.
The root coordinator should read this file and the linked handoffs, not section transcripts.

| Section | Priority | Status | Summary | PM handoff | Run | Updated (UTC) |
| --- | --- | --- | --- | --- | --- | --- |
| agents-md | nice-to-have | active | Cycle 002; last action review. | [handoff](../sections/agents-md/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T153706Z-agents-md-79b36bec` | 2026-08-22T20:49:21Z |
| codex-usage | must-have | done | Section completed and validated across 003 cycle(s) | [handoff](../sections/codex-usage/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T153704Z-codex-usage-5f13a050` | 2026-08-22T20:53:30Z |
| green-suite | must-have | done | Suite runs to completion and exits zero; the guard was never broken, it was never called. | [handoff](../sections/green-suite/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T153703Z-green-suite-51f4bdcf` | 2026-08-22T17:21:33Z |
| installer | must-have | done | A stock install lands every module, ignores the store and bytecode, and preserves state on reinstall. | [handoff](../sections/installer/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T153705Z-installer-3c68b20d` | 2026-08-22T18:14:05Z |
| packaging | must-have | active | Cycle 003; last action review. | [handoff](../sections/packaging/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T162623Z-packaging-8802916e` | 2026-08-22T20:51:42Z |
| persona-packs | must-have | active | Cycle 004; last action develop. | [handoff](../sections/persona-packs/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T153706Z-persona-packs-538690db` | 2026-08-22T20:47:37Z |
| store-ledger | must-have | planned | Reopened: its paths are disjoint from packaging and do not move. | [handoff](../sections/store-ledger/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T153705Z-store-ledger-40f91f03` | 2026-08-22T18:40:41Z |
| trace-commands | must-have | blocked | Blocked: scoped against a layout packaging replaces; re-cut once packaging lands. | [handoff](../sections/trace-commands/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T153704Z-trace-commands-f5a2c0a5` | 2026-08-22T18:24:54Z |
| worktree-isolation | must-have | done | Each section dispatches in its own git worktree; accepted work merges back, rejected work never reaches the main tree. | [handoff](../sections/worktree-isolation/handoff.md) | `.agentic/pm_flow/pm-agent/runs/20260822T153705Z-worktree-isolation-211e7a74` | 2026-08-22T18:12:36Z |

Allowed statuses: `planned`, `active`, `blocked`, `done`, `cancelled`.
Priority is `must-have` or `nice-to-have`; a section created before priorities existed reads as `must-have`.
A handoff is capped at 500 words and 8192 bytes and carries only outcomes, decisions, interfaces, risks, what is unproven, and the next action.
A handoff is a claim. Check the artifact it names before acting on it.
