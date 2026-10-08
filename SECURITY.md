# Security

The collector is read-only and runs as an ordinary user. Do not grant root solely for expanded telemetry visibility. Missing process/port access is expected.

Keep the collector on loopback and use a TLS reverse proxy for remote access. Use a unique random access token with at least 24 characters and explicit origin allow-list. Rotate by restarting the collector with a new token. CORS is a browser access policy, not a replacement for bearer authentication or network controls.

Snapshots and SQLite history contain host/process names and project basenames. Treat exports as operational data. There is no application account system or multi-tenant server in this release. The hosted preview's private access is provided by its host; self-hosted deployments must supply their own dashboard authentication.

Browser preferences are device-local. Collector tokens are held only in memory. Imported JSON is validated and rendered as text. Limit imports to 10 MB; maximum 20,000 process records. Requests time out after 8 seconds; failed samples retain the last successful data with an error banner.

## Optional cluster coordinator (read-only)

The separate coordinator (`cluster/coordinator.py`) receives snapshots from workers and serves them to signed-in viewers. It has no command channel: it cannot run anything on a monitored Mac, and the worker contains no subprocess or `launchctl` code (a test enforces this). Roles are `viewer` and `admin`; administrators can create single-use pairing codes (valid five minutes), revoke devices and read the audit log, which only changes the coordinator's own records. Device credentials and session tokens are random secrets stored only as hashes; sessions last eight hours; logins are rate limited. Remote traffic requires verified TLS. Browser tokens stay in tab memory. The coordinator stores each machine's latest snapshot (host and process names) and audit events, so restrict access and backups. See [docs/CLUSTER.md](docs/CLUSTER.md).

Report vulnerabilities privately to security@zyvor.dev.
