"""Pinned OpenTelemetry GenAI semantic-convention names for pm-flow.

The conventions are Development. ``v1.37.0`` was verified against the
``semantic-conventions`` repository's ``model/gen-ai/*.yaml`` at:
https://github.com/open-telemetry/semantic-conventions/tree/v1.37.0/model/gen-ai

``v1.36.0`` is deliberately supported as the comparison pin. Its registry
uses ``gen_ai.system`` where ``v1.37.0`` uses
``gen_ai.provider.name``; the rename is the observable revision difference
used to prove that telemetry reads this module rather than an installed copy:
https://github.com/open-telemetry/semantic-conventions/tree/v1.36.0/model/gen-ai
"""

from __future__ import annotations

REVISION = "v1.37.0"

SPAN_OPERATIONS = {
    "AGENT": "invoke_agent",
    "LLM": "chat",
}

_ATTRIBUTE_NAMES = {
    "operation": "gen_ai.operation.name",
    "agent_name": "gen_ai.agent.name",
    "request_model": "gen_ai.request.model",
    "input_tokens": "gen_ai.usage.input_tokens",
    "output_tokens": "gen_ai.usage.output_tokens",
}

_PROVIDER_ATTRIBUTES = {
    "v1.36.0": "gen_ai.system",
    "v1.37.0": "gen_ai.provider.name",
}


def attributes_for(attempt) -> dict:
    """Return pinned convention attributes for one logical attempt."""
    try:
        provider_attribute = _PROVIDER_ATTRIBUTES[REVISION]
    except KeyError as error:
        raise ValueError(f"unsupported semantic-conventions revision: {REVISION}") from error

    attributes = {}

    def put(key, value):
        if value is not None and value != "":
            attributes[key] = value

    usage = attempt.get("usage") or {}
    put(_ATTRIBUTE_NAMES["operation"], SPAN_OPERATIONS.get(attempt.get("span_kind")))
    put(provider_attribute, attempt.get("provider"))
    put(_ATTRIBUTE_NAMES["agent_name"], attempt.get("role"))
    put(_ATTRIBUTE_NAMES["request_model"], attempt.get("model"))
    put(_ATTRIBUTE_NAMES["input_tokens"], usage.get("input_tokens"))
    put(_ATTRIBUTE_NAMES["output_tokens"], usage.get("output_tokens"))

    # Neither verified registry defines request reasoning effort or usage cost.
    # Cost already has a pm-flow attribute in telemetry; preserve thinking here.
    put("pm_flow.thinking", attempt.get("thinking"))
    return attributes
