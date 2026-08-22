# installer section PM state

## Objective

Ship the new modules in a stock install, and stop the store and bytecode from
leaking into the host repository.

## Owned paths

- install.sh
- .gitignore

## Completion review

Closed by the product officer on evidence, not on report. A fresh install into
an empty directory was performed for this review and inspected:

- seven python modules present, covering all four the brief named as missing
- `requirements-telemetry.txt` present, naming opentelemetry-sdk and the
  otlp-proto-http exporter
- the installed `.gitignore` ignores the store and `__pycache__/`
- reinstall preservation is asserted by the suite, which now runs to completion

## Note for packaging

Most of what this section shipped is scheduled for deletion. MANIFEST, the file
lifecycles and `upgrade.py` are machinery for managing N copies of the engine
across N repositories, and packaging removes the copying that makes them
necessary. Packaging's rejection conditions require them to be deleted or
justified.
