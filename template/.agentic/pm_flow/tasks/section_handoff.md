---

# Task: write the section handoff

Section `{{SECTION_KEY}}` has been judged complete. Write the bounded report
the product officer and dependent sections will read. It is the only thing
that leaves this section, so it stands alone.

Read:

{{CONTEXT_FILES}}

Stay under 500 words and 8192 bytes. State what a reader needs in order to act;
do not summarise the transcript or restate the brief.

Your response text IS the handoff document: the driver validates it and writes
it to `handoff.md` itself. Do not write any file, and do not reply with a
summary of a document you wrote elsewhere - a response that is not the
document fails, whatever any file says.

## Respond with exactly these Markdown headings and nothing else

## Outcome
## Decisions
## Interfaces
## Risks
## What is unproven
## Next action

`Outcome` covers every acceptance ID in `brief.md`, one line each, with the
evidence that closed it and the commit it lives in. `Decisions` lists only the
choices that still constrain anyone. `Interfaces` names what another section
now depends on, by path or command. `Risks` names what could still go wrong and
what would reveal it.

`What is unproven` costs you something, so write it first and cut it last: every
capability this section claims that was not demonstrated against the real
thing - code exercised only against a fake, a threshold met on one sample, a
path no test covers, an integration that never contacted the system it
integrates with - and the observation that would settle each. `- None; every
claim above was demonstrated against the real system` is legitimate and must be
defensible. A reader above you treats this section as a claim and goes looking
for the artifact; anything left out here, they will find.
