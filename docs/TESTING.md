# Testing on macOS 26, macOS 27 and Linux

| Layer | Command | Needs |
|---|---|---|
| Types | `pnpm typecheck` | Node ≥ 22.13 |
| Cluster schema and URL rules | `node tests/cluster.mjs` | Node |
| Native Mac app | `./scripts/build-native.sh` (compiles; there are no Swift tests) | macOS, Xcode command line tools |
| Schema, grouping, alerts | `node tests/telemetry.mjs` | Node |
| Capacity forecasting | `node tests/forecast.mjs` | Node |
| Fleet Pro (Python) and forecasting | `pnpm test:fleet` | Python ≥ 3.10, Node |
| Collector, API, TLS, dashboard proxy, container parsing | `python3 -m unittest discover -s tests -v` | Python ≥ 3.10, `openssl` |
| Browser end-to-end | `pnpm test:e2e` | `pnpm exec playwright install chromium webkit` |
| Real container runtimes | `scripts/test-containers.sh podman` / `docker` | Podman or Docker with a running engine |
| Installers and deploy | `scripts/install-macos.sh --dry-run`, `scripts/install-linux.sh --dry-run [--system]`, `scripts/deploy-remote.sh HOST USER --dry-run` | bash |
| Production bundle | `pnpm build` | Node |

The container unit tests replay recorded `docker`/`podman` CLI output from `tests/fixtures/`, so they run anywhere without a runtime. They assert that the collector only ever calls `--version`, `version`, `ps` and `stats --no-stream`, and that `docker ps` never uses `{{json .}}` (that template makes Docker compute every container's disk size, which took 77 s on a host with many stopped containers).

## macOS 26 and 27

```sh
brew install node python pnpm          # Python 3.10+; Apple's /usr/bin/python3 is too old
pnpm install --frozen-lockfile
pnpm typecheck && pnpm test
pnpm exec playwright install chromium webkit && pnpm test:e2e
```

`test_real_snapshot` exercises the native macOS collector (`sysctl`, `vm_stat`, `ps`, `lsof`, `netstat`, `pmset`). Check a live sample with:

```sh
python3 agent/vytrix.py --once | head -40
```

Containers are optional. If Docker Desktop or Podman is installed and its VM is running, the collector reports its containers (CPU and memory are relative to that VM); otherwise the runtime shows as not installed or unreachable and everything else works.

### launchd agent

```sh
scripts/install-macos.sh --dry-run --allow-origin http://localhost:5173   # preview
scripts/install-macos.sh --allow-origin http://localhost:5173
launchctl print gui/$(id -u)/com.zyvor.vytrix | head
curl -s -H "Authorization: Bearer $(scripts/install-macos.sh --show-token)" http://127.0.0.1:9847/v1/snapshot | head -c 300
scripts/install-macos.sh --uninstall
```

## Linux

```sh
pnpm install --frozen-lockfile && pnpm typecheck && pnpm test
scripts/test-containers.sh docker    # needs the docker group (or root)
scripts/test-containers.sh podman
```

`scripts/test-containers.sh` starts `nginx:alpine` on port 18080 (`VYTRIX_TEST_PORT` overrides it) and checks that the collector reports it as running with an `18080→80/tcp` mapping. A `docker` binary that is really the `podman-docker` shim is skipped so containers aren't counted twice; a Docker CLI without a reachable daemon shows as unreachable.

### systemd on the local machine

```sh
scripts/install-linux.sh --dry-run                     # user unit preview
scripts/install-linux.sh --allow-origin http://localhost:5173
systemctl --user status vytrix && journalctl --user -u vytrix -n 20
sudo scripts/install-linux.sh --system --allow-origin https://dash.example.com   # hardened system unit, no containers
systemd-analyze security vytrix.service               # review the sandbox score
```

The user unit doesn't set `NoNewPrivileges`: rootless Podman needs the setuid `newuidmap` helper.

### Remote host

`scripts/deploy-remote.sh` deploys the dashboard and collector to a Linux host over SSH (see [RELEASE.md](RELEASE.md#deploying-to-a-linux-host)). After a deploy:

```sh
./scripts/deploy-remote.sh 203.0.113.10 deploy --verify-only     # unit status, /healthz, dashboard HTTP 200
curl -sk https://203.0.113.10:30847/healthz                    # {"status": "ok"}
curl -sk -o /dev/null -w '%{http_code}\n' https://203.0.113.10:30847/v1/snapshot   # 401 without a token
TOKEN=$(ssh deploy@203.0.113.10 'sed -n "s/^VYTRIX_TOKEN=//p" ~/.vytrix/env')
curl -sk -H "Authorization: Bearer $TOKEN" https://203.0.113.10:30847/v1/snapshot | head -c 300
```

## CI

`.github/workflows/ci.yml` runs type checking, unit tests, the build and Playwright on `ubuntu-latest` and `macos-latest`, runs `scripts/test-containers.sh docker` on Linux, and runs the installers and the deploy script in dry-run mode on both operating systems.
