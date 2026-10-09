# Vytrix Fleet Pro

Fleet Pro extends the existing read-only Vytrix collector/coordinator without a remote command channel.

## Included

- Apple Silicon/Metal/ANE capability visibility and best-effort GPU telemetry.
- Linux DRM GPU, thermal and power telemetry where the kernel exports counters.
- Per-process disk I/O rates; macOS per-process network rates via `nettop` when available.
- AI workload classification without reading process command lines.
- Safe software/version inventory and collector health.
- 90-day centralized history by default (`--retention-days`, up to 3650).
- Node tags, group and site metadata.
- Viewer, auditor, operator and admin roles with node scoping.
- Central alert rules/events and signed HTTPS webhooks (Slack-compatible incoming webhooks are supported).
- Signed reverse-proxy SSO assertion endpoint, suitable behind an OIDC/SAML identity proxy.
- Prometheus `/metrics` export protected by `VYTRIX_METRICS_TOKEN`.
- Local capacity/anomaly forecasting in the dashboard.
- Commercial entitlement scaffold with node limits.
- Online SQLite backup utility for HA/DR replication workflows.
- Explicit SHA-256 verified agent update helper; updates are never triggered by monitoring traffic.

## Entry points

Use `agent/vytrix_fleet.py` instead of `agent/vytrix.py`, `agent/cluster_worker_fleet.py` instead of `agent/cluster_worker.py`, and `cluster/fleet_coordinator.py` instead of `cluster/coordinator.py`.

The originals remain untouched and are the rollback path.

## SSO proxy

Set `VYTRIX_SSO_SECRET`. A trusted OIDC/SAML proxy provisions a user in the normal Vytrix config and POSTs `/v1/sso` with `user`, unix `timestamp`, and HMAC-SHA256 of `user + "\\n" + timestamp`. Assertions older than 60 seconds are rejected.

## Entitlements

Set `VYTRIX_LICENSE_SECRET` and `VYTRIX_LICENSE_TOKEN`. The token is `base64url(JSON).hex_hmac`. This is a commercial packaging scaffold, not DRM. The token does not change the rights granted by the project `LICENSE`; production use is licensed separately.

## Known platform boundaries

Linux `/proc/<pid>/net/dev` is namespace-wide rather than process-specific, so Vytrix does not pretend it is per-process traffic. Accurate Linux attribution needs an eBPF collector. macOS ANE global utilization is not exposed by a stable public API, so Vytrix reports ANE availability but not invented utilization.

Apple code signing/notarization is intentionally not embedded in source. Release CI must receive Apple Developer signing credentials as repository secrets on a macOS runner.
