# Section facts, as the driver observes them

Derived from files on disk, not from anybody reporting. Treat every claim
in a handoff as unverified until a probe of your own says otherwise.

| section | priority | status | cycles | spent | waiting on |
| --- | --- | --- | --- | --- | --- |
| checkpoint-acceleration | nice-to-have | planned | 0 | 0.0000 | timelines-replay (cycles 0, planned)  |
| experiment-evaluation-consumers | must-have | planned | 0 | 0.0000 | experiment-execution (cycles 0, planned)  |
| experiment-execution | must-have | planned | 0 | 0.0000 | telemetry-continuity (cycles 0, planned)  |
| general-workflows | must-have | planned | 0 | 0.0000 | runtime-cutover (cycles 0, planned)  |
| golden-grid-rollout | must-have | planned | 0 | 0.0000 | telemetry-continuity (cycles 0, planned)  |
| legacy-migration | must-have | planned | 0 | 0.0000 | provenance-acceptance (cycles 0, planned) timelines-replay (cycles 0, planned)  |
| live-product-validation | must-have | planned | 0 | 0.0000 | experiment-evaluation-consumers (cycles 0, planned) general-workflows (cycles 0, planned) golden-grid-rollout (cycles 0, planned)  |
| provenance-acceptance | must-have | planned | 0 | 0.0000 | state-service (cycles 002, active)  |
| runtime-cutover | must-have | planned | 0 | 0.0000 | legacy-migration (cycles 0, planned)  |
| state-service | must-have | active | 002 | 22.4482 | nothing |
| telemetry-continuity | must-have | planned | 0 | 0.0000 | runtime-cutover (cycles 0, planned)  |
| timelines-replay | must-have | planned | 0 | 0.0000 | state-service (cycles 002, active)  |

