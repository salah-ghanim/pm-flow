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
Only `--protocol grpc` imports the SDK.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request
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

    payload = {
        "resourceSpans": [{
            "resource": {"attributes": _attributes(resource_attributes)},
            "scopeSpans": [{
                "scope": {"name": SCOPE_NAME},
                "spans": spans,
            }],
        }]
    }
    return validate_otlp_json(payload)


def validate_otlp_json(payload):
    """Check the OTLP/JSON shape produced here without importing the SDK."""
    try:
        resource_spans = payload["resourceSpans"]
        if not isinstance(resource_spans, list) or not resource_spans:
            raise ValueError("resourceSpans must be a non-empty list")
        for resource_span in resource_spans:
            if not isinstance(resource_span["resource"]["attributes"], list):
                raise ValueError("resource attributes must be a list")
            scope_spans = resource_span["scopeSpans"]
            if not isinstance(scope_spans, list) or not scope_spans:
                raise ValueError("scopeSpans must be a non-empty list")
            for scope_span in scope_spans:
                if not isinstance(scope_span["scope"]["name"], str):
                    raise ValueError("scope name must be a string")
                spans = scope_span["spans"]
                if not isinstance(spans, list):
                    raise ValueError("spans must be a list")
                for span in spans:
                    if (len(span["traceId"]) != 32 or len(span["spanId"]) != 16
                            or not all(char in "0123456789abcdef"
                                       for char in span["traceId"] + span["spanId"])):
                        raise ValueError("traceId/spanId must be lowercase hex")
                    for key in ("name", "startTimeUnixNano", "endTimeUnixNano"):
                        if not isinstance(span[key], str):
                            raise ValueError(f"{key} must be a string")
                    if not isinstance(span["kind"], int):
                        raise ValueError("kind must be an integer")
                    if not isinstance(span["attributes"], list):
                        raise ValueError("attributes must be a list")
                    if not isinstance(span["status"]["code"], int):
                        raise ValueError("status code must be an integer")
    except (KeyError, TypeError) as error:
        raise ValueError(f"invalid OTLP/JSON payload: {error}") from error
    return payload


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
    return len(rows)


# -------------------------------------------------------------- OTLP / net

def export_to_otlp(rows, events_by_span, resource_attributes, args):
    """Send spans and return the number the receiver acknowledged."""
    if args.protocol == "http":
        endpoint = args.otlp
        # Every backend listens on /v1/traces; accepting a bare origin and
        # completing it is the difference between this working first try and
        # silently posting to a UI route that returns 200 and drops the body.
        if not endpoint.rstrip("/").endswith("/v1/traces"):
            endpoint = endpoint.rstrip("/") + "/v1/traces"
        headers = parse_headers(args.header)
        headers["Content-Type"] = "application/json"
        payload = json.dumps(
            to_otlp_json(rows, events_by_span, resource_attributes)
        ).encode("utf-8")
        request = urllib.request.Request(
            endpoint, data=payload, headers=headers, method="POST"
        )
        try:
            with urllib.request.urlopen(request, timeout=args.timeout) as response:
                body = response.read()
        except urllib.error.HTTPError as error:
            print(
                f"OTLP export failed with HTTP {error.code}; "
                f"{len(rows)} span(s) kept for retry",
                file=sys.stderr,
            )
            return 0
        except (urllib.error.URLError, TimeoutError, OSError) as error:
            print(
                f"OTLP export failed: {error}; "
                f"{len(rows)} span(s) kept for retry",
                file=sys.stderr,
            )
            return 0

        try:
            rejected = int(
                json.loads(body.decode("utf-8"))
                .get("partialSuccess", {})
                .get("rejectedSpans", 0)
            )
        except (AttributeError, TypeError, ValueError, json.JSONDecodeError, UnicodeError):
            rejected = 0
        rejected = min(max(rejected, 0), len(rows))
        return len(rows) - rejected

    try:
        from opentelemetry.sdk.resources import Resource
        from opentelemetry.sdk.trace import Event, ReadableSpan
        from opentelemetry.sdk.util.instrumentation import InstrumentationScope
        from opentelemetry.trace import SpanContext, SpanKind, TraceFlags
        from opentelemetry.trace.status import Status, StatusCode
        from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import (
            OTLPSpanExporter,
        )
    except ImportError:
        raise SystemExit(
            "the gRPC exporter is not installed; use --protocol http "
            "or install opentelemetry-exporter-otlp-proto-grpc"
        )

    exporter = OTLPSpanExporter(
        endpoint=args.otlp, headers=parse_headers(args.header)
    )

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
    if getattr(result, "name", str(result)) in ("SUCCESS", "0"):
        return len(rows)
    return 0


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


