# Prompt quality and end-to-end QA

The unit under test is the exact generated prompt, not only the role and task
templates. Every dispatch writes `<phase>_prompt.manifest.json` beside its
prompt before a model is called. The manifest records role, phase, commit owner,
prompt words and bytes, task-to-prompt ratio, duplicate ratio, context file
count and size, and all findings.

## Release gates

1. Static unit gate on every change:

   ```bash
   zsh tests/prompt_quality_test.sh
   ```

   It fails unresolved placeholders, false history claims, commit-owner
   contradictions, model-family assumptions, leaked incident stories, missing
   phase facts, and excessive copied prose in strict mode - first on fixtures
   that prove each rule, then on every prompt the stub suites compose from the
   shipped templates, audited in strict mode. A template edit that pushes a
   composed prompt over budget or into a contradiction fails here, not in a
   live dispatch.

2. Deterministic state-machine gate on every change:

   ```bash
   zsh template/.agentic/pm_flow/tests/run.zsh
   ```

   Stub roles run scope → develop → review → complete, recovery, governance,
   and on-demand paths without model spend. Assertions cover bounded history,
   workplan-to-assignment mapping, response parsing, and prompt manifests.

3. Packaged integration gate before release:

   ```bash
   zsh tests/pm_flow_test.sh
   zsh tests/packaged_layout_test.sh
   ```

   These exercise the installed wheel, project/engine separation, persona and
   task layer order, and deterministic dispatches.

4. Live canary nightly or before a prompt release:

   ```bash
   PM_FLOW_PROMPT_AUDIT_STRICT=1 pm-flow --project <canary> run --max-ticks 8
   pm-flow --project <canary> prompt-audit --all --strict
   ```

   Use a small disposable project with one implementation task and one real
   user-visible end-to-end check. A stub can validate routing but cannot close a
   criterion involving an external CLI or service.

## What to inspect in a canary

- No error or warning findings in manifests created by the canary.
- Scope assignments carry one real `T<number>` from `workplan.md` and name
  implementation paths, existing components, acceptance IDs, and commands. The
  workplan no longer carries the scaffold marker.
- The task portion is at least 35% of prompt words; context is no more than
  eight files or roughly 9,000 words; phase word budgets stay green.
- Responses do not copy prompt policy back as their main content. The standing
  section should be mostly task facts and evidence.
- Every brief acceptance ID maps to a workplan task and then to evidence in
  `state.md`; the final task proves the user-visible scenario.
- No `UNPARSED` verdicts, avoidable retries, out-of-scope writes, or completion
  based only on file existence or a stub.

Compare metrics and task/acceptance coverage with the previous accepted canary,
not the full prompt text. Full-text golden files make useful wording changes
look like regressions while missing semantic drift. If a model grades sampled
prompts, use it only as a secondary review for contradictions and task
specificity; deterministic contract failures remain the release gate.
