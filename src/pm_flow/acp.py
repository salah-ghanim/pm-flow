#!/usr/bin/env python3
"""Small, dependency-free ACP v1 client for pm-flow agent bindings."""

from __future__ import annotations

import argparse
import json
import os
import select
import signal
import subprocess
import sys
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, NamedTuple


class Result(NamedTuple):
    text: str
    enforceable: bool
    usage: dict[str, Any]


class ACPFailure(Exception):
    def __init__(self, reason: str, message: str) -> None:
        super().__init__(message)
        self.reason = reason


class _Cancelled(Exception):
    pass


@dataclass
class _Client:
    process: subprocess.Popen[bytes]
    max_attempt_seconds: float
    silent_stall_seconds: float
    started_at: float
    last_activity_at: float
    access_tier: str
    session_id: str | None = None
    buffer: bytes = b""

    def send(self, payload: dict[str, Any]) -> None:
        if self.process.stdin is None:
            raise ACPFailure("acp_child_exited", "agent stdin is unavailable")
        try:
            self.process.stdin.write(
                json.dumps(payload, separators=(",", ":")).encode() + b"\n"
            )
            self.process.stdin.flush()
        except (BrokenPipeError, OSError) as exc:
            raise ACPFailure("acp_child_exited", f"agent closed stdin: {exc}") from exc

    def request(self, request_id: int, method: str, params: dict[str, Any]) -> None:
        self.send(
            {
                "jsonrpc": "2.0",
                "id": request_id,
                "method": method,
                "params": params,
            }
        )

    def cancel(self) -> None:
        if self.session_id is not None and self.process.poll() is None:
            try:
                self.send(
                    {
                        "jsonrpc": "2.0",
                        "method": "session/cancel",
                        "params": {"sessionId": self.session_id},
                    }
                )
            except ACPFailure:
                pass

    def _line(self) -> bytes:
        if self.process.stdout is None:
            raise ACPFailure("acp_child_exited", "agent stdout is unavailable")
        while b"\n" not in self.buffer:
            now = time.monotonic()
            attempt_left = self.max_attempt_seconds - (now - self.started_at)
            stall_left = self.silent_stall_seconds - (now - self.last_activity_at)
            if attempt_left <= 0:
                raise ACPFailure("acp_attempt_timeout", "maximum attempt time exceeded")
            if stall_left <= 0:
                raise ACPFailure("acp_silent_stall", "agent produced no protocol activity")
            ready, _, _ = select.select(
                [self.process.stdout.fileno()], [], [], min(attempt_left, stall_left)
            )
            if not ready:
                continue
            chunk = os.read(self.process.stdout.fileno(), 65536)
            if not chunk:
                status = self.process.poll()
                suffix = "EOF" if status is None else f"exit status {status}"
                raise ACPFailure(
                    "acp_child_exited", f"agent exited before the result ({suffix})"
                )
            self.last_activity_at = time.monotonic()
            self.buffer += chunk
        line, self.buffer = self.buffer.split(b"\n", 1)
        return line

    def receive(self) -> dict[str, Any]:
        raw = self._line()
        try:
            frame = json.loads(raw)
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise ACPFailure("acp_malformed_frame", "agent emitted invalid JSON") from exc
        if not isinstance(frame, dict) or frame.get("jsonrpc") != "2.0":
            raise ACPFailure(
                "acp_malformed_frame", "agent emitted a non-JSON-RPC frame"
            )
        has_method = isinstance(frame.get("method"), str)
        has_id = "id" in frame
        has_result = "result" in frame
        has_error = "error" in frame
        response = has_id and not has_method and has_result != has_error
        message = has_method and not has_result and not has_error
        if not (response or message):
            raise ACPFailure(
                "acp_malformed_frame", "agent emitted an invalid JSON-RPC envelope"
            )
        return frame

    def respond_to_agent_request(self, frame: dict[str, Any]) -> None:
        if "id" not in frame:
            return
        if frame["method"] == "session/request_permission":
            params = frame.get("params")
            options = params.get("options") if isinstance(params, dict) else None
            selected = None
            if self.access_tier in {"write", "scoped"} and isinstance(options, list):
                for kind in ("allow_once", "allow_always"):
                    selected = next(
                        (
                            option
                            for option in options
                            if isinstance(option, dict)
                            and option.get("kind") == kind
                            and isinstance(option.get("optionId"), str)
                        ),
                        None,
                    )
                    if selected is not None:
                        break
            outcome = {"outcome": "cancelled"}
            if selected is not None:
                outcome = {
                    "outcome": "selected",
                    "optionId": selected["optionId"],
                }
            self.send(
                {
                    "jsonrpc": "2.0",
                    "id": frame["id"],
                    "result": {"outcome": outcome},
                }
            )
        else:
            self.send(
                {
                    "jsonrpc": "2.0",
                    "id": frame["id"],
                    "error": {"code": -32601, "message": "Method not found"},
                }
            )

    def response(self, request_id: int, on_notification: Any = None) -> dict[str, Any]:
        while True:
            frame = self.receive()
            if "method" in frame:
                if "id" in frame:
                    self.respond_to_agent_request(frame)
                elif on_notification is not None:
                    on_notification(frame)
                continue
            if frame.get("id") != request_id:
                raise ACPFailure(
                    "acp_malformed_frame", "agent responded with an unexpected request id"
                )
            if "error" in frame:
                error = frame["error"]
                message = error.get("message", "JSON-RPC error") if isinstance(error, dict) else str(error)
                raise ACPFailure("acp_rpc_error", message)
            if not isinstance(frame["result"], dict):
                raise ACPFailure("acp_malformed_frame", "JSON-RPC result is not an object")
            return frame["result"]


