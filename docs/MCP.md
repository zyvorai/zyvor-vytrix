# Vytrix MCP server

`agent/vytrix_mcp.py` lets an MCP client (an AI assistant, an editor) ask a running collector about the host. It is a single Python 3.10+ standard-library file speaking newline-delimited JSON-RPC on stdio.

## Read-only, by construction

Every tool is one `GET` on the collector's `/v1` API. There is no tool that kills a process, changes a setting or writes anything, and the test suite (`tests/test_mcp.py`) asserts that every tool is a `GET`, is marked `readOnlyHint`, and that tool names contain no mutating verb. Arguments are validated against each tool's schema; unknown arguments are refused.

## Run it

```bash
VYTRIX_URL=http://127.0.0.1:9847 VYTRIX_TOKEN=<collector token> python3 agent/vytrix_mcp.py
```

- `VYTRIX_URL` defaults to `http://127.0.0.1:9847`. Plain HTTP is only accepted for localhost; anything else must be `https://`.
- The token is read from the environment only (never an argument, so it does not show in `ps`) and is never printed.
- Client config, for example:

```json
{ "mcpServers": { "vytrix": {
  "command": "python3",
  "args": ["/path/to/agent/vytrix_mcp.py"],
  "env": { "VYTRIX_TOKEN": "<collector token>" }
} } }
```

## Tools

| Tool | Collector endpoint |
|---|---|
| `vytrix_snapshot` | `/v1/snapshot` |
| `vytrix_history` (`since`, `limit`) | `/v1/history` |
| `vytrix_anomalies` (`since`, `limit`) | `/v1/anomalies` |
| `vytrix_evidence` (`from`, `to`, `metric`) | `/v1/evidence` |
| `vytrix_timeline` (`from`, `to`, `threshold`) | `/v1/timeline` |
| `vytrix_changes` (`since`, `to`) | `/v1/changes` |

Times are epoch seconds. Responses are the collector's JSON, truncated at 200 KB with a note. If the collector is unreachable or rejects the token, the tool returns an error result with a short message and nothing else.

There is one prompt, `vytrix_triage`, and the server's instructions tell the model not to invent counters: a missing field was not measured, app memory is RSS, and evidence correlates without establishing a cause.

## What it does not do

It adds no data of its own and no new access: anything it returns is already available to someone holding the collector token. Treat the MCP client with the same care as the token, because a client that can call these tools can read your process names, paths and ports. See [SECURITY.md](../SECURITY.md).
