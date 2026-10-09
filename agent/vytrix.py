#!/usr/bin/env python3
# SPDX-License-Identifier: BUSL-1.1
"""Read-only Linux/macOS telemetry collector. Python 3.10+, no dependencies."""
import argparse
import datetime as dt
import hmac
import json
import os
from pathlib import Path
import platform
import re
import shutil
import sqlite3
import ssl
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import urllib.error
import urllib.request
from urllib.parse import parse_qs, urlparse

VERSION = 1

def command(args, timeout=3):
    try:
        return subprocess.check_output(args, text=True, timeout=timeout, stderr=subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError):
        return ''

def app_name(name):
    match = re.search(r'/([^/]+)\.app/', name)
    if match:
        return match.group(1)
    name = Path(name).name
    for base in ['chrome', 'chromium', 'firefox', 'code']:
        if name.lower().startswith(base):
            return {'chrome':'Google Chrome','chromium':'Chromium','firefox':'Firefox','code':'Visual Studio Code'}[base]
    return name or 'Unknown'

SIZE_UNITS = {'b':1,'kb':1000,'mb':1000**2,'gb':1000**3,'tb':1000**4,'kib':1024,'mib':1024**2,'gib':1024**3,'tib':1024**4}

def parse_size(text):
    match = re.match(r'\s*([\d.]+)\s*([a-zA-Z]*)', text or '')
    if not match:
        return 0.0
    unit = match.group(2).lower() or 'b'
    if unit == 'k': unit = 'kb'
    return float(match.group(1)) * SIZE_UNITS.get(unit, 1)

def parse_pair(text):
    """'9.2MiB / 7.6GiB' -> (bytes, bytes)."""
    left, _, right = (text or '').partition('/')
    return parse_size(left), parse_size(right)

def parse_percent(text):
    try:
        return max(0.0, float(str(text).strip().rstrip('%') or 0))
    except ValueError:
        return 0.0

def expand_ports(first, last, limit=64):
    first, last = int(first), int(last or first)
    return range(first, min(last, first+limit-1)+1)

def parse_docker_ports(text):
    """Docker `ps` Ports column, e.g. '0.0.0.0:8080->80/tcp, :::8080->80/tcp, 9000/udp'."""
    seen, ports = set(), []
    for entry in (text or '').split(','):
        entry = entry.strip()
        mapped = re.search(r':(\d+)(?:-(\d+))?->(\d+)(?:-(\d+))?/(\w+)$', entry)
        bare = re.fullmatch(r'(\d+)(?:-(\d+))?/(\w+)', entry)
        pairs = []
        if mapped:
            hosts = expand_ports(mapped.group(1), mapped.group(2))
            inner = expand_ports(mapped.group(3), mapped.group(4))
            pairs = [(h, c, mapped.group(5)) for h, c in zip(hosts, inner)]
        elif bare:
            pairs = [(None, c, bare.group(3)) for c in expand_ports(bare.group(1), bare.group(2))]
        for pair in pairs:
            if pair not in seen and pair[2] in ('tcp','udp','sctp'):
                seen.add(pair)
                ports.append(dict(hostPort=pair[0], containerPort=pair[1], protocol=pair[2]))
    return ports

def parse_podman_ports(items):
    seen, ports = set(), []
    for item in items or []:
        try:
            count = max(1, int(item.get('range') or 1))
            host = item.get('host_port') or 0
            inner = int(item['container_port'])
            protocol = (item.get('protocol') or 'tcp').lower()
        except (KeyError, TypeError, ValueError):
            continue
        for offset in range(min(count, 64)):
            pair = (host+offset if host else None, inner+offset, protocol)
            if pair not in seen and protocol in ('tcp','udp','sctp'):
                seen.add(pair)
                ports.append(dict(hostPort=pair[0], containerPort=pair[1], protocol=protocol))
    return ports

def lower_keys(row):
    return {str(k).lower(): v for k, v in row.items()} if isinstance(row, dict) else {}

def json_rows(text):
    """Accept a JSON array or newline-delimited JSON objects."""
    text = (text or '').strip()
    if not text:
        return []
    try:
        data = json.loads(text)
        return [lower_keys(r) for r in (data if isinstance(data, list) else [data])]
    except ValueError:
        rows = []
        for line in text.splitlines():
            try:
                rows.append(lower_keys(json.loads(line)))
            except ValueError:
                continue
        return rows

