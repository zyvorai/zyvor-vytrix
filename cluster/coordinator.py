#!/usr/bin/env python3
# SPDX-License-Identifier: BUSL-1.1
"""Opt-in, read-only cluster telemetry coordinator. Python standard library only.

Workers push snapshots; viewers read them. There is no command channel: the coordinator cannot start,
stop or change anything on a monitored Mac."""
import argparse
import datetime as dt
import getpass
import hashlib
import hmac
import json
import math
import os
import secrets
import sqlite3
import ssl
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

MAX_BODY = 10 * 1024 * 1024
SESSION_TTL = 8 * 3600
STALE_AFTER = 15


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


def password_hash(password, salt=None):
    if len(password) < 12 or len(password) > 1024:
        raise ValueError('Password must contain 12–1024 characters')
    salt = salt or secrets.token_hex(16)
    return salt + ':' + hashlib.pbkdf2_hmac('sha256', password.encode(), salt.encode(), 600000).hex()


def verify_password(password, stored):
    try:
        salt, expected = stored.split(':')
        actual = hashlib.pbkdf2_hmac('sha256', password.encode(), salt.encode(), 600000).hex()
        return hmac.compare_digest(actual, expected)
    except (ValueError, AttributeError):
        return False


class APIError(Exception):
    def __init__(self, status, message):
        self.status, self.message = status, message


def text(value, limit=128):
    if not isinstance(value, str) or not value or len(value) > limit:
        raise APIError(400, 'Invalid string field')
    return value


def validate_snapshot(s):
    """Mirror browser telemetry bounds so one bad agent cannot poison a fleet view."""
    def require(condition):
        if not condition:
            raise APIError(400, 'Invalid snapshot')

    def metric(v, positive=False, maximum=None):
        require(type(v) in (int, float) and math.isfinite(v) and v >= 0)
        require(not positive or v > 0)
        require(maximum is None or v <= maximum)

    def integer(v, low, high=None):
        require(type(v) is int and v >= low and (high is None or v <= high))

    def array(v, maximum):
        require(isinstance(v, list) and len(v) <= maximum)
        return v

    def string(v, maximum, nullable=False):
        require(nullable and v is None or isinstance(v, str) and len(v) <= maximum)

    try:
        require(type(s['version']) is int and s['version'] == 1)
        stamp = dt.datetime.fromisoformat(text(s['timestamp'], 64).replace('Z', '+00:00'))
        require(stamp.tzinfo is not None)
        string(s['host']['name'], 256)
        string(s['host']['os'], 256)
        integer(s['host']['cores'], 1)
        for key in ('cpu', 'memoryUsed', 'diskUsed', 'download', 'upload'):
            metric(s[key])
        metric(s['host']['memoryTotal'], positive=True)
        metric(s['diskTotal'], positive=True)
        require(s['cpu'] <= 100 and s['memoryUsed'] <= s['host']['memoryTotal'] and s['diskUsed'] <= s['diskTotal'])
        if s['battery'] is not None:
            metric(s['battery'], maximum=100)
        for p in array(s['processes'], 20000):
            integer(p['pid'], 1)
            string(p['name'], 256)
            string(p['app'], 256)
            metric(p['cpu'])
            metric(p['memory'])
            string(p['project'], 256, nullable=True)
            for port in array(p['ports'], 256):
                integer(port, 1, 65535)
        for c in array(s.get('containers', []), 2000):
            require(c['runtime'] in ('docker', 'podman'))
            text(c['id'], 128)
            for key, limit in [('name', 256), ('image', 512), ('state', 64)]:
                string(c[key], limit)
            for key in ('cpu', 'memory', 'netIn', 'netOut'):
                metric(c[key])
            if c['memoryLimit'] is not None:
                metric(c['memoryLimit'])
            for port in array(c['ports'], 256):
                if port['hostPort'] is not None:
                    integer(port['hostPort'], 1, 65535)
                integer(port['containerPort'], 1, 65535)
                require(port['protocol'] in ('tcp', 'udp', 'sctp'))
        for r in array(s.get('runtimes', []), 8):
            require(r['name'] in ('docker', 'podman') and type(r['available']) is bool)
            string(r['error'], 256, nullable=True)
    except (KeyError, TypeError, AssertionError, ValueError, AttributeError):
        raise APIError(400, 'Invalid snapshot') from None

