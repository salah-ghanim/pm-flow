### Objective
Make the engine an installed Python package with a per-project version, so that
upgrading is `pip install -U` and not a file-copying protocol we maintain
ourselves. Then move the engine into it, and delete the machinery that existed
only to manage the copies.

### Scope
Everything pm-flow currently does about versioning exists for one reason: the
engine is *copied* into every repository that uses it. MANIFEST, the three file
lifecycles, drift detection, the refusal to overwrite an edited file, and
upgrade.py are all machinery for managing N copies of driver.zsh scattered across
N repositories. None of it is needed if the engine is never copied.

Python already solves this, and this project already assumes it. `agent_exec.sh`
activates `$PROJECT_ROOT/.venv` if one exists, and the telemetry exporter already
expects the OpenTelemetry SDK to be installable. A virtual environment per
repository is exactly the per-project version pinning MANIFEST was hand-rolling,
and it comes with resolution, upgrade and uninstall for free.

The split to build:

- **engine** - an installed package. The shell scripts, the python modules, and
  the *default* personas, tasks and domains. Never edited in place, never copied
  into a repository, so it can never conflict.
- **project data** - what stays in `.agentic/`: `config.json`, persona overrides,
  project state, sections, and the store.

Customisation must be by overlay, never by editing. This is already built: the
catalogue stacks a base persona and a domain overlay onto one seat through
`seat_personas`. A repository-local persona becomes one more layer over the
packaged default, which is what removes the need to merge anything on upgrade.

A console entry point (`pm-flow`) locates the packaged engine through
`importlib.resources` and runs it against the repository it was invoked in.

**What is already built.** `pyproject.toml`, `src/pm_flow/paths.py` and
`src/pm_flow/cli.py` exist and a wheel has been built and run from a clean venv
with no checkout present. `paths.py` holds the layout for both languages, with
`$PROJECT$`-style macros so persisted paths survive a move, and it already
distinguishes `engine_root` from `repo_root`, `flow_dir` and `project_dir`. The
remaining work is the move itself and the deletions that follow it.

**What changed since this brief was first written.** It was originally scoped to
`pyproject.toml` and `src/**` only, because a wider scope overlapped three
sections that were themselves scoped against the layout this section replaces.
That refusal was correct at the time. It is no longer: `installer` is closed,
and the sections that overlapped are blocked pending a re-cut *against this
section's result*, which cannot be written until this lands. Packaging is not a
peer of those sections; it is the re-baselining they will be re-cut against.

### Priority
- must-have. Every other section is cheaper after this and some become
  unnecessary; doing them first means doing them twice.

### Owned paths
- pyproject.toml
- src/pm_flow/cli.py
- src/pm_flow/paths.py
- src/pm_flow/__init__.py
- install.sh
- MANIFEST
- template/.agentic/pm_flow/pm_flow.sh
- template/.agentic/pm_flow/upgrade.py
- template/.agentic/pm_flow/.gitignore
- tests/pm_flow_test.sh
- tests/packaged_layout_test.sh
- tests/fixtures/stub_*.zsh
- .gitignore
- `tools/manifest.py`
- `README.md`, limited to the passages that describe MANIFEST, the manifest
  tool, and the copy-version lifecycle.

`src/**` and `tests/**` were both narrowed to the files this section actually
edits. Owning a whole directory is a claim on every file anyone might ever add
to it, and it blocked `topology-compare` from being cut at all - a section for
the plan's headline promise, refused because of a wildcard rather than a
conflict. The registry was right to refuse; the scope was wrong.

Narrowed from `template/**` and `README.md`. Owning all of `template/` was
over-claiming: packaging does not move the engine's source files - the wheel
force-includes `template/.agentic/pm_flow` as package data, so `agent_exec.sh`,
`cost.py`, `catalog.py` and the personas stay exactly where they are. What
packaging actually changes is how a *host repository* gets them, which is
install.sh, MANIFEST, the entry point, and the path resolution in pm_flow.sh.
Claiming the rest would have blocked three sections that touch none of it.
`README.md` belongs to agents-md, which has to describe the finished layout
anyway.

**Both of those last two were added after cycle 005.** That cycle deleted
`MANIFEST` as this brief asks, and immediately exposed a deadlock: a rejection
condition below says the file-lifecycle machinery must be deleted or justified,
`tools/manifest.py` is that machinery, and it sat outside this section's
allowlist so no assignment here could remove it. A section cannot be held to a
condition it has no path to satisfy. `tools/` is owned by nobody, and `README.md`
was released when `agents-md` closed.

Taking `README.md` is not a licence to rewrite it. `agents-md` closed on a
contract that section is entitled to keep: `AGENTS.md` is the instructions file,
it is rendered before `CLAUDE.md`, the managed markers and the one-time
`*.pre-pm-flow.md` backups are preserved, and pre-existing content survives.
Change the manifest passages and leave the rest alone.

### Dependencies
- green-suite
- worktree-isolation

### Acceptance
- `pip install pm-flow` (or `uv tool install`) into a project venv provides a
  working `pm-flow` command with no file copying.
- Two repositories can pin different pm-flow versions and both run correctly.
- A repository holds only project data: config, overrides, state, store. No
  copy of driver.zsh, agent_exec.sh or the default personas.
- A repository-local persona overlays the packaged one without editing it, and
  the record says which layers produced a result.
- Upgrading the package changes no file inside `.agentic/`.
- The suite runs to completion against the packaged layout.
- An existing `.agentic/pm_flow` install migrates: project data is kept, the
  copied engine is removed, and the run afterwards behaves identically.
- A checkout does not describe machinery it no longer has: with `MANIFEST` gone,
  no tool regenerates it and no documentation tells a reader to run one.

### Rejection conditions
- The engine is still copied into the repository under any name.
- A user is expected to edit a packaged file to customise a persona.
- The migration discards project state, run history, or a recorded domain.
- MANIFEST, upgrade.py or the file-lifecycle machinery survive without being
  either deleted or justified in the handoff. They exist to solve the problem
  this section removes.
- The suite is weakened, skipped, or made to exit zero without running to
  completion. It is the only mechanical evidence any of the above is true.
