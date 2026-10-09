#!/usr/bin/env python3
# SPDX-License-Identifier: BUSL-1.1
"""Outbound, read-only cluster worker: pushes this Mac's snapshot to a coordinator. No command channel."""
import argparse
import getpass
import json
import os
import ssl
import time
import urllib.request
from pathlib import Path
from urllib.parse import urlsplit

from vytrix import Collector, ContainerProbe


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *_):
        raise ValueError('Coordinator redirects are forbidden')


def coordinator_url(raw):
    url = urlsplit(raw)
    if url.username or url.password or url.query or url.fragment or url.path not in ('', '/'):
        raise ValueError('Use coordinator origin without credentials, path or query')
    if url.scheme != 'https' and not (url.scheme == 'http' and url.hostname in ('localhost', '127.0.0.1', '::1')):
        raise ValueError('Remote coordinator requires HTTPS')
    return raw.rstrip('/')


def private_json(path):
    p = Path(path)
    if p.is_symlink() or p.stat().st_uid != os.getuid() or p.stat().st_mode & 0o077:
        raise ValueError('Config must be owned by current user, mode 0600, and not a symlink')
    return json.loads(p.read_text())


def write_private(path, data):
    with open(path, 'x', opener=lambda p, f: os.open(p, f, 0o600)) as out:
        json.dump(data, out, indent=2)


class Client:
    def __init__(self, origin, token='', ca=None):
        self.origin, self.token = coordinator_url(origin), token
        self.opener = urllib.request.build_opener(NoRedirect(), urllib.request.HTTPSHandler(context=ssl.create_default_context(cafile=ca)))

    def post(self, path, body):
        request = urllib.request.Request(self.origin + path, data=json.dumps(body).encode(), headers={'Content-Type': 'application/json', 'Authorization': 'Bearer ' + self.token}, method='POST')
        with self.opener.open(request, timeout=10) as reply:
            raw = reply.read(10 * 1024 * 1024 + 1)
            if len(raw) > 10 * 1024 * 1024:
                raise ValueError('Oversized coordinator response')
            return json.loads(raw)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', required=True)
    parser.add_argument('--enroll', metavar='COORDINATOR_ORIGIN')
    parser.add_argument('--ca', help='Private CA file; TLS verification is always enabled')
    parser.add_argument('--interval', type=float, default=2)
    args = parser.parse_args()
    os.umask(0o077)
    if args.enroll:
        client = Client(args.enroll, ca=args.ca)
        enrolled = client.post('/v1/enroll', {'code': getpass.getpass('Pairing code: ')})
        write_private(args.config, {'coordinator': client.origin, 'id': enrolled['id'], 'token': enrolled['token'], 'ca': args.ca})
        print('Enrolled. Device credential saved to private config; add this ID to scoped user permissions:', enrolled['id'])
        return
    if args.interval < 1 or args.interval > 60:
        parser.error('--interval must be 1–60 seconds')
    if os.getuid() == 0:
        parser.error('Run as the macOS user, never root')
    config = private_json(args.config)
    client = Client(config['coordinator'], config['token'], args.ca or config.get('ca'))
    probe = ContainerProbe()
    probe.start(5)
    collector = Collector(probe)
    collector.snapshot()
    while True:
        started = time.monotonic()
        try:
            client.post('/v1/heartbeat', {'snapshot': collector.snapshot()})
        except Exception:
            print('Coordinator unavailable; retrying.', flush=True)
        time.sleep(max(0.1, args.interval - (time.monotonic() - started)))


if __name__ == '__main__':
    main()