def telemetry_config():
    """Read the project flow's telemetry defaults, falling back to this layout."""
    flow_dir = os.environ.get("PM_FLOW_FLOW_DIR")
    config_path = ((Path(flow_dir) if flow_dir else Path(__file__).resolve().parent)
                   / "config.json")
    try:
        config = json.loads(config_path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    telemetry = config.get("telemetry", {}) if isinstance(config, dict) else {}
    return telemetry if isinstance(telemetry, dict) else {}


def configured_headers(value):
    if isinstance(value, dict):
        return [f"{key}={item}" for key, item in value.items()]
    if isinstance(value, list):
        return [str(item) for item in value]
    return []


def recording_enabled(config):
    return config.get("enabled", 1) not in (False, 0, "0")


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
    args.export_incomplete = False
    rows = fetch_spans(connection, replay=args.replay, trace=args.trace,
                       limit=args.limit)
    if not rows:
        return 0
    events_by_span = fetch_events(connection, [row["span_id"] for row in rows])
    attributes = resource_attributes(args, connection)

    if args.file:
        acknowledged = export_to_file(rows, events_by_span, attributes, args.file)
    else:
        acknowledged = export_to_otlp(rows, events_by_span, attributes, args)

    exported = 0
    if acknowledged == len(rows):
        # A replay deliberately does not re-mark: it exists to send spans that
        # were already sent somewhere else, and clobbering the stamp would lose
        # the record of what the live exporter had already shipped.
        if not args.replay:
            mark_exported(connection, [row["span_id"] for row in rows])
        exported = len(rows)
    else:
        args.export_incomplete = True
        print(
            f"receiver acknowledged {acknowledged} of {len(rows)} span(s); "
            "all spans left unmarked and will be retried",
            file=sys.stderr,
        )
    return exported


def print_status(connection, config):
    if connection is None:
        unexported = in_flight = exported = 0
    else:
        unexported = connection.execute(
            "SELECT COUNT(*) FROM spans "
            "WHERE exported_at IS NULL AND ended_at IS NOT NULL"
        ).fetchone()[0]
        in_flight = connection.execute(
            "SELECT COUNT(*) FROM spans WHERE ended_at IS NULL"
        ).fetchone()[0]
        exported = connection.execute(
            "SELECT COUNT(*) FROM spans WHERE exported_at IS NOT NULL"
        ).fetchone()[0]
    endpoint = str(config.get("otlp_endpoint", "") or "")
    print(f"recording: {'enabled' if recording_enabled(config) else 'disabled'}")
    print(f"endpoint: {endpoint or 'none'}")
    print(f"unexported spans: {unexported}")
    print(f"in-flight spans: {in_flight}")
    print(f"exported spans: {exported}")


def main(argv):
    raw_args = list(argv[1:])
    command = "export"
    for index, token in enumerate(raw_args):
        if token in ("export", "status"):
            command = token
            del raw_args[index]
            break

    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--db", help="path to the store (or $PM_FLOW_STORE)")
    destination = parser.add_mutually_exclusive_group()
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
    parser.add_argument("--timeout", type=float, default=10.0,
                        help="HTTP request timeout in seconds")
    args = parser.parse_args(raw_args)

    config = telemetry_config()
    explicit_headers = args.header or []
    args.header = configured_headers(config.get("headers")) + explicit_headers
    if not args.otlp and not args.file:
        args.otlp = str(config.get("otlp_endpoint", "") or "")

    args.db = args.db or os.environ.get("PM_FLOW_STORE", "")
    if not args.db:
        raise SystemExit("no store: pass --db or set PM_FLOW_STORE")
    if not Path(args.db).exists() and command == "status":
        print_status(None, config)
        return 0
    if not Path(args.db).exists():
        raise SystemExit(f"no store at {args.db}")

    connection = store.connect(args.db)

    if command == "status":
        print_status(connection, config)
        return 0
    if not args.otlp and not args.file:
        parser.error(
            "trace export needs --otlp, --file, or telemetry.otlp_endpoint"
        )

    if not args.follow:
        count = export_once(connection, args)
        print(f"exported {count} span(s)")
        return 1 if args.export_incomplete else 0

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
