#!/usr/bin/env python3
# SPDX-License-Identifier: BUSL-1.1
"""Vytrix MCP server: read-only tools over a running collector, on stdio.

Newline-delimited JSON-RPC 2.0 (the MCP stdio transport). Python 3.10+ standard library only.
Every tool is a GET against the collector's /v1 API; there is no tool that changes anything on the
host or in Vytrix, and none can be added without changing TOOLS below (tests/test_mcp.py asserts it).

    VYTRIX_URL=http://127.0.0.1:9847 VYTRIX_TOKEN=... python3 agent/vytrix_mcp.py

The token comes from the environment only, never from arguments, and is never printed.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

PROTOCOL = '2025-06-18'
SERVER = {'name': 'vytrix', 'version': '0.6.0'}
MAX_TEXT = 200_000
GUARD = ('Report only what the data shows. Do not invent counters: a missing field means the collector '
         'did not measure it. App memory is RSS. Evidence correlates; it does not establish a cause.')


def num(schema_type='number', description='', **extra):
    return {'type': schema_type, 'description': description, **extra}


def _query(args, names):
    return urllib.parse.urlencode({k: args[k] for k in names if args.get(k) is not None})


def _history(a): return '/v1/history?' + _query(a, ('since', 'limit'))
def _anomalies(a): return '/v1/anomalies?' + _query(a, ('since', 'limit'))
def _evidence(a): return '/v1/evidence?' + _query(a, ('from', 'to', 'metric'))
def _timeline(a): return '/v1/timeline?' + _query(a, ('from', 'to', 'threshold'))
def _changes(a): return '/v1/changes?' + _query(a, ('since', 'to'))


# name -> (description, input schema, path builder). All GET; this table is the whole attack surface.
TOOLS = {
    'vytrix_snapshot': ('The latest host snapshot: CPU, memory, disk, network, battery, processes and containers.',
                        {'type': 'object', 'properties': {}, 'additionalProperties': False}, lambda a: '/v1/snapshot'),
    'vytrix_history': ('Stored samples in chronological order.',
                       {'type': 'object', 'properties': {'since': num(description='Epoch seconds'), 'limit': num('integer', 'Samples, 1-1000', minimum=1, maximum=1000)},
                        'additionalProperties': False}, _history),
    'vytrix_anomalies': ('Statistical anomaly scores and windows over stored history. Warm-up samples are null.',
                         {'type': 'object', 'properties': {'since': num(description='Epoch seconds'), 'limit': num('integer', 'Samples, 1-1000', minimum=1, maximum=1000)},
                          'additionalProperties': False}, _anomalies),
    'vytrix_evidence': ('What was busy in a time range, against the range before it.',
                        {'type': 'object', 'properties': {'from': num(description='Epoch seconds'), 'to': num(description='Epoch seconds'),
                                                          'metric': {'type': 'string', 'enum': ['cpu', 'memory', 'network']}},
                         'required': ['from', 'to'], 'additionalProperties': False}, _evidence),
    'vytrix_timeline': ('Alert transitions, anomaly windows and container changes in a range, with a fingerprint and what changed since the range before.',
                        {'type': 'object', 'properties': {'from': num(description='Epoch seconds'), 'to': num(description='Epoch seconds'),
                                                          'threshold': num(description='Alert threshold percent, 1-100')},
                         'required': ['from', 'to'], 'additionalProperties': False}, _timeline),
    'vytrix_changes': ('Apps, ports and containers that appeared or went away between the first and last sample of a range.',
                       {'type': 'object', 'properties': {'since': num(description='Epoch seconds'), 'to': num(description='Epoch seconds')},
                        'required': ['since'], 'additionalProperties': False}, _changes),
}

PROMPTS = {
    'vytrix_triage': ('Triage the host: what is busy now, what changed recently, and what is unusual.',
                      lambda: 'Use vytrix_snapshot, then vytrix_timeline and vytrix_changes for the last 15 minutes '
                              '(from = now - 900 epoch seconds). Summarise what is busy, what changed and what is anomalous. '
                              + GUARD),
}


def collector_url(raw):
    """Plain HTTP only to loopback, like the dashboard and the native app."""
    url = urllib.parse.urlparse(raw)
    loopback = url.hostname in ('localhost', '127.0.0.1', '::1')
    if url.scheme == 'https' or (url.scheme == 'http' and loopback):
        return raw.rstrip('/')
    raise ValueError('VYTRIX_URL must be https://, or http:// to localhost')


class Server:
    def __init__(self, base, token, opener=None):
        self.base = base
        self.token = token
        self.opener = opener or urllib.request.build_opener(urllib.request.ProxyHandler({}))

    def fetch(self, path):
        request = urllib.request.Request(self.base + path, headers={'Authorization': 'Bearer ' + self.token})
        try:
            with self.opener.open(request, timeout=10) as response:
                return json.load(response)
        except urllib.error.HTTPError as e:
            raise RuntimeError(f'The collector answered HTTP {e.code}.') from None
        except (urllib.error.URLError, OSError, ValueError):
            raise RuntimeError('The collector is not reachable or returned invalid data.') from None

    def call_tool(self, name, arguments):
        if name not in TOOLS:
            raise KeyError(name)
        schema, build = TOOLS[name][1], TOOLS[name][2]
        arguments = arguments or {}
        unknown = set(arguments) - set(schema['properties'])
        missing = [k for k in schema.get('required', []) if k not in arguments]
        if unknown or missing:
            raise ValueError('Unexpected arguments: %s; missing: %s' % (sorted(unknown), missing))
        for key, value in arguments.items():
            if schema['properties'][key].get('type') in ('number', 'integer') and (isinstance(value, bool) or not isinstance(value, (int, float))):
                raise ValueError(f'{key} must be a number')
        text = json.dumps(self.fetch(build(arguments)), indent=2)
        if len(text) > MAX_TEXT:
            text = text[:MAX_TEXT] + '\n[truncated: ask for a smaller range or limit]'
        return text

    def handle(self, message):
        """One JSON-RPC message in, one response out (None for notifications)."""
        method, ident, params = message.get('method'), message.get('id'), message.get('params') or {}
        def result(value): return {'jsonrpc': '2.0', 'id': ident, 'result': value}
        def error(code, text): return {'jsonrpc': '2.0', 'id': ident, 'error': {'code': code, 'message': text}}
        if ident is None:
            return None   # notifications (initialized, cancelled) need no reply
        if method == 'initialize':
            return result({'protocolVersion': PROTOCOL, 'serverInfo': SERVER,
                           'capabilities': {'tools': {}, 'prompts': {}}, 'instructions': GUARD})
        if method == 'ping':
            return result({})
        if method == 'tools/list':
            return result({'tools': [{'name': n, 'description': d, 'inputSchema': s, 'annotations': {'readOnlyHint': True}}
                                     for n, (d, s, _) in TOOLS.items()]})
        if method == 'tools/call':
            name = params.get('name')
            if name not in TOOLS:
                return error(-32602, f'Unknown tool: {name}')
            try:
                return result({'content': [{'type': 'text', 'text': self.call_tool(name, params.get('arguments'))}]})
            except ValueError as e:
                return error(-32602, str(e))
            except RuntimeError as e:
                return result({'content': [{'type': 'text', 'text': str(e)}], 'isError': True})
        if method == 'prompts/list':
            return result({'prompts': [{'name': n, 'description': d} for n, (d, _) in PROMPTS.items()]})
        if method == 'prompts/get':
            name = params.get('name')
            if name not in PROMPTS:
                return error(-32602, f'Unknown prompt: {name}')
            return result({'description': PROMPTS[name][0],
                           'messages': [{'role': 'user', 'content': {'type': 'text', 'text': PROMPTS[name][1]()}}]})
        return error(-32601, f'Method not found: {method}')


def serve(server, stdin=sys.stdin, stdout=sys.stdout):
    for line in stdin:
        line = line.strip()
        if not line:
            continue
        try:
            message = json.loads(line)
            if not isinstance(message, dict):
                raise ValueError()
        except ValueError:
            reply = {'jsonrpc': '2.0', 'id': None, 'error': {'code': -32700, 'message': 'Parse error'}}
        else:
            reply = server.handle(message)
        if reply is not None:
            stdout.write(json.dumps(reply) + '\n')
            stdout.flush()


def main():
    token = os.environ.get('VYTRIX_TOKEN', '')
    if not token:
        print('Set VYTRIX_TOKEN (and optionally VYTRIX_URL, default http://127.0.0.1:9847).', file=sys.stderr)
        return 2
    try:
        base = collector_url(os.environ.get('VYTRIX_URL', 'http://127.0.0.1:9847'))
    except ValueError as e:
        print(str(e), file=sys.stderr)
        return 2
    serve(Server(base, token))
    return 0


if __name__ == '__main__':
    sys.exit(main())
