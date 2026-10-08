import type { NextConfig } from "next";

// Empty for every normal build, e2e run and deploy. The GitHub Pages demo build sets
// VYTRIX_BASE_PATH=/zyvor-vytrix/demo so the app can be served as static files under a sub-path.
const basePath = process.env.VYTRIX_BASE_PATH || "";

const nextConfig: NextConfig = {
  ...(basePath ? { basePath } : {}),
  // Inlined at build time: the worker has no process env at request time, and app/layout.tsx needs the
  // base path to prefix the metadata icon URLs.
  env: { VYTRIX_BASE_PATH: basePath },
};

export default nextConfig;
