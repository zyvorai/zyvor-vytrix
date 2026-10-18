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

## Use with Claude Code

The repository's `.mcp.json` registers the server for Claude Code. It carries no token: export `VYTRIX_TOKEN` in the shell that starts `claude`.

```bash
export VYTRIX_TOKEN=<collector token>
claude mcp list
```

To register it outside this repository:

```bash
claude mcp add vytrix -e VYTRIX_URL=http://127.0.0.1:9847 -- python3 /path/to/agent/vytrix_mcp.py
```

The project also ships a `/vytrix-triage [minutes]` slash command (`.claude/commands/`) and allows the `vytrix` server's read-only tools in `.claude/settings.json`.

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

### Cluster and Fleet Pro tools (optional)

Set `VYTRIX_CLUSTER_URL` (https, or http to localhost) and `VYTRIX_CLUSTER_TOKEN` to a coordinator and its token and four more tools appear. They are still one `GET` each and use the cluster token only for cluster paths; with neither variable set they do not exist.

| Tool | Coordinator endpoint |
|---|---|
| `vytrix_cluster` | `/v1/cluster` |
| `vytrix_fleet_history` (`node`) | `/v1/fleet/history` |
| `vytrix_fleet_alerts` | `/v1/fleet/alerts` (auditor role) |
| `vytrix_fleet_entitlement` | `/v1/fleet/entitlement` |

Audit, webhook and rule endpoints are deliberately not exposed: they need admin and can carry secrets. Use a `viewer` or `auditor` token, never `admin`.

### Resources

`vytrix://snapshot` and `vytrix://anomalies` can be attached as context (`resources/list`, `resources/read`). Each is one `GET` on the collector.

### Prompts

All take an optional `minutes` argument (1-1440, default 15): `vytrix_triage`, `vytrix_what_changed`, `vytrix_incident_report` and `vytrix_capacity_check`. The server's instructions tell the model not to invent counters: a missing field was not measured, app memory is RSS, and evidence correlates without establishing a cause.

## MCP Registry and the container image

`server.json` describes the server for the official [MCP Registry](https://registry.modelcontextprotocol.io) as `io.github.zyvorai/vytrix`. The package is an OCI image, `ghcr.io/zyvorai/vytrix-mcp:<version>`, built from `Dockerfile.mcp`: `python:3.12-slim`, only `agent/vytrix_mcp.py` copied in, no pip installs, running as a non-root user. An OCI image was chosen over PyPI because the server is one standard-library file that this repo does not otherwise publish to PyPI, and it needs no PyPI account or trusted-publisher setup.

```bash
docker run -i --rm \
  -e VYTRIX_URL=http://host.docker.internal:9847 \
  -e VYTRIX_TOKEN=<collector token> \
  ghcr.io/zyvorai/vytrix-mcp:0.8.0
```

The environment variables are the same two the script reads, `VYTRIX_URL` and `VYTRIX_TOKEN` (secret). Inside a container `127.0.0.1` is the container itself, so `VYTRIX_URL` must point at the collector explicitly, and plain HTTP is still accepted only for localhost, so a remote collector needs `https://`. The tool list is read-only. The optional cluster variables (`VYTRIX_CLUSTER_URL`, `VYTRIX_CLUSTER_TOKEN`) are not declared in `server.json`; add them with further `-e` flags to enable the cluster tools.

Releases: pushing a `v*` tag builds and pushes the image (`mcp-image` in `release.yml`), then `publish-mcp` validates `server.json` with a pinned `mcp-publisher` and publishes it using GitHub OIDC (`id-token: write`, no stored token). `scripts/check-version-sync.sh` (run in CI) fails when `server.json`, the image tag, the server's own version and the image label drift from `package.json`.

## What it does not do

It adds no data of its own and no new access: anything it returns is already available to someone holding the collector token. Treat the MCP client with the same care as the token, because a client that can call these tools can read your process names, paths and ports. See [SECURITY.md](../SECURITY.md).