def container_row(runtime, info, stats):
    ident = str(info.get('id') or stats.get('id') or stats.get('container') or '')
    names = info.get('names') or stats.get('name') or ''
    name = (names[0] if isinstance(names, list) and names else str(names)).lstrip('/')
    state = str(info.get('state') or ('running' if stats else 'unknown')).lower()
    memory, limit = parse_pair(stats.get('memusage') or stats.get('mem_usage') or '')
    net_in, net_out = parse_pair(stats.get('netio') or stats.get('net_io') or '')
    if runtime == 'docker':
        ports = parse_docker_ports(info.get('ports') if isinstance(info.get('ports'), str) else '')
    else:
        ports = parse_podman_ports(info.get('ports'))
    return dict(runtime=runtime, id=ident[:64], name=name[:256], image=str(info.get('image') or '')[:512], state=state[:64],
                cpu=round(parse_percent(stats.get('cpuperc') or stats.get('cpu_percent') or stats.get('cpu') or 0), 2) if state == 'running' else 0.0,
                memory=memory if state == 'running' else 0.0, memoryLimit=limit or None, netIn=net_in, netOut=net_out, ports=ports)

# Explicit fields: '{{json .}}' references .Size, which makes `docker ps -a` walk every
# container filesystem (over a minute on hosts with many stopped containers).
DOCKER_PS_FORMAT='{"ID":{{json .ID}},"Names":{{json .Names}},"Image":{{json .Image}},"State":{{json .State}},"Ports":{{json .Ports}}}'

class ContainerProbe:
    """Read-only Docker/Podman inspection via their CLIs. Never starts, stops or modifies containers."""
    EXTRA_PATHS = ['/opt/homebrew/bin', '/usr/local/bin', '/usr/bin', str(Path.home()/'.docker/bin'),
                   '/Applications/Docker.app/Contents/Resources/bin', '/opt/podman/bin']

    def __init__(self, runner=command, which=None, timeout=10):
        self.run = runner
        search = os.pathsep.join([os.environ.get('PATH', '')] + self.EXTRA_PATHS)
        self.which = which or (lambda name: shutil.which(name, path=search))
        self.timeout = timeout
        self.lock = threading.Lock()
        self.cache = ([], [])
        self.stop = threading.Event()

    def runtime_binaries(self):
        found = {}
        for name in ('docker', 'podman'):
            path = self.which(name)
            if not path:
                continue
            # A podman-docker shim would otherwise report every container twice.
            if name == 'docker' and 'podman' in self.run([path, '--version'], timeout=self.timeout).lower():
                continue
            found[name] = path
        return found

    def probe(self, runtime, binary):
        if runtime == 'docker':
            listing = self.run([binary, 'ps', '-a', '--no-trunc', '--format', DOCKER_PS_FORMAT], timeout=self.timeout)
            stats = self.run([binary, 'stats', '--no-stream', '--no-trunc', '--format', '{{json .}}'], timeout=self.timeout)
        else:
            listing = self.run([binary, 'ps', '-a', '--format', 'json'], timeout=self.timeout)
            stats = self.run([binary, 'stats', '--no-stream', '--format', 'json'], timeout=self.timeout)
        infos = json_rows(listing)
        if not infos and not listing.strip():
            # Docker prints nothing for zero containers; tell that apart from a stopped daemon.
            if runtime == 'docker' and self.run([binary, 'version', '--format', '{{.Server.Version}}'], timeout=self.timeout).strip():
                return [], None
            return [], 'Runtime not reachable (daemon or machine stopped?)'
        by_id = {}
        for row in json_rows(stats):
            ident = str(row.get('id') or row.get('container') or '')
            if ident:
                by_id[ident] = row
        rows = []
        for info in infos:
            ident = str(info.get('id') or '')
            match = by_id.get(ident) or next((v for k, v in by_id.items() if ident.startswith(k) or k.startswith(ident)), {})
            rows.append(container_row(runtime, info, match))
        return rows, None

    def collect(self):
        containers, runtimes = [], []
        binaries = self.runtime_binaries()
        for name in ('docker', 'podman'):
            if name not in binaries:
                runtimes.append(dict(name=name, available=False, error='Not installed'))
                continue
            try:
                rows, error = self.probe(name, binaries[name])
            except (OSError, ValueError) as exc:
                rows, error = [], type(exc).__name__
            containers.extend(rows)
            runtimes.append(dict(name=name, available=error is None, error=error))
        with self.lock:
            self.cache = (containers[:2000], runtimes)
        return self.cache

    def latest(self):
        with self.lock:
            return self.cache

    def start(self, interval=5):
        def loop():
            while True:
                self.collect()
                if self.stop.wait(interval):
                    return
        threading.Thread(target=loop, daemon=True).start()

