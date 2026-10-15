#!/usr/bin/env bash
# SPDX-License-Identifier: BUSL-1.1
# Vytrix MCP Registry version gate: server.json, the MCP server's own version
# and the OCI image label must agree with package.json (the release version).
# Usage: scripts/check-version-sync.sh
set -euo pipefail
cd "$(dirname "$0")/.."

ref=$(sed -n 's/^  "version": "\([^"]*\)".*/\1/p' package.json)
if [[ -z "$ref" ]]; then
  echo "check-version-sync: cannot read version from package.json" >&2
  exit 2
fi

fail=0
each() { # each <where> <file> <sed-expr>
  local where=$1 file=$2 expr=$3 found v
  found=$(sed -n "$expr" "$file")
  if [[ -z "$found" ]]; then
    echo "MISSING   $where: no match in $file" >&2
    fail=1
    return
  fi
  while IFS= read -r v; do
    if [[ "$v" != "$ref" ]]; then
      echo "MISMATCH  $where: '$v' (want '$ref')" >&2
      fail=1
    fi
  done <<<"$found"
}

each "agent/vytrix_mcp.py SERVER"  agent/vytrix_mcp.py "s/^SERVER = {'name': 'vytrix', 'version': '\([^']*\)'}\$/\1/p"
each "server.json version"         server.json          's/^  "version": "\([^"]*\)".*/\1/p'
each "server.json package tag"     server.json          's#.*"identifier": "ghcr.io/zyvorai/vytrix-mcp:\([^"]*\)".*#\1#p'

mcp_name=$(sed -n 's/^  "name": "\([^"]*\)".*/\1/p' server.json)
mcp_label=$(sed -n 's/^LABEL io.modelcontextprotocol.server.name="\([^"]*\)"$/\1/p' Dockerfile.mcp)
if [[ -z "$mcp_name" || "$mcp_name" != "$mcp_label" ]]; then
  echo "MISMATCH  Dockerfile.mcp label '$mcp_label' != server.json name '$mcp_name'" >&2
  fail=1
fi
desc_len=$(sed -n 's/^  "description": "\(.*\)",$/\1/p' server.json | awk '{print length($0)}')
if [[ -z "$desc_len" || "$desc_len" -gt 100 ]]; then
  echo "MISMATCH  server.json description is ${desc_len:-missing} chars (max 100)" >&2
  fail=1
fi

if [[ $fail -ne 0 ]]; then exit 1; fi
echo "check-version-sync: all MCP Registry locations at $ref"
