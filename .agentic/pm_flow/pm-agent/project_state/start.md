# Starting pm-flow self-hosting

1. Describe what you want built in
   `.agentic/pm_flow/pm-agent/project_state/plan.md`. This is the only
   thing the product officer has to work from, so state the mission, the
   constraints that apply across sections, and what "finished" means.

2. Check which agents will do the work:

   ```bash
   ./.agentic/pm_flow/pm_flow.sh config
   ```

   Roles bind to a CLI, a model, and a difficulty in `.agentic/pm_flow/config.json`.
   Adjust them before a long run rather than during one.

3. Start:

   ```bash
   ./.agentic/pm_flow/pm_flow.sh run
   ```

With no sections yet, the first action is decomposition: the product officer
cuts the plan into independently owned sections and the same run begins driving
them.

To watch rather than commit, take one step at a time:

```bash
./.agentic/pm_flow/pm_flow.sh status   # what each section will do next
./.agentic/pm_flow/pm_flow.sh tick     # perform exactly one transition
```

`run --max-ticks <n>` bounds a run. It is a spend control as much as a time
control: every tick is at least one model call.
