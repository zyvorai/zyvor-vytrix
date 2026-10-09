# SPDX-License-Identifier: BUSL-1.1
"""Fleet enrichment for Vytrix collectors.

Read-only by default. The probe collects bounded inventory, agent health and, on macOS,
best-effort per-process network counters from nettop. Unsupported counters are omitted.
"""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import time
from typing import Any

VERSION = "0.4.0"


def _command(args: list[str], timeout: float = 4.0) -> str:
    try:
        return subprocess.check_output(args, text=True, timeout=timeout, stderr=subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError):
        return ""


def _version(binary: str, args: list[str] | None = None) -> str | None:
    path = shutil.which(binary)
    if not path:
        return None
    raw = _command([path] + (args or ["--version"]), timeout=2).splitlines()
    return raw[0][:256] if raw else None


def safe_inventory() -> dict[str, Any]:
    """Small software/hardware inventory with no command lines, files or user documents."""
    tools: dict[str, str] = {}
    for name, args in (("python3", ["--version"]), ("node", ["--version"]), ("git", ["--version"]),
                       ("docker", ["--version"]), ("podman", ["--version"]), ("swift", ["--version"])):
        value = _version(name, args)
        if value:
            tools[name] = value
    data: dict[str, Any] = {
        "agentVersion": VERSION,
        "hostname": platform.node()[:256],
        "architecture": platform.machine()[:64],
        "platform": platform.system()[:64],
        "platformRelease": platform.release()[:128],
        "python": platform.python_version(),
        "tools": tools,
    }
    if platform.system() == "Darwin":
        product = _command(["sw_vers", "-productVersion"]).strip()
        model = _command(["sysctl", "-n", "hw.model"]).strip()
        if product:
            data["macOS"] = product[:64]
        if model:
            data["model"] = model[:128]
    return data


def parse_nettop_csv(text: str) -> dict[int, tuple[int, int]]:
    """Parse bounded nettop CSV variants into PID -> cumulative bytes in/out.

    nettop output varies by macOS release. We locate columns by header name and ignore
    rows that do not contain an integer PID and byte counters.
    """
    rows = [r for r in text.splitlines() if r.strip()]
    if not rows:
        return {}
    header = [x.strip().lower() for x in rows[0].split(",")]
    def index(*names: str) -> int | None:
        for name in names:
            if name in header:
                return header.index(name)
        return None
    pid_i = index("pid")
    in_i = index("bytes_in", "bytes in", "rx_bytes")
    out_i = index("bytes_out", "bytes out", "tx_bytes")
    if pid_i is None or in_i is None or out_i is None:
        return {}
    result: dict[int, tuple[int, int]] = {}
    for raw in rows[1:10001]:
        cols = [x.strip() for x in raw.split(",")]
        try:
            pid = int(cols[pid_i]); incoming = max(0, int(float(cols[in_i]))); outgoing = max(0, int(float(cols[out_i])))
        except (ValueError, IndexError):
            continue
        previous = result.get(pid, (0, 0))
        result[pid] = (previous[0] + incoming, previous[1] + outgoing)
    return result


class FleetProbe:
    def __init__(self, inventory_ttl: float = 60.0):
        self.inventory_ttl = max(10.0, inventory_ttl)
        self._inventory: dict[str, Any] = {}
        self._inventory_at = 0.0
        self._net_previous: dict[int, tuple[int, int, float]] = {}
        self.started = time.monotonic()
        self.samples = 0
        self.failures = 0

    def _inventory_snapshot(self, now: float) -> dict[str, Any]:
        if not self._inventory or now - self._inventory_at >= self.inventory_ttl:
            self._inventory = safe_inventory()
            self._inventory_at = now
        return dict(self._inventory)

    def _mac_network(self, processes: list[dict[str, Any]], now: float) -> None:
        if platform.system() != "Darwin" or not shutil.which("nettop"):
            return
        raw = _command(["nettop", "-P", "-L", "1", "-J", "pid,bytes_in,bytes_out", "-x"], timeout=3)
        counters = parse_nettop_csv(raw)
        current: dict[int, tuple[int, int, float]] = {}
        for process in processes:
            pid = int(process.get("pid") or 0)
            pair = counters.get(pid)
            if not pair:
                continue
            prev = self._net_previous.get(pid)
            if prev:
                elapsed = max(0.001, now - prev[2])
                process["networkInRate"] = round(max(0, pair[0] - prev[0]) / elapsed, 2)
                process["networkOutRate"] = round(max(0, pair[1] - prev[1]) / elapsed, 2)
            current[pid] = (pair[0], pair[1], now)
        self._net_previous = current

    def enrich(self, snapshot: dict[str, Any]) -> dict[str, Any]:
        now = time.monotonic()
        try:
            self._mac_network(snapshot.get("processes") or [], now)
            snapshot["inventory"] = self._inventory_snapshot(now)
            self.samples += 1
        except Exception:
            self.failures += 1
        snapshot["agent"] = {
            "version": VERSION,
            "uptimeSeconds": round(max(0.0, now - self.started), 1),
            "samples": self.samples,
            "failures": self.failures,
            "healthy": self.failures == 0 or self.samples >= self.failures,
        }
        return snapshot


def sha256_file(path: str | Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def verify_update_manifest(manifest: dict[str, Any], candidate: str | Path) -> bool:
    """Verify a locally staged update against a manifest SHA-256 before installation."""
    expected = str(manifest.get("sha256") or "").lower()
    return bool(re.fullmatch(r"[0-9a-f]{64}", expected)) and sha256_file(candidate) == expected
