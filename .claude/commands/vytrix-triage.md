---
description: Triage the monitored host through the Vytrix MCP server
argument-hint: [minutes]
allowed-tools: mcp__vytrix__vytrix_snapshot, mcp__vytrix__vytrix_timeline, mcp__vytrix__vytrix_changes
---

Triage the host for the last $ARGUMENTS minutes (15 if empty) with the vytrix MCP tools: `vytrix_snapshot`, then `vytrix_timeline` and `vytrix_changes` (from = now minus that many seconds). Summarise what is busy, what changed and what is anomalous.

Report only what the data shows. A missing field was not measured, app memory is RSS, and evidence correlates without establishing a cause. This is read-only: do not suggest the tool can change anything on the host.
