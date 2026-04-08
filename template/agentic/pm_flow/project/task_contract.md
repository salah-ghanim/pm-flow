# {{PROJECT_NAME}} Task Contract

Primary mission:

- {{PRIMARY_MISSION}}
- keep going until the current task is either validated as complete or explicitly killed with evidence

What counts as progress:

- a concrete change or decision that directly advances the task goal
- a validation result that proves a candidate should be kept or rejected
- a negative result that kills a weak path quickly and with evidence
- a process fix only when it is strictly required to unblock the same task cycle

What does not count as progress by itself:

- documentation only
- generic cleanup with no relation to the task objective
- workflow polish not used in the same cycle
- observations without a decision or validation outcome
- side quests that are not tied to the current mission

Acceptance rule for any new candidate:

1. identify the exact source of the idea or requirement
2. state the one-sentence hypothesis or expected gain
3. implement the smallest version needed to test it
4. validate against the current baseline or explicit success criteria
5. keep it only if observed results support the hypothesis

Anti-drift rules:

- do not expand scope without stating why the expansion is necessary now
- do not count setup work as success unless it directly unlocks the same task cycle
- do not continue a failed path after a clean negative result unless Claude PM explicitly justifies one more check
- do not silently replace the task objective with a different one
- do not assume network or DNS problems before considering sandbox or wrapper issues
- prefer stable approved wrappers over ad hoc command shapes
- Claude PM must be called from the top shell, never from child scripts
- first Claude PM call should use plain `claude -p --output-format json`; later calls should use `--resume` with the returned `session_id`
- the prepared `command.txt` is the source of truth for Claude invocation shape

Drift review process:

- every proposed step must answer:
  - is it aligned with the current task objective
  - what direct outcome is expected
  - what will be validated
  - what would cause the path to be rejected
- every Claude PM review must explicitly include:
  - whether drift is happening
  - what the main risk is
  - whether the next step is approved, approved with changes, or rejected
- every completion report must include:
  - expected versus observed
  - whether drift happened
  - what contract change should prevent the same drift next time

Permissions and execution rules:

- prefer repo-local wrappers before ad hoc commands
- if repeated permissions are needed for the same family of commands, stabilize the command shape with a wrapper
- when sandboxed execution fails on networked work, retry through the approved outside-sandbox wrapper path before diagnosing infrastructure

Current baseline or reference:

- {{CURRENT_BASELINE}}
