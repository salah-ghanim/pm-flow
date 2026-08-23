# persona-cards section handoff

## Outcome

Rebaselined into schema, catalog integration, round trip, comparison identity,
and A2A skill compatibility tasks. No card implementation exists.

## Decisions

- Cards are optional portable identity, never runtime configuration.
- A2A identity/skill vocabulary is reused; endpoint/vendor/model/transport fields
  are rejected.
- Unverified provenance is displayed as a claim, not trust.

## Interfaces

- Planned: `persona_card.py` plus optional card handling in the existing catalog.

## Risks

- Catalog and compare integrations need ownership/dependency handoffs. T1 is
  deliberately independent of both.

## What is unproven

- All A1–A7 outcomes; nothing has been implemented.

## Next action

Scope workplan T1, then transfer catalog ownership for T2.
