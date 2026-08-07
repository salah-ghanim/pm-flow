---

# Task: write the section handoff

Section `{{SECTION_KEY}}` has been judged complete. Write the bounded handoff
that the product officer will read. It is the only thing that leaves this
section, so it must stand alone.

Read:

{{CONTEXT_FILES}}

Stay under 500 words and 8192 bytes. Do not summarise the transcript; state what
another section or the product officer needs in order to act.

## Respond with exactly these Markdown headings and nothing else

## Outcome
## Decisions
## Interfaces
## Risks
## What is unproven
## Next action

Under Interfaces, name anything another section now depends on. Under Risks,
name what could still go wrong and what would reveal it.

`What is unproven` is the heading that costs you something, so write it first
and cut it last. List every capability this section claims that has not been
demonstrated against the real thing: code exercised only against a fake, a
threshold met on one sample, a path no test covers, an integration that has
never contacted the system it integrates with. Name the observation that would
settle each one. `- None; every claim above was demonstrated against the real
system` is a legitimate answer and you must be able to defend it.

A reader above you treats this section as a claim and goes looking for the
artifact that proves it. Anything you leave out here, they will find.