class Cluster:
    def __init__(self, database, users, clock=time.time):
        self.clock, self.users = clock, users
        self.lock = threading.RLock()
        self.db = sqlite3.connect(database, check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.db.executescript('''
        PRAGMA journal_mode=WAL;
        CREATE TABLE IF NOT EXISTS sessions(token TEXT PRIMARY KEY, actor TEXT, expires REAL);
        CREATE TABLE IF NOT EXISTS pairings(code TEXT PRIMARY KEY, name TEXT, expires REAL);
        CREATE TABLE IF NOT EXISTS nodes(id TEXT PRIMARY KEY, name TEXT, token TEXT UNIQUE, seen REAL DEFAULT 0, snapshot TEXT, revoked INTEGER DEFAULT 0);
        CREATE TABLE IF NOT EXISTS audit(id INTEGER PRIMARY KEY, at REAL, actor TEXT, event TEXT, detail TEXT);
        ''')
        self.attempts = {}
        for user in users.values():
            if user.get('role') not in ('viewer', 'admin') or not isinstance(user.get('nodes'), list):
                raise ValueError('Each user needs role and nodes (IDs or ["*"])')

    def audit(self, actor, event, detail):
        self.db.execute('INSERT INTO audit(at,actor,event,detail) VALUES(?,?,?,?)', (self.clock(), actor, event, json.dumps(detail)))

    def expire(self):
        now = self.clock()
        self.db.execute('DELETE FROM sessions WHERE expires<?', (now,))
        self.db.execute('DELETE FROM pairings WHERE expires<?', (now,))
        # Retain bounded audit history.
        cutoff = now - 30 * 86400
        self.db.execute('DELETE FROM audit WHERE at<?', (cutoff,))

    def login(self, username, password, address):
        text(username)
        text(password, 1024)
        now = self.clock()
        self.attempts = {k: v for k, v in self.attempts.items() if now - v[0] < 60}
        if address not in self.attempts and len(self.attempts) >= 10000:
            raise APIError(429, 'Login temporarily limited')
        start, count = self.attempts.get(address, (now, 0))
        self.attempts[address] = (start, count + 1)
        if count >= 10:
            raise APIError(429, 'Too many login attempts; wait one minute')
        user = self.users.get(username)
        # Same expensive KDF even for an unknown username.
        stored = user['password'] if user else '0' * 32 + ':' + '0' * 64
        if not verify_password(password, stored) or not user:
            raise APIError(401, 'Invalid credentials')
        token = secrets.token_urlsafe(32)
        self.db.execute('INSERT INTO sessions VALUES(?,?,?)', (digest(token), username, now + SESSION_TTL))
        self.audit(username, 'login', {})
        return {'token': token, 'expires': now + SESSION_TTL, 'actor': username, 'role': user['role']}

    def principal(self, token):
        row = self.db.execute('SELECT actor FROM sessions WHERE token=? AND expires>?', (digest(token), self.clock())).fetchone()
        if not row or row['actor'] not in self.users:
            raise APIError(401, 'Session expired or invalid')
        return row['actor'], self.users[row['actor']]

    @staticmethod
    def allowed(user, node):
        return '*' in user['nodes'] or node in user['nodes']

    def node(self, token):
        row = self.db.execute('SELECT * FROM nodes WHERE token=? AND revoked=0', (digest(token),)).fetchone()
        if not row:
            raise APIError(401, 'Device credential invalid or revoked')
        return row

    def nodes(self, user):
        rows = self.db.execute('SELECT * FROM nodes WHERE revoked=0 ORDER BY name').fetchall()
        return [{'id': r['id'], 'name': r['name'], 'seen': r['seen'], 'online': r['seen'] > 0 and self.clock() - r['seen'] <= STALE_AFTER,
                 'snapshot': json.loads(r['snapshot']) if r['snapshot'] else None} for r in rows if self.allowed(user, r['id'])]

    def pair(self, actor, user, name):
        if user['role'] != 'admin':
            raise APIError(403, 'Administrator required')
        code = secrets.token_urlsafe(24)
        self.db.execute('INSERT INTO pairings VALUES(?,?,?)', (digest(code), text(name), self.clock() + 300))
        self.audit(actor, 'pairing-created', {'name': name})
        return {'code': code, 'expires': self.clock() + 300}

    def enroll(self, code):
        row = self.db.execute('SELECT * FROM pairings WHERE code=? AND expires>?', (digest(text(code)), self.clock())).fetchone()
        if not row:
            raise APIError(401, 'Pairing code expired or already used')
        node_id, token = str(uuid.uuid4()), secrets.token_urlsafe(32)
        self.db.execute('INSERT INTO nodes(id,name,token) VALUES(?,?,?)', (node_id, row['name'], digest(token)))
        self.db.execute('DELETE FROM pairings WHERE code=?', (digest(code),))
        self.audit(node_id, 'enrolled', {'name': row['name']})
        return {'id': node_id, 'token': token}

    def heartbeat(self, token, body):
        node = self.node(token)
        validate_snapshot(body.get('snapshot'))
        self.db.execute('UPDATE nodes SET seen=?,snapshot=? WHERE id=?', (self.clock(), json.dumps(body['snapshot']), node['id']))
        return {'ok': True}

    def dispatch(self, method, path, token, body, address='local'):
        with self.lock:
            try:
                with self.db:
                    self.expire()
                    return self.route(method, path, token, body, address)
            except APIError as error:
                if error.status in (401, 403):
                    with self.db:
                        self.audit('anonymous', 'request-denied', {'path': path, 'status': error.status})
                raise

    def route(self, method, path, token, body, address):
        if method == 'POST' and path == '/v1/login':
            return self.login(body.get('username'), body.get('password'), address)
        if method == 'POST' and path == '/v1/enroll':
            return self.enroll(body.get('code'))
        if method == 'POST' and path == '/v1/heartbeat':
            return self.heartbeat(token, body)
        actor, user = self.principal(token)
        if method == 'POST' and path == '/v1/logout':
            self.db.execute('DELETE FROM sessions WHERE token=?', (digest(token),))
            return {'ok': True}
        if method == 'GET' and path == '/v1/cluster':
            return {'version': 1, 'actor': actor, 'role': user['role'], 'nodes': self.nodes(user)}
        if method == 'POST' and path == '/v1/pairings':
            return self.pair(actor, user, body.get('name'))
        if method == 'POST' and path == '/v1/revoke':
            if user['role'] != 'admin':
                raise APIError(403, 'Administrator required')
            node_id = text(body.get('node'))
            if not self.allowed(user, node_id):
                raise APIError(403, 'Machine outside your permissions')
            self.db.execute('UPDATE nodes SET revoked=1 WHERE id=?', (node_id,))
            self.audit(actor, 'node-revoked', {'node': node_id})
            return {'ok': True}
        if method == 'GET' and path == '/v1/audit':
            if user['role'] != 'admin' or '*' not in user['nodes']:
                raise APIError(403, 'Global administrator required for audit history')
            return {'events': [dict(r) for r in self.db.execute('SELECT * FROM audit ORDER BY id DESC LIMIT 200')]}
        raise APIError(404, 'Unknown cluster endpoint')


class Server(ThreadingHTTPServer):
    daemon_threads = True
    def __init__(self, address, cluster, origins):
        super().__init__(address, Handler)
        self.cluster, self.origins = cluster, set(origins)


class Handler(BaseHTTPRequestHandler):
    def setup(self):
        super().setup()
        self.connection.settimeout(10)

    def log_message(self, *_):
        pass  # Never log credentials, pairing codes or telemetry.

    def reply(self, status, data):
        raw = json.dumps(data, allow_nan=False).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(raw)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        origin = self.headers.get('Origin')
        if origin in self.server.origins:
            self.send_header('Access-Control-Allow-Origin', origin)
            self.send_header('Vary', 'Origin')
        self.end_headers()
        self.wfile.write(raw)

    def do_OPTIONS(self):
        if self.headers.get('Origin') not in self.server.origins:
            return self.reply(403, {'error': 'Origin denied'})
        self.send_response(204)
        self.send_header('Access-Control-Allow-Origin', self.headers['Origin'])
        self.send_header('Access-Control-Allow-Headers', 'Authorization, Content-Type')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Vary', 'Origin')
        self.end_headers()

    def handle_api(self, method):
        try:
            origin = self.headers.get('Origin')
            if origin is not None and origin not in self.server.origins:
                raise APIError(403, 'Origin denied')
            path = urlsplit(self.path).path
            if method == 'GET' and path == '/healthz':
                return self.reply(200, {'status': 'ok'})
            body = {}
            if method == 'POST':
                size = int(self.headers.get('Content-Length', '0'))
                if not 0 < size <= MAX_BODY:
                    raise APIError(413, 'Body exceeds limit or is empty')
                body = json.loads(self.rfile.read(size))
                if not isinstance(body, dict):
                    raise APIError(400, 'Expected JSON object')
            token = self.headers.get('Authorization', '').removeprefix('Bearer ')
            result = self.server.cluster.dispatch(method, path, token, body, self.client_address[0])
            self.reply(200, result)
        except APIError as e:
            self.reply(e.status, {'error': e.message})
        except (ValueError, TypeError, KeyError):
            self.reply(400, {'error': 'Invalid request'})
        except Exception:
            self.reply(500, {'error': 'Coordinator error'})

    def do_GET(self):
        self.handle_api('GET')

    def do_POST(self):
        self.handle_api('POST')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--init-user', help='Print a user config entry; password read privately')
    p.add_argument('--role', choices=['admin', 'viewer'], default='admin')
    p.add_argument('--config')
    p.add_argument('--database', default='cluster.sqlite')
    p.add_argument('--bind', default='127.0.0.1')
    p.add_argument('--port', type=int, default=9848)
    p.add_argument('--allow-origin', action='append', default=[])
    p.add_argument('--tls-cert')
    p.add_argument('--tls-key')
    args = p.parse_args()
    if args.init_user:
        print(json.dumps({args.init_user: {'password': password_hash(getpass.getpass('Password (12+ characters): ')), 'role': args.role, 'nodes': ['*']}}, indent=2))
        return
    if not args.config:
        p.error('--config required')
    if bool(args.tls_cert) != bool(args.tls_key) or (args.bind not in ('127.0.0.1', '::1', 'localhost') and not args.tls_cert):
        p.error('Remote listener requires --tls-cert and --tls-key')
    os.umask(0o077)
    config = Path(args.config)
    if config.stat().st_mode & 0o077:
        p.error('Config permissions must be 0600')
    cluster = Cluster(args.database, json.loads(config.read_text()))
    os.chmod(args.database, 0o600)
    server = Server((args.bind, args.port), cluster, args.allow_origin)
    if args.tls_cert:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(args.tls_cert, args.tls_key)
        server.socket = context.wrap_socket(server.socket, server_side=True)
    print(f'Vytrix cluster coordinator on {args.bind}:{args.port}', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        cluster.db.close()


if __name__ == '__main__':
    main()
