### Objective
Make the engine an installed Python package with a per-project version, so that
upgrading is `pip install -U` and not a file-copying protocol we maintain
ourselves.

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

### Priority
- must-have. Every other section is cheaper after this and some become
  unnecessary; doing them first means doing them twice.

### Owned paths
- pyproject.toml
- src/**

Deliberately narrow, and the reason matters. The flow refused a wider scope: this
section's natural boundary overlaps `installer` on install.sh, `codex-usage` on
agent_exec.sh, and `agents-md` on CLAUDE.md. That refusal is correct and is the
most useful thing the section registry has said so far - packaging is not a peer
of those sections, it is a re-baselining that invalidates the layout they were
scoped against.

So build the package here, in new paths that collide with nothing. Moving the
existing engine into it is a second step, taken once those sections have landed
or been re-cut against the new layout, and coordinated through handoffs rather
than by widening this brief.

### Dependencies
- green-suite

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

### Rejection conditions
- The engine is still copied into the repository under any name.
- A user is expected to edit a packaged file to customise a persona.
- The migration discards project state, run history, or a recorded domain.
- MANIFEST, upgrade.py or the file-lifecycle machinery survive without being
  either deleted or justified in the handoff. They exist to solve the problem
  this section removes.
