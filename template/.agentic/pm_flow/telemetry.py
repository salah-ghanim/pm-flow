#!/usr/bin/env python3
"""Record what the flow is doing, as spans and attempts, into the store.

This is the process the driver shells out to. It is standard library only and
it is written to be unable to break a run: a telemetry failure prints an id and
exits zero, because losing an observation is a nuisance and losing a dispatch is
not.

It is also the only place that knows semantic conventions, and that is
deliberate. Neither agent CLI can be trusted to describe itself usefully:

  claude   emits OTLP spans with gen_ai.* attributes and accepts an inbound
           traceparent, so its own spans can nest under ours.
  codex    emits OTLP too, but under a private codex.* event schema with no
           gen_ai.* attributes at all, and much of it is marked log-only, which
           a span-oriented backend simply drops.

Neither knows what a project, a topology, a task or a role is - those exist only
here. So the orchestrator is the thing that has to describe the work, and it
compensates for the backend underneath it: token counts come out of claude's
response envelope and out of codex's JSONL event stream, and both end up in the
same attributes.

Those attributes are written twice, in two vocabularies, because the backends
disagree and both are cheap:

  gen_ai.*        OpenTelemetry GenAI semantic conventions - generic tooling
  llm.* input.value output.value openinference.span.kind
                  OpenInference - what Phoenix renders natively, and what
                  Langfuse maps onto its own model
  pm_flow.*       the things only this flow knows

Jaeger shows all of it as plain attributes and needs neither.
"""

from __future__ import annotations

import argparse
import json
import os
import socket
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import store  # noqa: E402

# How much prompt and response text to keep. Enough to see what was asked and
# what came back; not so much that the store becomes a copy of the repository.
DEFAULT_MAX_CONTENT_BYTES = 16384

PROVIDER_BY_CLI = {
    "claude": "anthropic",
    "codex": "openai",
    "copilot": "github",
}


# ------------------------------------------------------------------- ids

def new_trace_id() -> str:
    return os.urandom(16).hex()


def new_span_id() -> str:
    return os.urandom(8).hex()


def traceparent(trace_id: str, span_id: str, sampled: bool = True) -> str:
    """W3C trace context, as the child CLIs expect it in the environment."""
    return f"00-{trace_id}-{span_id}-{'01' if sampled else '00'}"


# --------------------------------------------------------------- usage

def _find_key(payload, wanted: str):
    """Depth-first search for a key anywhere in a decoded JSON document.

    Both CLIs nest usage differently and both have moved it between releases,
    so matching on shape rather than on an exact path keeps this working when
    they rearrange it again.
    """
    if isinstance(payload, dict):
        if wanted in payload:
            return payload[wanted]
        for value in payload.values():
            found = _find_key(value, wanted)
            if found is not None:
                return found
    elif isinstance(payload, list):
        for value in payload:
            found = _find_key(value, wanted)
            if found is not None:
                return found
    return None


