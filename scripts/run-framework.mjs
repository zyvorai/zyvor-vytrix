// SPDX-License-Identifier: BUSL-1.1
// Runs the vinext CLI in this process so `pnpm dev` / `pnpm build` keep their PID and signals.
import { fileURLToPath } from "node:url";

const [command, ...args] = process.argv.slice(2);
if (!["dev", "build"].includes(command)) throw new Error("Expected dev or build.");

const cli = new URL("../node_modules/vinext/dist/cli.js", import.meta.url);
// Default dev port 5173 unless the caller (Playwright, shots, demo) chose one.
const hasPort = args.some((a) => a === "--port" || a === "-p" || a.startsWith("--port="));
process.argv = [
  process.execPath,
  fileURLToPath(cli),
  command,
  ...(command === "dev" && !hasPort ? ["--port", "5173"] : []),
  ...args,
];
await import(cli.href);
