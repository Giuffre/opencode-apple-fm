#!/usr/bin/env python3
"""Verifica end-to-end che `fm serve` sia raggiungibile e faccia tool calling.

Uso:
    python3 scripts/smoke-test.py [port]

Esce 0 se tutto ok, 1 al primo fallback.
"""

from __future__ import annotations

import json
import sys
import urllib.error
import urllib.request
from typing import NoReturn

TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "add",
            "description": "Add two integers and return their sum",
            "parameters": {
                "type": "object",
                "properties": {
                    "a": {"type": "integer"},
                    "b": {"type": "integer"},
                },
                "required": ["a", "b"],
            },
        },
    }
]


def fail(message: str) -> NoReturn:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def get_json(url: str) -> dict:
    try:
        with urllib.request.urlopen(url, timeout=10) as response:
            return json.load(response)
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
        fail(f"impossibile fare GET {url}: {exc}")


def post_json(url: str, payload: dict) -> dict:
    data = json.dumps(payload).encode()
    request = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            return json.load(response)
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
        fail(f"impossibile fare POST {url}: {exc}")


def main() -> None:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 1976
    base = f"http://127.0.0.1:{port}"

    health = get_json(f"{base}/health")
    if "running" not in str(health.get("status", "")):
        fail(f"/health non pronto: {health}")
    print("OK   /health")

    models = get_json(f"{base}/v1/models")
    ids = [m.get("id") for m in models.get("data", [])]
    if "system" not in ids:
        fail(f"modello 'system' assente in /v1/models: {ids}")
    print("OK   /v1/models -> system")

    messages = [
        {
            "role": "user",
            "content": "Use the add tool to compute 2 + 3. Call the tool now.",
        }
    ]
    first = post_json(
        f"{base}/v1/chat/completions",
        {
            "model": "system",
            "stream": False,
            "messages": messages,
            "tools": TOOLS,
        },
    )
    try:
        tool_call = first["choices"][0]["message"]["tool_calls"][0]
    except (KeyError, IndexError, TypeError):
        fail(
            "il modello non ha emesso tool_calls. "
            "Su macOS 27.0.x il tool calling di fm serve è rotto: "
            "aggiorna a 27.2+ oppure usa install.sh --no-tools"
        )
    call_id = tool_call["id"]
    name = tool_call["function"]["name"]
    args = json.loads(tool_call["function"]["arguments"])
    if name != "add" or {k: int(v) for k, v in args.items()} != {"a": 2, "b": 3}:
        fail(f"tool_call inatteso: {name} {args}")
    print("OK   tool_calls -> add(a=2, b=3)")

    messages.extend(
        [
            {
                "role": "assistant",
                "tool_calls": [tool_call],
            },
            {
                "role": "tool",
                "tool_call_id": call_id,
                "content": "5",
            },
        ]
    )
    second = post_json(
        f"{base}/v1/chat/completions",
        {
            "model": "system",
            "stream": False,
            "messages": messages,
            "tools": TOOLS,
        },
    )
    content = second.get("choices", [{}])[0].get("message", {}).get("content", "")
    if "5" not in str(content):
        fail(f"il modello non ha usato il risultato del tool: {content!r}")
    print("OK   tool result -> risposta finale")

    print("SMOKE TEST PASS")


if __name__ == "__main__":
    main()
