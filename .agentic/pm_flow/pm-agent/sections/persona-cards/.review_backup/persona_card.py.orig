"""Parse, validate, and export portable persona cards.

A persona card deliberately keeps only the identity half of an A2A Agent
Card.  It omits ``protocolVersion``, service interfaces and URLs, provider
URLs, documentation and icons, capabilities, authentication and security,
input/output defaults, signatures, and authenticated-card discovery.  Those
fields describe a deployed runtime; a persona is only a portable prompt.

The retained ``skills`` use the A2A 0.2.5 ``AgentSkill`` vocabulary.  Authors
and provenance are unverified claims, not trust signals, so their stored values
must carry the literal ``unverified claim:`` label that a caller can display.
"""

from __future__ import annotations

import json
from collections.abc import Mapping
from typing import Any


class PersonaCardError(ValueError):
    """A persona card that cannot be parsed or validated."""


FORBIDDEN_CARD_KEYS = frozenset({"model", "vendor", "transport", "url", "endpoint"})
CARD_KEYS = frozenset({"name", "author", "purpose", "version", "skills", "provenance"})
REQUIRED_CARD_KEYS = frozenset({"name", "author", "purpose", "version", "skills"})
SKILL_KEYS = frozenset(
    {"id", "name", "description", "tags", "examples", "inputModes", "outputModes"}
)
REQUIRED_SKILL_KEYS = frozenset({"id", "name", "description", "tags"})
CLAIM_PREFIX = "unverified claim: "


def _reject_forbidden_fields(value: Any, path: str = "") -> None:
    """Refuse runtime-bearing field names anywhere in a card."""

    if isinstance(value, Mapping):
        for key, item in value.items():
            normalised = str(key).strip().lower().replace("-", "_")
            if normalised in FORBIDDEN_CARD_KEYS:
                raise PersonaCardError(
                    f'card field "{normalised}" is not allowed on a persona'
                )
            child_path = f"{path}.{key}" if path else str(key)
            _reject_forbidden_fields(item, child_path)
    elif isinstance(value, list):
        for index, item in enumerate(value):
            _reject_forbidden_fields(item, f"{path}[{index}]")


def _required_text(value: Any, field: str) -> None:
    if not isinstance(value, str) or not value.strip():
        raise PersonaCardError(f"{field} must be a non-empty string")


def _claim_text(value: Any, field: str) -> None:
    _required_text(value, field)
    if not value.startswith(CLAIM_PREFIX) or not value[len(CLAIM_PREFIX) :].strip():
        raise PersonaCardError(
            f'{field} must be labelled with "{CLAIM_PREFIX.rstrip()}"'
        )


def _string_list(value: Any, field: str) -> None:
    if not isinstance(value, list) or any(
        not isinstance(item, str) or not item.strip() for item in value
    ):
        raise PersonaCardError(f"{field} must be a list of non-empty strings")


def _validate_skill(skill: Any, index: int) -> None:
    field = f"skills[{index}]"
    if not isinstance(skill, Mapping):
        raise PersonaCardError(f"{field} must be an object")

    missing = REQUIRED_SKILL_KEYS.difference(skill)
    if missing:
        name = sorted(missing)[0]
        raise PersonaCardError(f'{field} is missing required field "{name}"')
    extra = set(skill).difference(SKILL_KEYS)
    if extra:
        name = sorted(str(key) for key in extra)[0]
        raise PersonaCardError(f'{field} has unsupported field "{name}"')

    for name in ("id", "name", "description"):
        _required_text(skill[name], f"{field}.{name}")
    _string_list(skill["tags"], f"{field}.tags")
    for name in ("examples", "inputModes", "outputModes"):
        if name in skill:
            _string_list(skill[name], f"{field}.{name}")


def validate(card: Any) -> Any:
    """Validate *card* and return it unchanged.

    Runtime-bearing names are checked first and depth-first so that a buried
    forbidden field receives the same stable refusal as a top-level one.
    """

    _reject_forbidden_fields(card)
    if not isinstance(card, Mapping):
        raise PersonaCardError("persona card must be an object")

    missing = REQUIRED_CARD_KEYS.difference(card)
    if missing:
        name = sorted(missing)[0]
        raise PersonaCardError(f'persona card is missing required field "{name}"')
    extra = set(card).difference(CARD_KEYS)
    if extra:
        name = sorted(str(key) for key in extra)[0]
        raise PersonaCardError(f'card field "{name}" is not part of the persona vocabulary')

    for name in ("name", "purpose", "version"):
        _required_text(card[name], name)
    _claim_text(card["author"], "author")

    skills = card["skills"]
    if not isinstance(skills, list):
        raise PersonaCardError("skills must be a list")
    for index, skill in enumerate(skills):
        _validate_skill(skill, index)

    if "provenance" in card:
        provenance = card["provenance"]
        if not isinstance(provenance, Mapping):
            raise PersonaCardError("provenance must be an object")
        for name, value in provenance.items():
            _claim_text(value, f"provenance.{name}")

    return card


def parse(text: str) -> dict[str, Any]:
    """Parse and validate a persona card JSON document."""

    if not isinstance(text, str):
        raise PersonaCardError("persona card input must be text")
    try:
        card = json.loads(text)
    except json.JSONDecodeError as exc:
        raise PersonaCardError(f"persona card is not valid JSON: {exc.msg}") from exc
    validate(card)
    return card


def export(card: Any) -> str:
    """Validate and export *card* as stable, human-readable JSON."""

    validate(card)
    return json.dumps(card, ensure_ascii=False, indent=2) + "\n"
