---

# Task: rescue this section

Section `{{SECTION_KEY}}` failed repeatedly and a consultant panel proposed an
alternative. You are the project's last engineering attempt at this capability.

Read:

{{CONTEXT_FILES}}

The chosen path is:

{{CHOSEN_PATH}}

Deliver that path fully. The previous attempts are evidence about which parts of
the problem are real, not noise to skip past. Append a one-line status to
`{{HEARTBEAT_FILE}}` as you go; rescue work runs long and a silent run is
terminated as hung.

Write it with the wrapper, which timestamps the line for you:
`./agentic/pm_flow/heartbeat.sh {{HEARTBEAT_FILE}} "<what you just did>"`.
Do not build the timestamp inline with `$(date ...)`; that is shell the
permission layer refuses, and a refused heartbeat reads as a silent run.

## Respond with these sections only, each as a Markdown heading

1. What I built
2. Why this works where the previous attempt did not
3. What I reused or restructured
4. Validation
5. Residual risk
6. Status

Paste the actual validation output. The only acceptable reason to stop short is
a structural one: a missing capability in a dependency, data that does not
exist, or a constraint that makes the goal unreachable. State it precisely if
you hit one.

The Status section must contain exactly one line, and that line must begin with
one of these exact tokens: DELIVERED, BLOCKED. A short justification may follow
the token on the same line.
