"""Expose pm-flow commands as MCP tools over JSON-RPC stdio."""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
from typing import Any


PROTOCOL_VERSION = "2024-11-05"
TOOL_COMMANDS = {
    "status": "status",
    "next": "next",
    "tick": "tick",
    "list_sections": "list-sections",
    "cost": "cost",
}


def _schema(tool_name: str) -> dict[str, Any]:
    properties: dict[str, Any] = {
        "project": {
            "type": "string",
            "description": "Optional pm-flow project key.",
        }
    }
    if tool_name == "tick":
        properties["section"] = {
            "type": "string",
            "description": "Optional section key to tick.",
        }
    return {
        "type": "object",
        "properties": properties,
        "additionalProperties": False,
    }


TOOLS = [
    {
        "name": name,
        "description": f"Run pm-flow {command}.",
        "inputSchema": _schema(name),
    }
    for name, command in TOOL_COMMANDS.items()
]


def _error(request_id: Any, code: int, message: str) -> dict[str, Any]:
    return {
        "jsonrpc": "2.0",
        "id": request_id,
        "error": {"code": code, "message": message},
    }


def _result(request_id: Any, result: Any) -> dict[str, Any]:
    return {"jsonrpc": "2.0", "id": request_id, "result": result}


def _validate_arguments(tool_name: str, arguments: Any) -> str | None:
    if not isinstance(arguments, dict):
        return "tool arguments must be an object"

    allowed = {"project"}
    if tool_name == "tick":
        allowed.add("section")
    unexpected = sorted(set(arguments) - allowed)
    if unexpected:
        return f"unexpected tool argument: {unexpected[0]}"

    for name, value in arguments.items():
        if not isinstance(value, str):
            return f"tool argument '{name}' must be a string"
    return None


def _command_for(tool_name: str, arguments: dict[str, str]) -> list[str]:
    installed = shutil.which("pm-flow")
    command = [installed] if installed else [sys.executable, "-m", "pm_flow.cli"]
    project = arguments.get("project")
    if project is not None:
        command.extend(["--project", project])
    command.append(TOOL_COMMANDS[tool_name])
    section = arguments.get("section")
    if section is not None:
        command.extend(["--section", section])
    return command


def _text_content(stdout: bytes, stderr: bytes) -> list[dict[str, str]]:
    content = []
    if stdout:
        content.append({"type": "text", "text": stdout.decode(errors="replace")})
    if stderr:
        content.append({"type": "text", "text": stderr.decode(errors="replace")})
    return content or [{"type": "text", "text": ""}]


def _call_tool(tool_name: str, arguments: dict[str, str]) -> dict[str, Any]:
    try:
        completed = subprocess.run(
            _command_for(tool_name, arguments),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
    except OSError as error:
        return {
            "content": [{"type": "text", "text": str(error)}],
            "isError": True,
        }
    return {
        "content": _text_content(completed.stdout, completed.stderr),
        "isError": completed.returncode != 0,
    }


def _handle(request: Any) -> dict[str, Any] | None:
    if not isinstance(request, dict) or request.get("jsonrpc") != "2.0":
        return _error(None, -32600, "Invalid Request")

    method = request.get("method")
    if not isinstance(method, str):
        return _error(request.get("id"), -32600, "Invalid Request")

    # JSON-RPC notifications never receive a response.
    if "id" not in request:
        return None

    request_id = request["id"]
    params = request.get("params", {})
    if method == "initialize":
        if not isinstance(params, dict):
            return _error(request_id, -32602, "initialize params must be an object")
        requested_version = params.get("protocolVersion", PROTOCOL_VERSION)
        if not isinstance(requested_version, str):
            return _error(request_id, -32602, "protocolVersion must be a string")
        return _result(
            request_id,
            {
                "protocolVersion": PROTOCOL_VERSION,
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "pm-flow", "version": "1"},
            },
        )

    if method == "tools/list":
        if not isinstance(params, dict):
            return _error(request_id, -32602, "tools/list params must be an object")
        return _result(request_id, {"tools": TOOLS})

    if method == "tools/call":
        if not isinstance(params, dict):
            return _error(request_id, -32602, "tools/call params must be an object")
        tool_name = params.get("name")
        if not isinstance(tool_name, str) or tool_name not in TOOL_COMMANDS:
            return _error(request_id, -32602, f"unknown tool: {tool_name}")
        arguments = params.get("arguments", {})
        argument_error = _validate_arguments(tool_name, arguments)
        if argument_error:
            return _error(request_id, -32602, argument_error)
        return _result(request_id, _call_tool(tool_name, arguments))

    return _error(request_id, -32601, f"Method not found: {method}")


def main() -> int:
    for line in sys.stdin:
        try:
            request = json.loads(line)
        except json.JSONDecodeError:
            response = _error(None, -32700, "Parse error")
        else:
            response = _handle(request)
        if response is not None:
            try:
                sys.stdout.write(json.dumps(response, separators=(",", ":")) + "\n")
                sys.stdout.flush()
            except BrokenPipeError:
                return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
