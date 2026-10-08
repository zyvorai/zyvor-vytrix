// SPDX-License-Identifier: Apache-2.0
// Worker entry: hand every request to vinext's fetch handler.
import handler from "vinext/server/fetch-handler";

const worker = {
  fetch(request: Request, env: Cloudflare.Env, ctx: ExecutionContext) {
    return handler.fetch(request, env, ctx);
  },
};

export default worker;
