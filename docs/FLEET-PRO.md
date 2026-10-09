# Vytrix Fleet Pro

Fleet Pro extends the read-only collector and coordinator with richer telemetry, central history, metadata, roles, alerts and exports. **It adds no command channel**: nothing in it can run, stop or change anything on a monitored machine. The original `agent/vytrix.py`, `agent/cluster_worker.py` and `cluster/coordinator.py` are unchanged and remain the rollback path.

Licensing: Fleet Pro is part of Vytrix and is under the same [Business Source License 1.1](../LICENSE) as everything else. Production use needs a commercial license from Zyvor AI Labs Private Limited.

## Entry points

| Use | Instead of |
| --- | --- |
| `agent/vytrix_fleet.py` | `agent/vytrix.py` |
| `agent/cluster_worker_fleet.py` | `agent/cluster_worker.py` |
| `cluster/fleet_coordinator.py` | `cluster/coordinator.py` |

They take the same flags as the originals. The coordinator adds `--retention-days` (default 90 or `VYTRIX_RETENTION_DAYS`, up to 3650). Remote listeners still require TLS, and the config file must be mode 0600.

```bash
python3 cluster/fleet_coordinator.py --init-user alice --role admin > ~/.vytrix-cluster/users.json
chmod 600 ~/.vytrix-cluster/users.json
python3 cluster/fleet_coordinator.py --config ~/.vytrix-cluster/users.json \
  --bind 0.0.0.0 --tls-cert cert.pem --tls-key key.pem --allow-origin https://dashboard.example.com
```

## What it adds

- **Telemetry** (optional snapshot fields, so older snapshots stay valid): `hardware` (Apple Silicon, Metal and Neural Engine availability, GPU best effort; Linux DRM GPU, thermal and power where the kernel exports counters), per-process `diskReadRate`/`diskWriteRate`, macOS per-process `networkInRate`/`networkOutRate` via `nettop` when available, `aiWorkloads` and per-process `ai` classification, `inventory` (software and versions) and `agent` health. Counters that are not available are omitted, never estimated.
- **AI workload classification** uses process names only; it never reads command lines.
- **Central history**: 90 days by default.
- **Metadata**: tags, group and site per machine.
- **Alerts**: central rules and events, and signed webhooks (HTTPS only, except loopback; Slack-compatible incoming webhooks work).
- **Dashboard**: Silicon & AI and Capacity intelligence cards on the Overview (local trend and anomaly forecasting; nothing leaves the browser), and Fleet inventory, intelligence and admin panels in Mac cluster.
- **Operations**: Prometheus `/metrics`, an online SQLite backup tool (`cluster/backup.py DATABASE OUTPUT`), and an explicit update helper.

## Roles

Each role includes the ones above it.

| Role | Can |
| --- | --- |
| `viewer` | Read machines, history and the entitlement |
| `auditor` | Also read alert events and rules |
| `editor` | Also write alert rules and node tags, group and site. Coordinator records only |
| `admin` | Also manage webhooks (and pairings, revocation and audit as in the base coordinator) |

There is no `operator` role anywhere: the base coordinator still accepts only `viewer` and `admin`, and a test enforces it.

## API (additions)

| Endpoint | Role |
| --- | --- |
| `POST /v1/sso` | A trusted proxy; see below |
| `GET /v1/fleet/history` | viewer (optional `node`) |
| `GET /v1/fleet/entitlement` | viewer |
| `GET /v1/fleet/alerts`, `GET /v1/fleet/rules` | auditor |
| `POST /v1/fleet/rules`, `POST /v1/fleet/meta` | editor |
| `GET`/`POST /v1/fleet/webhooks` | admin |
| `GET /metrics` | `Authorization: Bearer $VYTRIX_METRICS_TOKEN` (off if unset) |
| `GET /healthz` | none; `{"status": "ok", "fleet": true}` |

`GET /v1/cluster` gains optional `tags`, `group`, `site`, `inventory`, `agentHealth` per node and an `entitlement` object. There is still no endpoint that sends anything to a machine.

## SSO proxy

Set `VYTRIX_SSO_SECRET`. A trusted OIDC/SAML proxy provisions the user in the normal Vytrix config and POSTs `/v1/sso` with `user`, a unix `timestamp`, and an HMAC-SHA256 of `user + "\n" + timestamp`. Assertions older than 60 seconds are rejected. Vytrix does not speak OIDC or SAML itself.

## Entitlements

Set `VYTRIX_LICENSE_SECRET` and `VYTRIX_LICENSE_TOKEN`. The token is `base64url(JSON).hex_hmac` and carries a plan, a node limit and features. Without a valid token the coordinator runs as `community` (3 nodes). This is a packaging scaffold, not DRM, and it does not change the rights granted by `LICENSE`.

## Updating an agent

`scripts/vytrix-agent-update.py MANIFEST CANDIDATE TARGET` installs a new agent file only if its SHA-256 matches the manifest. It is run by an operator on purpose; monitoring traffic never triggers an update.

## Known boundaries

- Linux `/proc/<pid>/net/dev` is namespace-wide, not per process, so Vytrix does not report per-process Linux network. Accurate attribution needs an eBPF helper.
- macOS Neural Engine utilization has no stable public API: Vytrix reports availability, not utilization.
- Apple signing and notarization need Apple Developer credentials on a macOS CI runner; none are in the source.
- Verified so far: five unit tests (`tests/test_fleet.py`: nettop parsing, role hierarchy, SSO and entitlement tokens, history/alerts/Prometheus, update checksum) and the forecast test. **Not verified:** a fleet across several Macs over HTTPS, webhook delivery to a real receiver, the SSO endpoint behind a real identity proxy, and Prometheus scraping.