def _as_int(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _as_float(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def usage_from_response(path) -> dict:
    """Token counts and cost out of a pm-flow response envelope.

    A successful claude dispatch publishes the CLI's own JSON, so usage sits at
    the top level. A failed one does not: the harness wraps whatever the CLI
    emitted as a string in `result`, and the usage ends up nested inside that
    string. Those are exactly the dispatches worth counting, so the nested form
    is parsed too.
    """
    usage = {}
    try:
        raw = Path(path).read_text(errors="replace")
    except OSError:
        return usage
    try:
        payload = json.loads(raw)
    except ValueError:
        return usage

    candidates = [payload]
    inner = payload.get("result") if isinstance(payload, dict) else None
    if isinstance(inner, str):
        try:
            candidates.append(json.loads(inner))
        except ValueError:
            pass

    for candidate in candidates:
        block = _find_key(candidate, "usage")
        if isinstance(block, dict):
            usage.setdefault("input_tokens", _as_int(block.get("input_tokens")))
            usage.setdefault("output_tokens", _as_int(block.get("output_tokens")))
            usage.setdefault(
                "cache_read_tokens", _as_int(block.get("cache_read_input_tokens"))
            )
            usage.setdefault(
                "cache_write_tokens", _as_int(block.get("cache_creation_input_tokens"))
            )
        cost = _find_key(candidate, "total_cost_usd")
        if cost is not None:
            usage.setdefault("cost_usd", _as_float(cost))

    return {key: value for key, value in usage.items() if value is not None}


def usage_from_codex_events(path) -> dict:
    """Token counts out of codex's JSONL event stream.

    codex reports usage nowhere else that pm-flow can reach: its response file
    holds only the last message, and its OTLP output carries no gen_ai.*
    attributes. `codex exec --json` does emit a token_count event, so that is
    where the numbers come from. The last such event in the stream is the
    cumulative one.
    """
    usage = {}
    try:
        lines = Path(path).read_text(errors="replace").splitlines()
    except OSError:
        return usage

    totals = None
    for line in lines:
        line = line.strip()
        if not line or not line.startswith("{"):
            continue
        try:
            event = json.loads(line)
        except ValueError:
            continue
        found = _find_key(event, "total_token_usage")
        if isinstance(found, dict):
            totals = found
    if not isinstance(totals, dict):
        return usage

    usage["input_tokens"] = _as_int(totals.get("input_tokens"))
    usage["output_tokens"] = _as_int(totals.get("output_tokens"))
    usage["cache_read_tokens"] = _as_int(totals.get("cached_input_tokens"))
    usage["reasoning_tokens"] = _as_int(totals.get("reasoning_output_tokens"))
    usage["total_tokens"] = _as_int(totals.get("total_tokens"))
    return {key: value for key, value in usage.items() if value is not None}


# -------------------------------------------------------------- semconv

def semconv_attributes(*, role=None, cli=None, model=None, thinking=None,
                       project=None, topology=None, task=None, cycle=None,
                       seat=None, attempt_no=None, label=None, step=None,
                       access=None, run_key=None, failure_reason=None,
                       usage=None, span_kind="AGENT",
                       input_text=None, output_text=None) -> dict:
    """One logical description of a call, in every vocabulary that matters."""
    attributes = {}
    usage = usage or {}

    def put(key, value):
        if value is not None and value != "":
            attributes[key] = value

    provider = PROVIDER_BY_CLI.get(cli or "", cli)

    # OpenInference - Phoenix reads this natively, Langfuse maps it.
    put("openinference.span.kind", span_kind)
    put("llm.model_name", model)
    put("llm.provider", provider)
    put("llm.system", provider)
    put("llm.token_count.prompt", usage.get("input_tokens"))
    put("llm.token_count.completion", usage.get("output_tokens"))
    put("llm.token_count.total", usage.get("total_tokens"))
    if thinking or model or cli:
        put("llm.invocation_parameters", store.dumps(
            {k: v for k, v in
             {"model": model, "reasoning_effort": thinking, "cli": cli}.items()
             if v}))

    # OpenTelemetry GenAI - generic tooling and anything reading the spec.
    # Only a span that really is a model call gets an operation name; tagging a
    # CHAIN as `chat` would make every run and tick look like a generation.
    if span_kind == "AGENT":
        put("gen_ai.operation.name", "invoke_agent")
    elif span_kind == "LLM":
        put("gen_ai.operation.name", "chat")
    put("gen_ai.system", provider)
    put("gen_ai.provider.name", provider)
    put("gen_ai.agent.name", role)
    put("gen_ai.request.model", model)
    put("gen_ai.request.reasoning_effort", thinking)
    put("gen_ai.usage.input_tokens", usage.get("input_tokens"))
    put("gen_ai.usage.output_tokens", usage.get("output_tokens"))
    # Langfuse maps this onto its cost model; nothing else reads it.
    put("gen_ai.usage.cost", usage.get("cost_usd"))

    # Grouping. Both Phoenix and Langfuse use session.id to collect a
    # conversation, which for this flow is one run.
    put("session.id", run_key)

    # What only pm-flow knows.
    put("pm_flow.project", project)
    put("pm_flow.topology", topology)
    put("pm_flow.task", task)
    put("pm_flow.cycle", cycle)
    put("pm_flow.role", role)
    put("pm_flow.seat", seat)
    put("pm_flow.attempt", attempt_no)
    put("pm_flow.label", label)
    put("pm_flow.step", step)
    put("pm_flow.cli", cli)
    put("pm_flow.access_tier", access)
    put("pm_flow.failure_reason", failure_reason)
    put("pm_flow.cost_usd", usage.get("cost_usd"))
    put("pm_flow.cache_read_tokens", usage.get("cache_read_tokens"))
    put("pm_flow.cache_write_tokens", usage.get("cache_write_tokens"))
    put("pm_flow.reasoning_tokens", usage.get("reasoning_tokens"))

    if input_text is not None:
        put("input.value", input_text)
        put("input.mime_type", "text/markdown")
    if output_text is not None:
        put("output.value", output_text)
        put("output.mime_type", "text/markdown")

    return attributes


# --------------------------------------------------------------- writes

def parse_attrs(pairs) -> dict:
    """`--attr key=value`, with numbers and booleans coerced so a backend can
    aggregate on them instead of receiving every measurement as a string."""
    attributes = {}
    for pair in pairs or []:
        if "=" not in pair:
            continue
        key, _, value = pair.partition("=")
        key = key.strip()
        value = value.strip()
        if not key:
            continue
        lowered = value.lower()
        if lowered in ("true", "false"):
            attributes[key] = lowered == "true"
            continue
        try:
            attributes[key] = int(value)
            continue
        except ValueError:
            pass
        try:
            attributes[key] = float(value)
            continue
        except ValueError:
            pass
        attributes[key] = value
    return attributes


def read_text(path, max_bytes=DEFAULT_MAX_CONTENT_BYTES):
    if not path:
        return None
    try:
        raw = Path(path).read_bytes()
    except OSError:
        return None
    if max_bytes and len(raw) > max_bytes:
        raw = raw[:max_bytes]
    return raw.decode("utf-8", "replace")


def capture_content() -> bool:
    """Prompts and responses are the point of an LLM trace, so this defaults on;
    a flow working on something sensitive turns it off in one variable."""
    return os.environ.get("PM_FLOW_TELEMETRY_CONTENT", "1") not in ("0", "false", "no")


def max_content_bytes() -> int:
    try:
        return int(os.environ.get("PM_FLOW_TELEMETRY_MAX_CONTENT",
                                  DEFAULT_MAX_CONTENT_BYTES))
    except ValueError:
        return DEFAULT_MAX_CONTENT_BYTES


def insert_span(connection, *, span_id, trace_id, parent_span_id, name, kind,
                started_at, attributes, run_id=None, attempt_id=None):
    with connection:
        connection.execute(
            "INSERT OR REPLACE INTO spans"
            " (span_id, trace_id, parent_span_id, name, kind, started_at,"
            "  status, attributes, run_id, attempt_id)"
            " VALUES (?, ?, ?, ?, ?, ?, 'UNSET', ?, ?, ?)",
            (span_id, trace_id, parent_span_id, name, kind, started_at,
             store.dumps(attributes), run_id, attempt_id),
        )


def finish_span(connection, *, span_id, status, message, attributes, ended_at):
    with connection:
        row = connection.execute(
            "SELECT attributes FROM spans WHERE span_id = ?", (span_id,)
        ).fetchone()
        if row is None:
            return
        merged = store.loads(row["attributes"])
        merged.update(attributes or {})
        connection.execute(
            "UPDATE spans SET ended_at = ?, status = ?, status_message = ?,"
            " attributes = ? WHERE span_id = ?",
            (ended_at, status, message, store.dumps(merged), span_id),
        )


# -------------------------------------------------------------- commands

def cmd_run_start(args):
    connection = store.connect(args.db)
    trace_id = new_trace_id()
    span_id = new_span_id()
    run_key = args.run_key or f"{time.strftime('%Y%m%dT%H%M%SZ', time.gmtime())}-{trace_id[:8]}"

    project_id = topology_id = None
    with connection:
        if args.project:
            connection.execute(
                "INSERT OR IGNORE INTO projects (key, name, domain, created_at)"
                " VALUES (?, ?, ?, ?)",
                (args.project, args.project, args.domain, store.now()),
            )
            row = connection.execute(
                "SELECT id FROM projects WHERE key = ?", (args.project,)
            ).fetchone()
            project_id = row["id"] if row else None
        if args.topology and project_id:
            connection.execute(
                "INSERT OR IGNORE INTO topologies"
                " (key, name, project_id, domain, created_at)"
                " VALUES (?, ?, ?, ?, ?)",
                (args.topology, args.topology, project_id, args.domain, store.now()),
            )
            row = connection.execute(
                "SELECT id FROM topologies WHERE key = ? AND project_id IS ?",
                (args.topology, project_id),
            ).fetchone()
            topology_id = row["id"] if row else None
        cursor = connection.execute(
            "INSERT INTO runs (run_key, trace_id, project_id, topology_id, command,"
            " label, started_at, status, host, pid)"
            " VALUES (?, ?, ?, ?, ?, ?, ?, 'running', ?, ?)",
            (run_key, trace_id, project_id, topology_id, args.command, args.label,
             store.now(), socket.gethostname(), os.getpid()),
        )
        run_id = cursor.lastrowid

    insert_span(
        connection, span_id=span_id, trace_id=trace_id, parent_span_id=None,
        name=f"pm_flow.{args.command or 'run'}", kind="INTERNAL",
        started_at=store.now(), run_id=run_id,
        attributes=semconv_attributes(
            project=args.project, topology=args.topology, run_key=run_key,
            span_kind="CHAIN", label=args.label,
        ),
    )
    print(f"run_id={run_id}")
    print(f"run_key={run_key}")
    print(f"trace_id={trace_id}")
    print(f"span_id={span_id}")
    return 0


def cmd_run_end(args):
    connection = store.connect(args.db)
    with connection:
        connection.execute(
            "UPDATE runs SET ended_at = ?, status = ? WHERE run_key = ? OR id = ?",
            (store.now(), args.status, args.run, args.run),
        )
    if args.span:
        finish_span(connection, span_id=args.span,
                    status="OK" if args.status in ("ok", "finished") else "ERROR",
                    message=args.message, attributes=parse_attrs(args.attr),
                    ended_at=store.now())
    return 0


def cmd_span_start(args):
    connection = store.connect(args.db)
    span_id = new_span_id()
    attributes = parse_attrs(args.attr)
    if args.span_kind:
        attributes.setdefault("openinference.span.kind", args.span_kind)
    insert_span(connection, span_id=span_id, trace_id=args.trace,
                parent_span_id=args.parent, name=args.name,
                kind=args.kind, started_at=store.now(), attributes=attributes,
                run_id=args.run)
    print(span_id)
    return 0


def cmd_span_end(args):
    connection = store.connect(args.db)
    finish_span(connection, span_id=args.span, status=args.status.upper(),
                message=args.message, attributes=parse_attrs(args.attr),
                ended_at=store.now())
    return 0


def cmd_event(args):
    connection = store.connect(args.db)
    with connection:
        connection.execute(
            "INSERT INTO span_events (span_id, at, name, attributes)"
            " VALUES (?, ?, ?, ?)",
            (args.span, store.now(), args.name, store.dumps(parse_attrs(args.attr))),
        )
    return 0


def cmd_traceparent(args):
    print(traceparent(args.trace, args.span))
    return 0


def cmd_attempt_start(args):
    connection = store.connect(args.db)
    span_id = new_span_id()

    run_row = connection.execute(
        "SELECT id, run_key, trace_id, project_id, topology_id FROM runs"
        " WHERE run_key = ? OR id = ?", (args.run, args.run)
    ).fetchone()
    run_id = run_row["id"] if run_row else None
    trace_id = args.trace or (run_row["trace_id"] if run_row else new_trace_id())
    run_key = run_row["run_key"] if run_row else None
    project_id = run_row["project_id"] if run_row else None
    topology_id = run_row["topology_id"] if run_row else None

    task_id = None
    if args.task and project_id:
        with connection:
            connection.execute(
                "INSERT OR IGNORE INTO tasks (project_id, key, title, created_at)"
                " VALUES (?, ?, ?, ?)",
                (project_id, args.task, args.task, store.now()),
            )
        row = connection.execute(
            "SELECT id FROM tasks WHERE project_id = ? AND key = ?",
            (project_id, args.task),
        ).fetchone()
        task_id = row["id"] if row else None

    agent_definition_id = None
    if args.agent_hash:
        row = connection.execute(
            "SELECT id FROM agent_definitions WHERE content_hash = ?",
            (args.agent_hash,),
        ).fetchone()
        agent_definition_id = row["id"] if row else None

    input_artifact_id = None
    input_text = None
    if args.prompt_file and capture_content():
        input_text = read_text(args.prompt_file, max_content_bytes())
        if input_text is not None:
            input_artifact_id = store.put_artifact(
                connection, input_text, max_bytes=max_content_bytes()
            )

    started = store.now()
    with connection:
        cursor = connection.execute(
            "INSERT INTO attempts"
            " (run_id, project_id, task_id, agent_definition_id, role_key, seat,"
            "  cycle, attempt_no, label, step, trace_id, span_id, cli, model,"
            "  thinking_level, access_tier, started_at, status, input_artifact_id)"
            " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'running', ?)",
            (run_id, project_id, task_id, agent_definition_id, args.role, args.seat,
             args.cycle, args.attempt_no, args.label, args.step, trace_id, span_id,
             args.cli, args.model, args.thinking, args.access, started,
             input_artifact_id),
        )
        attempt_id = cursor.lastrowid

    topology_key = None
    if topology_id:
        row = connection.execute(
            "SELECT key FROM topologies WHERE id = ?", (topology_id,)
        ).fetchone()
        topology_key = row["key"] if row else None
    project_key = None
    if project_id:
        row = connection.execute(
            "SELECT key FROM projects WHERE id = ?", (project_id,)
        ).fetchone()
        project_key = row["key"] if row else None

    attributes = semconv_attributes(
        role=args.role, cli=args.cli, model=args.model, thinking=args.thinking,
        project=project_key, topology=topology_key, task=args.task,
        cycle=args.cycle, seat=args.seat, attempt_no=args.attempt_no,
        label=args.label, step=args.step, access=args.access, run_key=run_key,
        span_kind=args.span_kind, input_text=input_text,
    )
    insert_span(connection, span_id=span_id, trace_id=trace_id,
                parent_span_id=args.parent_span, name=args.name or f"{args.role}",
                kind="CLIENT", started_at=started, attributes=attributes,
                run_id=run_id, attempt_id=attempt_id)

    print(f"attempt_id={attempt_id}")
    print(f"span_id={span_id}")
    print(f"trace_id={trace_id}")
    print(f"traceparent={traceparent(trace_id, span_id)}")
    return 0


def cmd_attempt_end(args):
    connection = store.connect(args.db)
    row = connection.execute(
        "SELECT * FROM attempts WHERE id = ?", (args.attempt,)
    ).fetchone()
    if row is None:
        return 0

    # Which backend actually ran is decided inside the dispatcher, not by the
    # caller, and the response envelope already records it. Reading it back here
    # keeps that resolution in one place instead of reimplementing it in shell.
    envelope = {}
    if args.response:
        try:
            envelope = json.loads(Path(args.response).read_text(errors="replace"))
        except (OSError, ValueError):
            envelope = {}
    if not isinstance(envelope, dict):
        envelope = {}
    cli = args.cli or envelope.get("pm_backend") or row["cli"]
    model = args.model or envelope.get("model") or row["model"]
    thinking = args.thinking or envelope.get("difficulty") or row["thinking_level"]
    attempt_no = _as_int(envelope.get("attempts")) or row["attempt_no"]
    failure_reason = args.failure_reason or envelope.get("failure_reason") or None
    if failure_reason == "none":
        failure_reason = None

    usage = {}
    if args.response:
        usage.update(usage_from_response(args.response))
    if args.events:
        # codex reports usage nowhere the response envelope can reach it, so the
        # event stream fills in what the envelope could not.
        for key, value in usage_from_codex_events(args.events).items():
            usage.setdefault(key, value)
    if args.cost_usd is not None:
        usage["cost_usd"] = args.cost_usd
    if usage.get("total_tokens") is None:
        pair = [usage.get("input_tokens"), usage.get("output_tokens")]
        if any(value is not None for value in pair):
            usage["total_tokens"] = sum(value or 0 for value in pair)

    output_text = None
    output_artifact_id = None
    if capture_content():
        output_text = read_text(args.output_file, max_content_bytes())
        if output_text is not None:
            output_artifact_id = store.put_artifact(
                connection, output_text, max_bytes=max_content_bytes()
            )

    ended = store.now()
    duration = ended - (row["started_at"] or ended)
    with connection:
        connection.execute(
            "UPDATE attempts SET ended_at = ?, duration_s = ?, status = ?,"
            " failure_reason = ?, cost_usd = ?, input_tokens = ?, output_tokens = ?,"
            " reasoning_tokens = ?, cache_read_tokens = ?, cache_write_tokens = ?,"
            " total_tokens = ?, output_artifact_id = ?, response_path = ?,"
            " cli = ?, model = ?, thinking_level = ?, attempt_no = ?"
            " WHERE id = ?",
            (ended, duration, args.status, failure_reason,
             usage.get("cost_usd"), usage.get("input_tokens"),
             usage.get("output_tokens"), usage.get("reasoning_tokens"),
             usage.get("cache_read_tokens"), usage.get("cache_write_tokens"),
             usage.get("total_tokens"), output_artifact_id, args.response,
             cli, model, thinking, attempt_no, args.attempt),
        )

    attributes = semconv_attributes(
        role=row["role_key"], cli=cli, model=model,
        thinking=thinking, usage=usage, attempt_no=attempt_no,
        failure_reason=failure_reason, span_kind=args.span_kind,
        output_text=output_text,
    )
    attributes.update(parse_attrs(args.attr))
    if row["span_id"]:
        finish_span(connection, span_id=row["span_id"],
                    status="OK" if args.status == "ok" else "ERROR",
                    message=failure_reason, attributes=attributes,
                    ended_at=ended)
    return 0


def cmd_outcome(args):
    connection = store.connect(args.db)
    run_row = connection.execute(
        "SELECT id, project_id FROM runs WHERE run_key = ? OR id = ?",
        (args.run, args.run),
    ).fetchone()
    task_id = None
    if args.task and run_row:
        row = connection.execute(
            "SELECT id FROM tasks WHERE project_id = ? AND key = ?",
            (run_row["project_id"], args.task),
        ).fetchone()
        task_id = row["id"] if row else None
    with connection:
        connection.execute(
            "INSERT INTO outcomes (run_id, project_id, task_id, attempt_id, metric,"
            " value_num, value_text, source, recorded_at)"
            " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (run_row["id"] if run_row else None,
             run_row["project_id"] if run_row else None,
             task_id, args.attempt, args.metric, args.num, args.text,
             args.source, store.now()),
        )
    return 0


def build_parser():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", required=False, help="path to the store")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("run-start")
    p.add_argument("--project"); p.add_argument("--topology")
    p.add_argument("--domain"); p.add_argument("--command", default="run")
    p.add_argument("--label"); p.add_argument("--run-key")
    p.set_defaults(func=cmd_run_start)

    p = sub.add_parser("run-end")
    p.add_argument("--run", required=True); p.add_argument("--span")
    p.add_argument("--status", default="ok"); p.add_argument("--message")
    p.add_argument("--attr", action="append")
    p.set_defaults(func=cmd_run_end)

    p = sub.add_parser("span-start")
    p.add_argument("--trace", required=True); p.add_argument("--parent")
    p.add_argument("--name", required=True); p.add_argument("--kind", default="INTERNAL")
    p.add_argument("--span-kind", default="CHAIN"); p.add_argument("--run", type=int)
    p.add_argument("--attr", action="append")
    p.set_defaults(func=cmd_span_start)

    p = sub.add_parser("span-end")
    p.add_argument("--span", required=True); p.add_argument("--status", default="ok")
    p.add_argument("--message"); p.add_argument("--attr", action="append")
    p.set_defaults(func=cmd_span_end)

    p = sub.add_parser("event")
    p.add_argument("--span", required=True); p.add_argument("--name", required=True)
    p.add_argument("--attr", action="append")
    p.set_defaults(func=cmd_event)

    p = sub.add_parser("traceparent")
    p.add_argument("--trace", required=True); p.add_argument("--span", required=True)
    p.set_defaults(func=cmd_traceparent)

    p = sub.add_parser("attempt-start")
    p.add_argument("--run", required=True); p.add_argument("--role", required=True)
    p.add_argument("--trace"); p.add_argument("--parent-span")
    p.add_argument("--task"); p.add_argument("--cycle", type=int)
    p.add_argument("--seat", type=int, default=1)
    p.add_argument("--attempt-no", type=int, default=1)
    p.add_argument("--label"); p.add_argument("--step"); p.add_argument("--name")
    p.add_argument("--cli"); p.add_argument("--model"); p.add_argument("--thinking")
    p.add_argument("--access"); p.add_argument("--agent-hash")
    p.add_argument("--prompt-file"); p.add_argument("--span-kind", default="AGENT")
    p.set_defaults(func=cmd_attempt_start)

    p = sub.add_parser("attempt-end")
    p.add_argument("--attempt", required=True, type=int)
    p.add_argument("--status", default="ok"); p.add_argument("--failure-reason")
    p.add_argument("--response"); p.add_argument("--events")
    p.add_argument("--output-file"); p.add_argument("--cost-usd", type=float)
    p.add_argument("--cli"); p.add_argument("--model"); p.add_argument("--thinking")
    p.add_argument("--span-kind", default="AGENT")
    p.add_argument("--attr", action="append")
    p.set_defaults(func=cmd_attempt_end)

    p = sub.add_parser("outcome")
    p.add_argument("--run", required=True); p.add_argument("--task")
    p.add_argument("--attempt", type=int); p.add_argument("--metric", required=True)
    p.add_argument("--num", type=float); p.add_argument("--text")
    p.add_argument("--source", default="derived")
    p.set_defaults(func=cmd_outcome)

    return parser


def main(argv):
    parser = build_parser()
    args = parser.parse_args(argv[1:])
    if not args.db:
        args.db = os.environ.get("PM_FLOW_STORE", "")
    if not args.db:
        # No store configured is not an error; it is telemetry being off.
        return 0
    return args.func(args)


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv))
    except SystemExit:
        raise
    except Exception as error:  # noqa: BLE001
        # Losing an observation is a nuisance. Losing a dispatch is not, and a
        # driver under `set -e` would take a non-zero exit as the latter.
        print(f"pm-flow telemetry: {error}", file=sys.stderr)
        raise SystemExit(0)