def os_label():
    if platform.system() == 'Darwin' and platform.mac_ver()[0]:
        return 'macOS '+platform.mac_ver()[0]
    return platform.system()+' '+platform.release()

class Collector:
    def __init__(self, containers=None):
        if platform.system() not in ('Linux', 'Darwin'):
            raise RuntimeError('This release supports Linux and macOS.')
        self.linux = platform.system() == 'Linux'
        self.proc = Path('/proc')
        self.containers = containers
        self.previous_cpu = None
        self.previous_processes = {}
        self.previous_network = None
        self.previous_time = time.monotonic()
        self.ticks = os.sysconf('SC_CLK_TCK')
        self.page_size = os.sysconf('SC_PAGE_SIZE')

    def linux_snapshot(self, elapsed):
        memory = {}
        for line in (self.proc/'meminfo').read_text().splitlines():
            key, value = line.split(':', 1)
            memory[key] = int(value.split()[0]) * 1024
        cpu = list(map(int, (self.proc/'stat').read_text().splitlines()[0].split()[1:]))
        # guest time is included in user/nice; don't count it twice.
        total, idle = sum(cpu[:8]), cpu[3] + (cpu[4] if len(cpu)>4 else 0)
        usage = 0.0
        if self.previous_cpu:
            delta = total-self.previous_cpu[0]
            if delta>0:
                usage = 100 * (1-(idle-self.previous_cpu[1])/delta)
        self.previous_cpu = (total,idle)
        ports = {}
        for proto in ['tcp', 'tcp6']:
            try:
                for line in (self.proc/'net'/proto).read_text().splitlines()[1:]:
                    fields = line.split()
                    if fields[3]=='0A':
                        ports[fields[9]] = int(fields[1].split(':')[1],16)
            except OSError:
                pass
        current = {}
        processes = []
        for folder in self.proc.iterdir():
            if not folder.name.isdigit():
                continue
            try:
                stat = (folder/'stat').read_text()
                # comm may itself contain parentheses.
                end = stat.rfind(')')
                fields = stat[end+2:].split()
                name = stat[stat.find('(')+1:end]
                ticks = int(fields[11])+int(fields[12])
                start = int(fields[19])
                rss = max(0,int(fields[21]))*self.page_size
                pid = int(folder.name)
                current[(pid,start)] = ticks
                previous = self.previous_processes.get((pid,start),ticks)
                process_cpu = max(0,(ticks-previous)/self.ticks/elapsed*100)
                listening = []
                try:
                    for fd in (folder/'fd').iterdir():
                        target = os.readlink(fd)
                        if target.startswith('socket:['):
                            inode = target[8:-1]
                            if inode in ports:
                                listening.append(ports[inode])
                except OSError:
                    pass
                try:
                    cwd = os.readlink(folder/'cwd')
                    project = Path(cwd).name if name in ('node','python','python3','go','cargo') and cwd!='/' else None
                except OSError:
                    project = None
                processes.append(dict(pid=pid,name=name,app=app_name(name),cpu=round(process_cpu,2),memory=rss,project=project,ports=sorted(set(listening))))
            except (OSError,ValueError,IndexError):
                continue
        self.previous_processes = current
        incoming = outgoing = 0
        for line in (self.proc/'net'/'dev').read_text().splitlines()[2:]:
            interface, data = line.split(':',1)
            if interface.strip()=='lo':
                continue
            counters = data.split()
            incoming += int(counters[0]); outgoing += int(counters[8])
        battery = None
        for p in Path('/sys/class/power_supply').glob('*/capacity'):
            try:
                battery = max(0,min(100,int(p.read_text())))
                break
            except (OSError,ValueError):
                pass
        return usage,memory['MemTotal'],memory['MemTotal']-memory.get('MemAvailable',memory.get('MemFree',0)),processes,(incoming,outgoing),battery

    def mac_snapshot(self, elapsed):
        total = int(command(['sysctl','-n','hw.memsize']).strip() or '0')
        if total<=0:
            raise RuntimeError('Could not read macOS physical memory.')
        vm = command(['vm_stat'])
        page = re.search(r'page size of (\d+) bytes',vm)
        page_size = int(page.group(1)) if page else self.page_size
        pages = dict((k.strip(),int(v)) for k,v in re.findall(r'([^\n:]+):\s+(\d+)\.',vm))
        available = (pages.get('Pages free',0)+pages.get('Pages inactive',0)+pages.get('Pages speculative',0))*page_size
        processes = []
        listeners = {}
        pid = None
        for line in command(['lsof','-nP','-iTCP','-sTCP:LISTEN','-Fpn']).splitlines():
            if line.startswith('p'):
                pid = int(line[1:])
            elif line.startswith('n') and pid:
                port = re.search(r':(\d+)$',line)
                if port:
                    listeners.setdefault(pid,[]).append(int(port.group(1)))
        for line in command(['ps','-axo','pid=,pcpu=,rss=,comm=']).splitlines():
            fields = line.strip().split(None,3)
            try:
                pid,cpu,rss,name = fields
                processes.append(dict(pid=int(pid),name=Path(name).name,app=app_name(name),cpu=float(cpu),memory=int(rss)*1024,project=None,ports=sorted(set(listeners.get(int(pid),[])))))
            except (ValueError,IndexError):
                continue
        # macOS ps %cpu is OS-reported recent process CPU, summed and core-normalized.
        cpu = min(100,sum(p['cpu'] for p in processes)/(os.cpu_count() or 1))
        incoming = outgoing = 0
        lines = command(['netstat','-ibn']).splitlines()
        if lines:
            header = lines[0].split()
            if 'Ibytes' in header and 'Obytes' in header:
                seen = set()
                for line in lines[1:]:
                    row = line.split()
                    try:
                        name = row[0]
                        if name in seen or name.startswith('lo') or not row[2].startswith('<Link'):
                            continue
                        incoming += int(row[header.index('Ibytes')]); outgoing += int(row[header.index('Obytes')]); seen.add(name)
                    except (ValueError,IndexError):
                        continue
        bat = re.search(r'(\d+)%;',command(['pmset','-g','batt']))
        return cpu,total,max(0,min(total,total-available)),processes,(incoming,outgoing),int(bat.group(1)) if bat else None

    def snapshot(self):
        now = time.monotonic()
        elapsed = max(.001,now-self.previous_time)
        cpu,total,used,processes,network,battery = self.linux_snapshot(elapsed) if self.linux else self.mac_snapshot(elapsed)
        download = upload = 0
        if self.previous_network:
            download = max(0,(network[0]-self.previous_network[0])/elapsed)
            upload = max(0,(network[1]-self.previous_network[1])/elapsed)
        self.previous_network = network
        self.previous_time = now
        disk = shutil.disk_usage('/')
        extra = {}
        if self.containers is not None:
            containers, runtimes = self.containers.latest()
            extra = dict(containers=containers, runtimes=runtimes)
        return dict(version=VERSION,timestamp=dt.datetime.now(dt.timezone.utc).isoformat().replace('+00:00','Z'),host=dict(name=platform.node(),os=os_label(),cores=os.cpu_count() or 1,memoryTotal=total),cpu=round(max(0,min(100,cpu)),2),memoryUsed=used,diskUsed=disk.used,diskTotal=disk.total,download=round(download,2),upload=round(upload,2),battery=battery,processes=processes,**extra)

