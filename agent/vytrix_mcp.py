#!/usr/bin/env python3
# SPDX-License-Identifier: BUSL-1.1
"""Vytrix MCP server: read-only tools over a running collector, on stdio.

Newline-delimited JSON-RPC 2.0 (the MCP stdio transport). Python 3.10+ standard library only.
Every tool is a GET against the collector's /v1 API; there is no tool that changes anything on the
host or in Vytrix, and none can be added without changing TOOLS below (tests/test_mcp.py asserts it).

    VYTRIX_URL=http://127.0.0.1:9847 VYTRIX_TOKEN=... python3 agent/vytrix_mcp.py

Optionally VYTRIX_CLUSTER_URL and VYTRIX_CLUSTER_TOKEN add read-only cluster/Fleet Pro tools.
Tokens come from the environment only, never from arguments, and are never printed.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

PROTOCOL = '2025-06-18'
SERVER = {'name': 'vytrix', 'version': '0.8.0'}
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

def _fleet_history(a): return '/v1/fleet/history?' + _query(a, ('node',))


# Only offered when VYTRIX_CLUSTER_URL and VYTRIX_CLUSTER_TOKEN are set. Also GET only; no audit, webhook or rule
# endpoints (those need admin and can carry secrets), and nothing that sends anything to a machine.
CLUSTER_TOOLS = {
    'vytrix_cluster': ('Every node in the cluster with its last snapshot and whether it is online.',
                       {'type': 'object', 'properties': {}, 'additionalProperties': False}, lambda a: '/v1/cluster'),
    'vytrix_fleet_history': ('Fleet Pro stored history, for all nodes or one.',
                             {'type': 'object', 'properties': {'node': {'type': 'string', 'description': 'Node id'}},
                              'additionalProperties': False}, _fleet_history),
    'vytrix_fleet_alerts': ('Fleet Pro alerts (needs the auditor role or above).',
                            {'type': 'object', 'properties': {}, 'additionalProperties': False}, lambda a: '/v1/fleet/alerts'),
    'vytrix_fleet_entitlement': ('Fleet Pro entitlement of this coordinator.',
                                 {'type': 'object', 'properties': {}, 'additionalProperties': False}, lambda a: '/v1/fleet/entitlement'),
}

# Resources a client can attach as context: name -> (description, collector path).
RESOURCES = {
    'vytrix://snapshot': ('The latest host snapshot.', '/v1/snapshot'),
    'vytrix://anomalies': ('Anomaly windows over stored history.', '/v1/anomalies'),
}

WINDOW = {'name': 'minutes', 'description': 'How far back to look, 1-1440 (default 15)', 'required': False}


def _minutes(args, default=15):
    try:
        return max(1, min(1440, int(args.get('minutes') or default)))
    except (TypeError, ValueError):
        return default


def _prompt_window(text):
    def build(args):
        minutes = _minutes(args)
        return text.format(minutes=minutes, seconds=minutes * 60) + ' ' + GUARD
    return build


PROMPTS = {
    'vytrix_triage': ('Triage the host: what is busy now, what changed recently, and what is unusual.', [WINDOW],
                      _prompt_window('Use vytrix_snapshot, then vytrix_timeline and vytrix_changes for the last {minutes} minutes '
                                     '(from = now - {seconds} epoch seconds). Summarise what is busy, what changed and what is anomalous.')),
    'vytrix_what_changed': ('List apps, ports and containers that started, stopped or appeared in a window.', [WINDOW],
                            _prompt_window('Call vytrix_changes with since = now - {seconds} epoch seconds. List what started, stopped, opened or '
                                           'closed, and mention the transient entries and the notes about short-lived processes.')),
    'vytrix_incident_report': ('Write a short incident report for a window from stored evidence.', [WINDOW],
                               _prompt_window('Call vytrix_timeline and vytrix_evidence (metric cpu, then memory, then network) for the last {minutes} '
                                              'minutes (from = now - {seconds}). Write a short report: timeline, top contributors, what changed, '
                                              'and what the data cannot tell you.')),
    'vytrix_capacity_check': ('Check headroom: CPU, memory, disk and network trends against recent history.', [WINDOW],
                              _prompt_window('Call vytrix_snapshot and vytrix_history (since = now - {seconds}, limit 300). Report current use, the trend '
                                             'over the window, and which resource has the least headroom. Say which fields were not measured.')),
}


def collector_url(raw):
    """Plain HTTP only to loopback, like the dashboard and the native app."""
    url = urllib.parse.urlparse(raw)
    loopback = url.hostname in ('localhost', '127.0.0.1', '::1')
    if url.scheme == 'https' or (url.scheme == 'http' and loopback):
        return raw.rstrip('/')
    raise ValueError('VYTRIX_URL must be https://, or http:// to localhost')


class Server:
    def __init__(self, base, token, opener=None, cluster=None):
        self.base = base
        self.token = token
        self.cluster = cluster   # (url, token) or None
        self.opener = opener or urllib.request.build_opener(urllib.request.ProxyHandler({}))
        self.tools = dict(TOOLS, **(CLUSTER_TOOLS if cluster else {}))

    def fetch(self, path):
        base, token = self.base, self.token
        if self.cluster and path.startswith(('/v1/cluster', '/v1/fleet')):
            base, token = self.cluster
        request = urllib.request.Request(base + path, headers={'Authorization': 'Bearer ' + token})
        try:
            with self.opener.open(request, timeout=10) as response:
                return json.load(response)
        except urllib.error.HTTPError as e:
            raise RuntimeError(f'The collector answered HTTP {e.code}.') from None
        except (urllib.error.URLError, OSError, ValueError):
            raise RuntimeError('The collector is not reachable or returned invalid data.') from None

    def call_tool(self, name, arguments):
        if name not in self.tools:
            raise KeyError(name)
        schema, build = self.tools[name][1], self.tools[name][2]
        arguments = arguments or {}
        unknown = set(arguments) - set(schema['properties'])
        missing = [k for k in schema.get('required', []) if k not in arguments]
        if unknown or missing:
            raise ValueError('Unexpected arguments: %s; missing: %s' % (sorted(unknown), missing))
        for key, value in arguments.items():
            kind = schema['properties'][key].get('type')
            if kind in ('number', 'integer') and (isinstance(value, bool) or not isinstance(value, (int, float))):
                raise ValueError(f'{key} must be a number')
            if kind == 'string' and not isinstance(value, str):
                raise ValueError(f'{key} must be a string')
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
                           'capabilities': {'tools': {}, 'prompts': {}, 'resources': {}}, 'instructions': GUARD})
        if method == 'ping':
            return result({})
        if method == 'tools/list':
            return result({'tools': [{'name': n, 'description': d, 'inputSchema': s, 'annotations': {'readOnlyHint': True}}
                                     for n, (d, s, _) in self.tools.items()]})
        if method == 'tools/call':
            name = params.get('name')
            if name not in self.tools:
                return error(-32602, f'Unknown tool: {name}')
            try:
                return result({'content': [{'type': 'text', 'text': self.call_tool(name, params.get('arguments'))}]})
            except ValueError as e:
                return error(-32602, str(e))
            except RuntimeError as e:
                return result({'content': [{'type': 'text', 'text': str(e)}], 'isError': True})
        if method == 'prompts/list':
            return result({'prompts': [{'name': n, 'description': d, 'arguments': a} for n, (d, a, _) in PROMPTS.items()]})
        if method == 'prompts/get':
            name = params.get('name')
            if name not in PROMPTS:
                return error(-32602, f'Unknown prompt: {name}')
            return result({'description': PROMPTS[name][0],
                           'messages': [{'role': 'user', 'content': {'type': 'text', 'text': PROMPTS[name][2](params.get('arguments') or {})}}]})
        if method == 'resources/list':
            return result({'resources': [{'uri': u, 'name': u.split('//')[1], 'description': d, 'mimeType': 'application/json'}
                                         for u, (d, _) in RESOURCES.items()]})
        if method == 'resources/read':
            uri = params.get('uri')
            if uri not in RESOURCES:
                return error(-32602, f'Unknown resource: {uri}')
            try:
                text = json.dumps(self.fetch(RESOURCES[uri][1]), indent=2)[:MAX_TEXT]
            except RuntimeError as e:
                return error(-32603, str(e))
            return result({'contents': [{'uri': uri, 'mimeType': 'application/json', 'text': text}]})
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
    cluster = None
    if os.environ.get('VYTRIX_CLUSTER_URL') or os.environ.get('VYTRIX_CLUSTER_TOKEN'):
        try:
            cluster_token = os.environ.get('VYTRIX_CLUSTER_TOKEN', '')
            if not cluster_token:
                raise ValueError('Set VYTRIX_CLUSTER_TOKEN together with VYTRIX_CLUSTER_URL.')
            cluster = (collector_url(os.environ.get('VYTRIX_CLUSTER_URL', '')), cluster_token)
        except ValueError as e:
            print(str(e), file=sys.stderr)
            return 2
    serve(Server(base, token, cluster=cluster))
    return 0


if __name__ == '__main__':
    sys.exit(main())
