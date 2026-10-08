// SPDX-License-Identifier: Apache-2.0
// Preloaded (`node --import`) before wrangler: keeps its state project-local and its telemetry off.
import { mkdirSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const projectRoot = fileURLToPath(new URL("../", import.meta.url));
const stateRoot = process.env.VYTRIX_STATE_ROOT || path.join(projectRoot, ".wrangler");

process.env.CLOUDFLARE_CF_FETCH_ENABLED ||= "false";
process.env.WRANGLER_SEND_METRICS ||= "false";
process.env.WRANGLER_WRITE_LOGS ||= "false";
process.env.WRANGLER_LOG_PATH ||= path.join(stateRoot, "logs");
process.env.WRANGLER_REGISTRY_PATH ||= path.join(stateRoot, "dev-registry");
process.env.MINIFLARE_REGISTRY_PATH ||= path.join(stateRoot, "registry");

process.chdir(projectRoot);
for (const directory of [
  process.env.WRANGLER_LOG_PATH,
  process.env.WRANGLER_REGISTRY_PATH,
  process.env.MINIFLARE_REGISTRY_PATH,
]) {
  mkdirSync(directory, { recursive: true });
}