class Store:
    def __init__(self,path):
        self.path=path
        self.lock=threading.Lock()
        with self.connection() as db:
            db.execute('CREATE TABLE IF NOT EXISTS samples (timestamp REAL PRIMARY KEY, payload TEXT NOT NULL)')
    def connection(self):
        return sqlite3.connect(self.path,timeout=10)
    def add(self,sample):
        now=dt.datetime.fromisoformat(sample['timestamp'].replace('Z','+00:00')).timestamp()
        with self.lock,self.connection() as db:
            db.execute('INSERT OR REPLACE INTO samples VALUES (?,?)',(now,json.dumps(sample)))
            db.execute('DELETE FROM samples WHERE timestamp < ?',(now-30*86400,))
    def history(self,since=0,limit=300):
        with self.lock,self.connection() as db:
            rows=db.execute('SELECT payload FROM samples WHERE timestamp >= ? ORDER BY timestamp DESC LIMIT ?',(since,min(1000,max(1,limit)))).fetchall()
        return [json.loads(row[0]) for row in reversed(rows)]

class TelemetryServer(ThreadingHTTPServer):
    daemon_threads=True
    def __init__(self,address,token,origins,store,snapshot,ui_upstream=None):
        super().__init__(address,Handler)
        self.token=token;self.origins=set(origins);self.store=store;self.snapshot=snapshot;self.snapshot_lock=threading.Lock()
        self.ui_upstream=ui_upstream.rstrip('/') if ui_upstream else None
        self.tls=False