def _positive_seconds(params: dict[str, Any], name: str) -> float:
    try:
        value = float(params[name])
    except (KeyError, TypeError, ValueError) as exc:
        raise ACPFailure("acp_invalid_params", f"{name} must be provided as a number") from exc
    if value <= 0:
        raise ACPFailure("acp_invalid_params", f"{name} must be greater than zero")
    return value


def _is_enforceable(initialize: dict[str, Any], access_tier: str) -> bool:
    capabilities = initialize.get("agentCapabilities")
    if not isinstance(capabilities, dict):
        return False
    metadata = capabilities.get("_meta")
    declarations = [
        capabilities.get("sandbox"),
        capabilities.get("filesystemBoundary"),
        metadata.get("sandbox") if isinstance(metadata, dict) else None,
        metadata.get("filesystemBoundary") if isinstance(metadata, dict) else None,
    ]
    for declaration in declarations:
        if declaration is True:
            return True
        if isinstance(declaration, dict):
            tiers = declaration.get("tiers")
            if declaration.get("enforced") is True and tiers is None:
                return True
            if isinstance(tiers, list) and access_tier in tiers:
                return True
    # Reads need a declared boundary too: an unrestricted agent can read beyond
    # the requested root just as it can write beyond it. Therefore all three
    # pm-flow tiers use the same capability-declaration rule.
    return False


def _record_access(
    log_path: Path | None,
    role: str,
    label: str,
    enforceable: bool,
) -> None:
    if log_path is None:
        return
    record = {
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "role": role,
        "label": label,
        "tool": "ACP",
        "targets": [],
        "outside": False,
        "reaches_user_files": False,
        "access": "enforced" if enforceable else "prompt-level",
        "source": "acp-capabilities",
    }
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("a", encoding="utf-8") as stream:
        stream.write(json.dumps(record, separators=(",", ":"), sort_keys=True) + "\n")


def _reap(client: _Client) -> None:
    process = client.process
    if process.stdin is not None:
        try:
            process.stdin.close()
        except OSError:
            pass
    try:
        process.wait(timeout=0.5)
        return
    except subprocess.TimeoutExpired:
        pass
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=0.5)
        return
    except subprocess.TimeoutExpired:
        pass
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait()


