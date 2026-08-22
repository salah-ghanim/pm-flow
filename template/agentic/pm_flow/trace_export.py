#!/usr/bin/env python3
"""Ship recorded spans to whatever is listening, whenever it starts listening.

An unattended run lasts hours and the backend that wants its traces is usually
not running while they are produced. So nothing is exported live by necessity:
spans are recorded to the store first, and this replays them into a backend on
demand. Start Phoenix tomorrow and yesterday's run is still there to look at.

    trace_export.py --db runs/pm_flow.db --otlp http://localhost:6006
    trace_export.py --db runs/pm_flow.db --otlp http://localhost:4318 --replay
    trace_export.py --db runs/pm_flow.db --file traces.otlp.jsonl
    trace_export.py --db runs/pm_flow.db --otlp http://localhost:6006 --follow

Endpoints worth knowing, none of which this file needs to care about beyond the
URL, because all three speak OTLP:

    Phoenix    http://localhost:6006          (OTLP/HTTP; gRPC on 4317)
    Jaeger     http://localhost:4318
    Langfuse   http://localhost:3000/api/public/otel   with a Basic auth header

The `--file` path deliberately needs no dependency at all: OTLP/JSON is a
documented wire format and writing it is a dozen lines, so a store can always be
turned into something a collector will read even where nothing is installed.
Only `--otlp` imports the SDK.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import store  # noqa: E402

SERVICE_NAME = "pm-flow"
SCOPE_NAME = "pm-flow"

# OTLP enum values. Written out rather than imported so the file exporter stays
# dependency-free.
SPAN_KIND = {"UNSPECIFIED": 0, "INTERNAL": 1, "SERVER": 2, "CLIENT": 3,
             "PRODUCER": 4, "CONSUMER": 5}
STATUS_CODE = {"UNSET": 0, "OK": 1, "ERROR": 2}


def fetch_spans(connection, *, replay=False, trace=None, limit=0):
    """Finished spans awaiting export, oldest first.

    Unfinished spans are skipped: a span with no end time is a dispatch still in
    flight, and exporting it would put a permanently-open span in the backend.
    """
    where = ["ended_at IS NOT NULL"]
    params = []
    if not replay:
        where.append("exported_at IS NULL")
    if trace:
        where.append("trace_id = ?")
        params.append(trace)
    sql = ("SELECT * FROM spans WHERE " + " AND ".join(where) +
           " ORDER BY started_at ASC")
    if limit:
        sql += f" LIMIT {int(limit)}"
    return connection.execute(sql, params).fetchall()


def fetch_events(connection, span_ids):
    """Span events, grouped by span. One query rather than one per span."""
    if not span_ids:
        return {}
    marks = ",".join("?" for _ in span_ids)
    rows = connection.execute(
        f"SELECT * FROM span_events WHERE span_id IN ({marks}) ORDER BY at ASC",
        list(span_ids),
    ).fetchall()
    grouped = {}
    for row in rows:
        grouped.setdefault(row["span_id"], []).append(row)
    return grouped


def mark_exported(connection, span_ids):
    if not span_ids:
        return
    stamp = store.now()
    with connection:
        connection.executemany(
            "UPDATE spans SET exported_at = ? WHERE span_id = ?",
            [(stamp, span_id) for span_id in span_ids],
        )


# ------------------------------------------------------------- OTLP / JSON

def _attribute(key, value):
    """One OTLP AnyValue. Ints and floats stay numeric so a backend can
    aggregate them instead of receiving every token count as a string."""
    if isinstance(value, bool):
        return {"key": key, "value": {"boolValue": value}}
    if isinstance(value, int):
        return {"key": key, "value": {"intValue": str(value)}}
    if isinstance(value, float):
        return {"key": key, "value": {"doubleValue": value}}
    return {"key": key, "value": {"stringValue": str(value)}}


def _attributes(mapping):
    return [_attribute(key, value) for key, value in sorted((mapping or {}).items())]


def _nanos(seconds):
    return str(int((seconds or 0) * 1_000_000_000))


def to_otlp_json(rows, events_by_span, resource_attributes):
    """The store's rows as an OTLP ExportTraceServiceRequest, JSON-encoded.

    OTLP/JSON encodes trace and span ids as hex strings, not base64 - that is the
    one place the JSON mapping deliberately departs from protobuf's defaults.
    """
    spans = []
    for row in rows:
        span = {
            "traceId": row["trace_id"],
            "spanId": row["span_id"],
            "name": row["name"],
            "kind": SPAN_KIND.get((row["kind"] or "INTERNAL").upper(), 1),
            "startTimeUnixNano": _nanos(row["started_at"]),
            "endTimeUnixNano": _nanos(row["ended_at"]),
            "attributes": _attributes(store.loads(row["attributes"])),
            "status": {"code": STATUS_CODE.get((row["status"] or "UNSET").upper(), 0)},
        }
        if row["parent_span_id"]:
            span["parentSpanId"] = row["parent_span_id"]
        if row["status_message"]:
            span["status"]["message"] = row["status_message"]
        events = events_by_span.get(row["span_id"]) or []
        if events:
            span["events"] = [
                {"timeUnixNano": _nanos(event["at"]), "name": event["name"],
                 "attributes": _attributes(store.loads(event["attributes"]))}
                for event in events
            ]
        spans.append(span)

    return {
        "resourceSpans": [{
            "resource": {"attributes": _attributes(resource_attributes)},
            "scopeSpans": [{
                "scope": {"name": SCOPE_NAME},
                "spans": spans,
            }],
        }]
    }


def export_to_file(rows, events_by_span, resource_attributes, path):
    """Append one OTLP/JSON request per line.

    Line-delimited because that is what a collector's otlpjson receiver reads
    and what makes the file appendable across runs.
    """
    payload = to_otlp_json(rows, events_by_span, resource_attributes)
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(payload, ensure_ascii=False) + "\n")
    return True


# -------------------------------------------------------------- OTLP / net

def export_to_otlp(rows, events_by_span, resource_attributes, args):
    """Hand the spans to the OpenTelemetry SDK's exporter.

    The SDK is used rather than a hand-rolled POST because the parts that are
    tedious to get right - retry and backoff, gzip, protobuf framing, partial
    success handling - are exactly the parts it already has.
    """
    try:
        from opentelemetry.sdk.resources import Resource
        from opentelemetry.sdk.trace import Event, ReadableSpan
        from opentelemetry.sdk.util.instrumentation import InstrumentationScope
        from opentelemetry.trace import SpanContext, SpanKind, TraceFlags
        from opentelemetry.trace.status import Status, StatusCode
    except ImportError:
        raise SystemExit(
            "sending to an endpoint needs the OpenTelemetry SDK:\n"
            "    pip install -r agentic/pm_flow/requirements-telemetry.txt\n"
            "Writing a file with --file needs nothing installed."
        )

    if args.protocol == "grpc":
        try:
            from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import (
                OTLPSpanExporter,
            )
        except ImportError:
            raise SystemExit(
                "the gRPC exporter is not installed; use --protocol http "
                "or install opentelemetry-exporter-otlp-proto-grpc"
            )
        exporter = OTLPSpanExporter(endpoint=args.otlp, headers=parse_headers(args.header))
    else:
        try:
            from opentelemetry.exporter.otlp.proto.http.trace_exporter import (
                OTLPSpanExporter,
            )
        except ImportError:
            raise SystemExit(
                "the HTTP exporter is not installed:\n"
                "    pip install -r agentic/pm_flow/requirements-telemetry.txt"
            )
        endpoint = args.otlp
        # Every backend listens on /v1/traces; accepting a bare origin and
        # completing it is the difference between this working first try and
        # silently posting to a UI route that returns 200 and drops the body.
        if not endpoint.rstrip("/").endswith("/v1/traces"):
            endpoint = endpoint.rstrip("/") + "/v1/traces"
        exporter = OTLPSpanExporter(endpoint=endpoint, headers=parse_headers(args.header))

    kind_by_name = {
        "INTERNAL": SpanKind.INTERNAL, "SERVER": SpanKind.SERVER,
        "CLIENT": SpanKind.CLIENT, "PRODUCER": SpanKind.PRODUCER,
        "CONSUMER": SpanKind.CONSUMER,
    }
    status_by_name = {
        "UNSET": StatusCode.UNSET, "OK": StatusCode.OK, "ERROR": StatusCode.ERROR,
    }

    resource = Resource.create(resource_attributes)
    scope = InstrumentationScope(SCOPE_NAME)
    readable = []
    for row in rows:
        context = SpanContext(
            trace_id=int(row["trace_id"], 16),
            span_id=int(row["span_id"], 16),
            is_remote=False,
            trace_flags=TraceFlags(TraceFlags.SAMPLED),
        )
        parent = None
        if row["parent_span_id"]:
            parent = SpanContext(
                trace_id=int(row["trace_id"], 16),
                span_id=int(row["parent_span_id"], 16),
                is_remote=False,
                trace_flags=TraceFlags(TraceFlags.SAMPLED),
            )
        events = [
            Event(name=event["name"],
                  attributes=store.loads(event["attributes"]),
                  timestamp=int((event["at"] or 0) * 1_000_000_000))
            for event in events_by_span.get(row["span_id"]) or []
        ]
        readable.append(ReadableSpan(
            name=row["name"],
            context=context,
            parent=parent,
            resource=resource,
            attributes=store.loads(row["attributes"]),
            events=tuple(events),
            links=(),
            kind=kind_by_name.get((row["kind"] or "INTERNAL").upper(),
                                  SpanKind.INTERNAL),
            instrumentation_scope=scope,
            status=Status(
                status_by_name.get((row["status"] or "UNSET").upper(),
                                   StatusCode.UNSET),
                row["status_message"] or None,
            ),
            start_time=int((row["started_at"] or 0) * 1_000_000_000),
            end_time=int((row["ended_at"] or 0) * 1_000_000_000),
        ))

    result = exporter.export(readable)
    exporter.shutdown()
    return getattr(result, "name", str(result)) in ("SUCCESS", "0")


def parse_headers(pairs):
    """`--header k=v`, plus Langfuse's Basic auth spelled the short way."""
    headers = {}
    for pair in pairs or []:
        if "=" in pair:
            key, _, value = pair.partition("=")
        elif ":" in pair:
            key, _, value = pair.partition(":")
        else:
            continue
        headers[key.strip()] = value.strip()

    public = os.environ.get("LANGFUSE_PUBLIC_KEY")
    secret = os.environ.get("LANGFUSE_SECRET_KEY")
    if public and secret and "Authorization" not in headers:
        token = base64.b64encode(f"{public}:{secret}".encode()).decode()
        headers["Authorization"] = f"Basic {token}"
    return headers


