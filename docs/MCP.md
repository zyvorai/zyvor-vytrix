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

## MCP Registry and the container image

`server.json` describes the server for the official [MCP Registry](https://registry.modelcontextprotocol.io) as `io.github.zyvorai/vytrix`. The package is an OCI image, `ghcr.io/zyvorai/vytrix-mcp:<version>`, built from `Dockerfile.mcp`: `python:3.12-slim`, only `agent/vytrix_mcp.py` copied in, no pip installs, running as a non-root user. An OCI image was chosen over PyPI because the server is one standard-library file that this repo does not otherwise publish to PyPI, and it needs no PyPI account or trusted-publisher setup.

```bash
docker run -i --rm \
  -e VYTRIX_URL=http://host.docker.internal:9847 \
  -e VYTRIX_TOKEN=<collector token> \
  ghcr.io/zyvorai/vytrix-mcp:0.7.0
```

The environment variables are the same two the script reads, `VYTRIX_URL` and `VYTRIX_TOKEN` (secret). Inside a container `127.0.0.1` is the container itself, so `VYTRIX_URL` must point at the collector explicitly, and plain HTTP is still accepted only for localhost, so a remote collector needs `https://`. The tool list is unchanged and read-only.

Releases: pushing a `v*` tag builds and pushes the image (`mcp-image` in `release.yml`), then `publish-mcp` validates `server.json` with a pinned `mcp-publisher` and publishes it using GitHub OIDC (`id-token: write`, no stored token). `scripts/check-version-sync.sh` (run in CI) fails when `server.json`, the image tag, the server's own version and the image label drift from `package.json`.

## What it does not do

It adds no data of its own and no new access: anything it returns is already available to someone holding the collector token. Treat the MCP client with the same care as the token, because a client that can call these tools can read your process names, paths and ports. See [SECURITY.md](../SECURITY.md).