def run(
    prompt: str,
    params: dict[str, Any],
    access_tier: str,
    *,
    access_log: Path | None = None,
    role: str = "",
    label: str = "",
) -> Result:
    """Run one ACP prompt against the command in a binding's ``cli_params``."""

    if access_tier not in {"read", "write", "scoped"}:
        raise ACPFailure("acp_invalid_params", f"unknown access tier: {access_tier}")
    command = params.get("command")
    if (
        not isinstance(command, list)
        or not command
        or any(not isinstance(part, str) or not part for part in command)
    ):
        raise ACPFailure("acp_invalid_params", "params.command must be a non-empty argv list")
    max_seconds = _positive_seconds(params, "max_attempt_seconds")
    stall_seconds = _positive_seconds(params, "silent_stall_seconds")
    process = subprocess.Popen(
        command,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        start_new_session=True,
        bufsize=0,
    )
    now = time.monotonic()
    client = _Client(process, max_seconds, stall_seconds, now, now, access_tier)
    previous_handlers: dict[int, Any] = {}

    def request_cancel(_signum: int, _frame: Any) -> None:
        raise _Cancelled

    if threading.current_thread() is threading.main_thread():
        for signum in (signal.SIGINT, signal.SIGTERM):
            previous_handlers[signum] = signal.getsignal(signum)
            signal.signal(signum, request_cancel)

    try:
        client.request(
            1,
            "initialize",
            {
                "protocolVersion": 1,
                "clientCapabilities": {},
                "clientInfo": {"name": "pm-flow", "version": "1"},
            },
        )
        initialized = client.response(1)
        enforceable = _is_enforceable(initialized, access_tier)
        _record_access(access_log, role, label, enforceable)
        client.request(2, "session/new", {"cwd": os.getcwd(), "mcpServers": []})
        session = client.response(2)
        session_id = session.get("sessionId")
        if not isinstance(session_id, str) or not session_id:
            raise ACPFailure("acp_malformed_frame", "session/new omitted sessionId")
        client.session_id = session_id
        text_parts: list[str] = []
        usage: dict[str, Any] = {}

        def update(frame: dict[str, Any]) -> None:
            if frame.get("method") != "session/update":
                return
            notification = frame.get("params")
            if not isinstance(notification, dict) or notification.get("sessionId") != session_id:
                raise ACPFailure("acp_malformed_frame", "invalid session/update notification")
            value = notification.get("update")
            if not isinstance(value, dict):
                raise ACPFailure("acp_malformed_frame", "session/update omitted update")
            if value.get("sessionUpdate") == "agent_message_chunk":
                content = value.get("content")
                if isinstance(content, dict) and content.get("type") == "text" and isinstance(content.get("text"), str):
                    text_parts.append(content["text"])
            elif value.get("sessionUpdate") == "usage_update":
                usage.clear()
                usage.update({key: item for key, item in value.items() if key != "sessionUpdate"})

        client.request(
            3,
            "session/prompt",
            {"sessionId": session_id, "prompt": [{"type": "text", "text": prompt}]},
        )
        prompt_result = client.response(3, update)
        if isinstance(prompt_result.get("usage"), dict):
            usage = dict(prompt_result["usage"])
        return Result("".join(text_parts), enforceable, usage)
    except _Cancelled as exc:
        client.cancel()
        raise ACPFailure("acp_cancelled", "ACP exchange cancelled by caller") from exc
    finally:
        for signum, handler in previous_handlers.items():
            signal.signal(signum, handler)
        _reap(client)


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run one ACP agent exchange")
    prompts = parser.add_mutually_exclusive_group(required=True)
    prompts.add_argument("--prompt")
    prompts.add_argument("--prompt-file", type=Path)
    parser.add_argument("--params-json", required=True)
    parser.add_argument("--access-tier", required=True, choices=("read", "write", "scoped"))
    parser.add_argument("--access-log", type=Path)
    parser.add_argument("--role", default="")
    parser.add_argument("--label", default="")
    parser.add_argument("--max-attempt-seconds", type=float)
    parser.add_argument("--silent-stall-seconds", type=float)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        params = json.loads(args.params_json)
        if not isinstance(params, dict):
            raise ValueError("params JSON is not an object")
        if args.max_attempt_seconds is not None:
            params["max_attempt_seconds"] = args.max_attempt_seconds
        if args.silent_stall_seconds is not None:
            params["silent_stall_seconds"] = args.silent_stall_seconds
        prompt = args.prompt_file.read_text() if args.prompt_file is not None else args.prompt
        result = run(
            prompt,
            params,
            args.access_tier,
            access_log=args.access_log,
            role=args.role,
            label=args.label,
        )
        reason = "none" if result.enforceable else "acp_capability_missing"
        payload = {
            "failure_reason": reason,
            "text": result.text,
            "enforceable": result.enforceable,
            "usage": result.usage,
        }
        status = 0
    except (ACPFailure, OSError, ValueError, json.JSONDecodeError) as exc:
        reason = exc.reason if isinstance(exc, ACPFailure) else "acp_invalid_params"
        payload = {
            "failure_reason": reason,
            "text": "",
            "enforceable": False,
            "usage": {},
            "error": str(exc),
        }
        status = 1
    print(json.dumps(payload, separators=(",", ":"), sort_keys=True))
    return status


if __name__ == "__main__":
    raise SystemExit(main())
