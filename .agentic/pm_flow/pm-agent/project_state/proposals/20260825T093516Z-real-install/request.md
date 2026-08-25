Owner request. Priority: must-have. Several done sections honestly admit in
their handoffs that nothing was ever proven against a real install: store-ledger
cost parity unproven outside fixtures, packaging exercised only in test
repositories, no real project has run the packaged engine end to end. The one
real install exists at `/Users/salah/code/personal/golden-grid` (about ten
workspaces, predates the packaging split, still carries a copied engine — the
migration path `install.sh` claims to handle).

Wanted outcome: golden-grid runs the packaged engine. Concretely: the current
`pm-flow` wheel installed into golden-grid's venv, `install.sh` run against it
performing the copied-engine migration it advertises (project data preserved,
copied engine removed, recorded rename), and one real section cycle driven
there by `pm-flow run` or `run-detach` — a real dispatch, a real verdict, a
real driver commit in that repository. Then the parity checks the handoffs
deferred: `cost.py total` against that install's legacy `cost_ledger.tsv`
import, and `pm-flow trace status` / an export showing that install's spans.

This section's code changes live in THIS repository (installer, migration,
docs, and a test that reproduces golden-grid's pre-migration layout as a
fixture); golden-grid itself is evidence ground, not owned territory. Where a
dispatch cannot reach the external path from its sandbox, the acceptance
criterion should say what observation settles it and the driver's extra-dir
mechanism or an operator-run probe provides it — do not water the criterion
down to "the fixture passes". Suggested owned paths: `install.sh`, a new
fixture + test suite under `tests/`, and documentation. Dependencies: none
hard; boundary-schema and outcome-record make the evidence richer but must not
block this.