def resource_attributes(args, connection):
    attributes = {
        "service.name": args.service_name,
        "service.namespace": "pm-flow",
        "telemetry.sdk.language": "python",
    }
    row = connection.execute(
        "SELECT p.key AS project, p.domain AS domain FROM projects p"
        " ORDER BY p.id LIMIT 1"
    ).fetchone()
    if row:
        if row["project"]:
            attributes["pm_flow.project"] = row["project"]
        if row["domain"]:
            attributes["pm_flow.domain"] = row["domain"]
    if args.environment:
        attributes["deployment.environment.name"] = args.environment
    return attributes


def export_once(connection, args) -> int:
    rows = fetch_spans(connection, replay=args.replay, trace=args.trace,
                       limit=args.limit)
    if not rows:
        return 0
    events_by_span = fetch_events(connection, [row["span_id"] for row in rows])
    attributes = resource_attributes(args, connection)

    if args.file:
        ok = export_to_file(rows, events_by_span, attributes, args.file)
    else:
        ok = export_to_otlp(rows, events_by_span, attributes, args)

    if ok:
        # A replay deliberately does not re-mark: it exists to send spans that
        # were already sent somewhere else, and clobbering the stamp would lose
        # the record of what the live exporter had already shipped.
        if not args.replay:
            mark_exported(connection, [row["span_id"] for row in rows])
        return len(rows)
    raise SystemExit("export failed; spans left unmarked and will be retried")


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--db", help="path to the store (or $PM_FLOW_STORE)")
    destination = parser.add_mutually_exclusive_group(required=True)
    destination.add_argument("--otlp", help="OTLP endpoint, e.g. http://localhost:6006")
    destination.add_argument("--file", help="append OTLP/JSON lines to this path")
    parser.add_argument("--protocol", choices=("http", "grpc"), default="http")
    parser.add_argument("--header", action="append",
                        help="extra OTLP header, key=value (repeatable)")
    parser.add_argument("--service-name", default=SERVICE_NAME)
    parser.add_argument("--environment")
    parser.add_argument("--trace", help="only this trace id")
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--replay", action="store_true",
                        help="include spans already exported")
    parser.add_argument("--follow", action="store_true",
                        help="keep exporting as new spans are recorded")
    parser.add_argument("--interval", type=float, default=5.0)
    args = parser.parse_args(argv[1:])

    args.db = args.db or os.environ.get("PM_FLOW_STORE", "")
    if not args.db:
        raise SystemExit("no store: pass --db or set PM_FLOW_STORE")
    if not Path(args.db).exists():
        raise SystemExit(f"no store at {args.db}")

    connection = store.connect(args.db)

    if not args.follow:
        count = export_once(connection, args)
        print(f"exported {count} span(s)")
        return 0

    print(f"following {args.db}; ctrl-c to stop")
    total = 0
    try:
        while True:
            # --replay would resend everything on every pass, so a follow loop
            # is always incremental regardless of how it was invoked.
            args.replay = False
            sent = export_once(connection, args)
            if sent:
                total += sent
                print(f"exported {sent} span(s) ({total} total)")
            time.sleep(args.interval)
    except KeyboardInterrupt:
        print(f"\nstopped after {total} span(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
