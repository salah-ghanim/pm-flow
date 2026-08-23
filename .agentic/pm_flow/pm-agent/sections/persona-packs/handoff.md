## Outcome

- A1: one store, `persona add <dir>` then `persona add file://<same repo>`: the path row is adopted (same id, hash `701d0151…`), `source_url` → URL, `metadata.git_commit` = C1, `persona_packs` = (URL, C1), no checkout left. Local install `aaaf4b9`, Git cycle 006; chain proof cycle 011 at `2038254`.
- A2: `persona swap pm update-manager` changed exactly one `seat_personas` row (pm, base); domain/style rows, other seats, `bindings`, `tool_grants` identical; the next `tick` prompt carried the new wording in base<domain<style order. `dc38523`.
- A3: after commit C2, `persona update` exit 0 → `^ update-manager (new version; the previous one is kept)`; list shows H2/C2; v1 row field-identical; `persona_packs.ref` = C2. `e2eb511`.
- A4: readback from `attempts.persona_stack` printed `1 H1 1 C1` / `2 H2 15 C2`, both live rows; no-op `persona update update-crafts` → `=`, 15→15 rows. `e2eb511`.
- A5: `zsh tests/pm_flow_test.sh` ten `PASS:`, `suite_exit=0`; cycles 008–010 regressions exit 0; re-verified at `39a1fe4`, owned paths unchanged since `2038254`.

Mutants (update rewrites in place; Git add inserts, not adopts) fail the named assertions.

## Decisions

- A pack is one JSON index plus Markdown files; nothing from a pack executes at install (a pack `install.sh` marker never fires).
- A persona carrying a CLI, model or tool grant is refused and the pack rolls back; cross-pack collisions reject the whole install atomically.
- Versions are immutable rows keyed `(key, content_hash)`. Identical content from a richer source (path → Git URL) is adoption: same row id, provenance refreshed, `persona_packs.source_url`/`.ref` move to the URL and commit.
- `persona update` re-acquires from `persona_packs.source_url`; a failed pack is named, changes nothing, and the command exits 1 after trying the rest.
- A swap records a key in `topology_agents.overrides`, not a version id; the next dispatch after an update carries the new version.

## Interfaces

- `python3 <flow>/catalog.py --db <store> persona add <path|git-url>`, `persona list`, `persona update [pack-name]`, `persona swap <role> <persona-key> [--project K] [--topology T]`.
- `personas`: `source_url`, `source_path`, `content_hash`, `metadata.git_commit`; `persona_packs`: `source_url`, `ref`.
- `attempts.persona_stack` names each layer's key and `content_hash`, joinable to `personas` after any number of updates.
- Regression harness: `cycles/011/{acceptance.sh,assertions.py,regressions.sh}` — gitignored project data, not on `main`.

## Risks

- The brief's `pm-flow persona …` spelling is not delivered: `pm_flow.sh` has no `persona` subcommand and is outside owned paths. Running it shows the gap.
- Inherited `PM_FLOW_*` variables misroute a standalone catalog run; harnesses `env -u` them. A suite failure outside the harness reveals it.
- A manifest-only change (version/summary) is reported `~` and refreshes provenance in place, no new row; a caller expecting a row per version bump will not get one.

## What is unproven

- HTTPS/SSH Git transports: only `file://` was exercised (real Git CLI, same code path). Settled by `persona add` against a remote repository.

## Next action

Mark the section complete. `persona-cards` takes `catalog.py` next and should run `cycles/011/acceptance.sh` and `regressions.sh` around its first edit. A `persona` subcommand in `pm_flow.sh` is a one-line wrapper for whichever section owns that file.