# Headers that describe one hop and must not be forwarded by the dashboard proxy.
HOP_HEADERS={'connection','keep-alive','proxy-authenticate','proxy-authorization','te','trailers','transfer-encoding','upgrade','host','content-length','authorization'}

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,*args,**kwargs):
        return None

PROXY=urllib.request.build_opener(NoRedirect)

class Handler(BaseHTTPRequestHandler):
    server_version='Vytrix/0.1'
    timeout=30
    def log_message(self,*args):
        pass  # Do not log authorization headers or queries.
    def origin_allowed(self):
        origin=self.headers.get('Origin')
        return origin is None or origin in self.server.origins
    def reply(self,status,payload=None):
        body=json.dumps(payload).encode() if payload is not None else b''
        self.send_response(status)
        origin=self.headers.get('Origin')
        if origin in self.server.origins:
            self.send_header('Access-Control-Allow-Origin',origin)
            self.send_header('Vary','Origin')
        self.send_header('Content-Type','application/json')
        self.send_header('Cache-Control','no-store')
        self.send_header('X-Content-Type-Options','nosniff')
        self.send_header('Content-Length',str(len(body)))
        self.end_headers();self.wfile.write(body)
    def do_OPTIONS(self):
        if not self.origin_allowed():
            return self.reply(403,{'error':'Origin denied'})
        self.send_response(204)
        origin=self.headers.get('Origin')
        if origin:
            self.send_header('Access-Control-Allow-Origin',origin)
            self.send_header('Vary','Origin')
        self.send_header('Access-Control-Allow-Methods','GET, OPTIONS')
        self.send_header('Access-Control-Allow-Headers','Authorization')
        self.send_header('Content-Length','0');self.end_headers()
    def proxy(self):
        """Serve the dashboard from --ui-upstream on this origin, so the browser needs one HTTPS port."""
        length=int(self.headers.get('Content-Length') or 0)
        if length>1024**2:
            return self.reply(413,{'error':'Request too large'})
        body=self.rfile.read(length) if length else None
        headers={k:v for k,v in self.headers.items() if k.lower() not in HOP_HEADERS}
        headers['X-Forwarded-Proto']='https' if self.server.tls else 'http'
        headers['X-Forwarded-Host']=self.headers.get('Host','')
        request=urllib.request.Request(self.server.ui_upstream+self.path,data=body,headers=headers,method=self.command)
        try:
            response=PROXY.open(request,timeout=30)
        except urllib.error.HTTPError as error:
            response=error
        except OSError:
            return self.reply(502,{'error':'Dashboard unavailable'})
        with response:
            data=response.read()
            self.send_response(response.status)
            for key,value in response.headers.items():
                if key.lower() in HOP_HEADERS:
                    continue
                if key.lower()=='location' and value.startswith(self.server.ui_upstream):
                    value=value[len(self.server.ui_upstream):] or '/'
                self.send_header(key,value)
            self.send_header('Content-Length',str(len(data)))
            self.end_headers()
            if self.command!='HEAD':
                self.wfile.write(data)
    def do_HEAD(self):
        if self.server.ui_upstream and not self.path.startswith('/v1/'):
            return self.proxy()
        return self.reply(405,{'error':'Method not allowed'})
    def do_POST(self):
        if self.server.ui_upstream and not self.path.startswith('/v1/'):
            return self.proxy()
        return self.reply(405,{'error':'Read-only API'})
    def do_GET(self):
        path=urlparse(self.path)
        if path.path=='/healthz':
            return self.reply(200,{'status':'ok'})
        if self.server.ui_upstream and not path.path.startswith('/v1/'):
            return self.proxy()
        if not self.origin_allowed():
            return self.reply(403,{'error':'Origin denied'})
        expected='Bearer '+self.server.token
        if not hmac.compare_digest(self.headers.get('Authorization','').encode(),expected.encode()):
            return self.reply(401,{'error':'Unauthorized'})
        if path.path=='/v1/snapshot':
            with self.server.snapshot_lock:
                return self.reply(200,self.server.snapshot)
        if path.path=='/v1/history':
            try:
                query=parse_qs(path.query)
                since=float(query.get('since',['0'])[0]);limit=int(query.get('limit',['300'])[0])
                if not 0<=since<1e12 or not 1<=limit<=1000:
                    raise ValueError()
                return self.reply(200,{'version':1,'samples':self.server.store.history(since,limit)})
            except ValueError:
                return self.reply(400,{'error':'since must be a finite epoch timestamp; limit must be 1–1000'})
        return self.reply(404,{'error':'Not found'})

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--once',action='store_true',help='Print one snapshot, then exit')
    parser.add_argument('--bind',default='127.0.0.1')
    parser.add_argument('--port',type=int,default=9847)
    parser.add_argument('--allow-origin',action='append',default=[])
    parser.add_argument('--database',default=str(Path.home()/'.local/share/vytrix/history.sqlite'))
    parser.add_argument('--interval',type=float,default=2)
    parser.add_argument('--no-containers',action='store_true',help='Do not query Docker or Podman')
    parser.add_argument('--container-interval',type=float,default=5,help='Seconds between Docker/Podman polls')
    parser.add_argument('--tls-cert',help='PEM certificate; serve HTTPS (required for remote browser access)')
    parser.add_argument('--tls-key',help='PEM private key for --tls-cert')
    parser.add_argument('--ui-upstream',help='Proxy non-API paths to this dashboard URL, e.g. http://127.0.0.1:8787')
    args=parser.parse_args()
    if args.interval<1 or args.interval>3600:
        parser.error('--interval must be 1–3600 seconds')
    if args.container_interval<2 or args.container_interval>3600:
        parser.error('--container-interval must be 2–3600 seconds')
    if bool(args.tls_cert)!=bool(args.tls_key):
        parser.error('--tls-cert and --tls-key must be given together')
    if args.ui_upstream:
        upstream=urlparse(args.ui_upstream)
        if upstream.scheme!='http' or upstream.hostname not in ('127.0.0.1','localhost','::1') or upstream.path.strip('/'):
            parser.error('--ui-upstream must be a loopback http origin, e.g. http://127.0.0.1:8787')
    probe=None if args.no_containers else ContainerProbe()
    if probe:
        probe.collect()
    collector=Collector(probe);collector.snapshot();time.sleep(1)
    snapshot=collector.snapshot()
    if args.once:
        print(json.dumps(snapshot,indent=2));return
    token=os.environ.get('VYTRIX_TOKEN','')
    if len(token)<24:
        parser.error('Set VYTRIX_TOKEN to a random token of at least 24 characters')
    for origin in args.allow_origin:
        parsed=urlparse(origin)
        if parsed.scheme not in ('http','https') or not parsed.netloc or parsed.path or parsed.query or parsed.fragment:
            parser.error('--allow-origin must be an exact http(s) origin without a trailing slash')
    Path(args.database).parent.mkdir(parents=True,exist_ok=True,mode=0o700)
    store=Store(args.database);os.chmod(args.database,0o600);store.add(snapshot)
    server=TelemetryServer((args.bind,args.port),token,args.allow_origin,store,snapshot,args.ui_upstream)
    if args.tls_cert:
        context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version=ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(args.tls_cert,args.tls_key)
        server.socket=context.wrap_socket(server.socket,server_side=True,do_handshake_on_connect=False)
        server.tls=True
    elif args.bind not in ('127.0.0.1','localhost','::1'):
        print('Warning: serving plain HTTP on a non-loopback address; use --tls-cert/--tls-key.',flush=True)
    stop=threading.Event()
    def sample_loop():
        while not stop.wait(args.interval):
            try:
                sample=collector.snapshot();store.add(sample)
                with server.snapshot_lock:
                    server.snapshot=sample
            except (OSError,RuntimeError,sqlite3.Error) as error:
                print('Collection failed:',type(error).__name__,flush=True)
    threading.Thread(target=sample_loop,daemon=True).start()
    if probe:
        probe.start(args.container_interval)
    print(f"Vytrix read-only collector listening on {'https' if server.tls else 'http'}://{args.bind}:{args.port}",flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        stop.set();server.server_close()
        if probe:
            probe.stop.set()

if __name__=='__main__':
    main()
