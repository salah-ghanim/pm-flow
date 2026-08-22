# persona-packs handoff

## Outcome

- Cycle 004 is accepted and committed. A user can install, inspect and re-add a
  local persona pack; edited prompt content creates a new attributable version.

## Decisions

- The pack format is a JSON index plus indexed Markdown persona files.
- Pack validation rejects machine-local CLI, model, binding, access and tool
  fields, path escapes, symlink escapes and non-Markdown indexed files before
  opening the store.
- Identical standalone personas are adopted in place, retaining their IDs and
  measurement references while gaining pack provenance.
- A second pack claiming an identical installed persona is rejected atomically;
  the original publisher and measurement references remain unchanged.
- Focused local, adoption and collision checks pass, their targeted mutations
  fail, and the hermetic suite passes.

## Interfaces

- `catalog.py --db <store> persona add <local-path>` installs a validated pack.
- `catalog.py --db <store> persona list` shows the newest version of each key
  with its layer, pack, manifest version, content hash and source.

## Risks

- A pack with one cross-pack collision is rejected whole. This preserves
  attribution but means its otherwise distinct personas are not installed.
- Git acquisition must not persist a temporary clone path as provenance.

## What is unproven

- Git URL acquisition, update from source while retaining old attributable
  versions, and layer-specific seat swapping remain unimplemented.

## Next action

- Add git-URL installation using the real Git CLI, retaining the original URL
  and installed commit while reusing the accepted pack validation path.
