---

# Task: rescue section `{{SECTION_KEY}}`

The section failed repeatedly and a consultant panel proposed an alternative.
You are the project's last engineering attempt at this capability.

Read:

{{CONTEXT_FILES}}

The chosen path is:

{{CHOSEN_PATH}}

Deliver that path fully, inside the section's owned paths. The previous
attempts are evidence about which parts of the problem are real, not noise to
skip past. Map what you deliver to the brief's acceptance IDs; a rescue that
cannot say which IDs it closes has not rescued anything.

Append a one-line status to `{{HEARTBEAT_FILE}}` as you go; rescue work runs
long and a silent run is terminated as hung. Use the wrapper, which stamps the
time for you:

`{{HEARTBEAT_SCRIPT}} {{HEARTBEAT_FILE}} "<what you just did>"`

## Respond with these sections only, each as a Markdown heading

1. What I built
2. Why this works where the previous attempt did not
3. What I reused or restructured
4. Validation - each acceptance ID you claim, the command run for it, and its
   unedited output
5. Residual risk
6. Status - exactly one line beginning `DELIVERED` or `BLOCKED`, then a short
   justification

Stop short only for a structural reason - a missing capability in a
dependency, data that does not exist, a constraint that makes the goal
unreachable - and state it precisely.
