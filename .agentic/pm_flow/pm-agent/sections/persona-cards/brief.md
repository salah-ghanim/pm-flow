## Objective

- Give a persona a card: who wrote it, what it is for, what it is good at, and
  which version this is — so a persona can be published, discovered and credited
  rather than only copied.

## Scope

`plan.md` says a persona is portable because it names no model: a system prompt
that names a CLI cannot be shared with somebody who does not have that CLI.
`persona-packs` makes one installable. What neither provides is identity. Two
personas called `reviewer` from two authors are indistinguishable once
installed, nobody can tell which one a comparison actually measured, and there
is no way to credit the person who wrote the better one.

That is the social half, and it is the half that makes sharing worth doing. A
persona that measurably beats the default is worth publishing; publishing needs
a name, an author and a version attached to the artifact itself.

A2A's Agent Card is the closest existing shape and should be read before
designing anything: it already settles skills, versioning, provenance and
signing, and it is a Linux Foundation standard with real adoption rather than a
format invented here. Take that vocabulary.

Take it knowingly, though, because the fit is partial and pretending otherwise
would produce a bad format. An Agent Card describes a **deployed endpoint** — a
URL, a transport, a security scheme, a running service. A persona is a **prompt**
and deliberately describes no runtime at all. The endpoint half of an Agent Card
is exactly the half a persona must not have; the identity half is the half worth
copying. Where the two disagree, the invariant wins: a persona names no model, no
vendor and no transport, and a card that adds one has broken the thing the card
was supposed to make shareable.

Recorded as direction, deliberately not scoped here: publishing cards to a
registry, and running seats through a model router such as OpenRouter. Both are
plausible next steps and the card format should not foreclose either. Neither is
this section's work, and a card that grows an endpoint field to anticipate them
has already failed the paragraph above.

## Priority

- nice-to-have. Personas work uncredited and unversioned; without cards they
  stay private, and a persona nobody can attribute is one nobody will publish.

## Owned paths

- `src/pm_flow/persona_card.py`
- `template/.agentic/pm_flow/cards/**`
- `tests/persona_cards_test.sh`

New paths only. The catalog and store that install a persona belong to
`persona-packs`; read them, and hand that section a bounded change if a card has
to be written at install time, rather than editing its files from here.

## Dependencies

- persona-packs
- a2a-binding

`persona-packs` is the obvious one: there is no card without a persona format to
attach it to. `a2a-binding` is the less obvious one and is a real dependency
rather than sequencing, because one acceptance criterion below is that a stock
A2A client can read a card's skills. Proving that needs an A2A surface to read
them with; asserting it against a hand-written JSON file is precisely the kind of
evidence this project has already been burned by.

## Acceptance

Stated as outcomes in the running system.

- A persona installed from somewhere else displays its card — author, purpose,
  skills, version — without dispatching a model to do it.
- A card that names a model, a vendor or a transport is refused at install time,
  and the refusal says which field broke the rule. A persona whose portability
  has been silently voided is worse than one with no card.
- Two personas sharing a name but not an author are distinguishable in the
  catalog, and a comparison of the two reports which card produced which arm.
- A card survives a round trip: exported from this project, installed into a
  different one, and every field reads back identical.
- A persona with no card still installs and still runs. Cards are identity, not
  a licence to execute.
- A stock A2A client reading pm-flow's Agent Card sees a card's skills as A2A
  skills; where the two formats cannot be reconciled, the difference is written
  down where the format is defined rather than left for a reader to discover.
- The suite still passes.

## Rejection conditions

- A card carries an endpoint, a URL, a model name, a vendor name or a transport.
- A card becomes mandatory, so an uncarded persona stops working.
- Author or provenance is presented as a trust signal without anything
  establishing it; an unverified name is a claim, and the format must not let it
  read as a guarantee.
- The card format is invented from scratch where the Agent Card already settles
  the same question.
- Card fields are proven only against a fixture written by the same cycle.
- The suite is weakened, or made to exit zero without running to completion.
