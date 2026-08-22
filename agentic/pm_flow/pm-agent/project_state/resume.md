# Resuming pm-flow self-hosting

Run it again:

```bash
./agentic/pm_flow/pm_flow.sh run
```

There is nothing to clean up first and no recovery flag to pass. The driver
keeps no record of what it was doing: each tick reads the section files, derives
the single next action, performs it, and exits. An interrupted run left the
files in a state that describes itself, so resuming is the same command.

A dispatch that died mid-flight leaves a claim with no output. That is treated
as an attempt that bought nothing and is retried; a claim that keeps failing
stops the run rather than spending further.

To see where things stand before continuing:

```bash
./agentic/pm_flow/pm_flow.sh status
```

`STATUS` is the section's lifecycle — `planned`, `active`, `blocked`, `done`,
`cancelled`. `NEXT ACTION` is what the next tick would do: `scope`, `develop`,
`review`, `escalate`, `adjudicate`, `rescue`, `review-rescue`, `complete`,
`abandon`, `waiting-dependencies`, or `idle`. A blocked section is idle until
deliberately reopened; a section waiting on dependencies cannot be dispatched
until every required section is done.

A section sitting at `escalate` has failed enough consecutive reviews to earn a
consultant panel. A section at `abandon` has exhausted its rescue rounds; read
`sections/<key>/escalation/adjudication.md` for why before overriding it.

To reopen a terminal section deliberately, publish an `active` or `planned`
handoff for it first.
