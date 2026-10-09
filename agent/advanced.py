# SPDX-License-Identifier: BUSL-1.1
"""Advanced, read-only telemetry enrichment for Vytrix.

No third-party Python dependencies. All probes are best-effort. Missing counters are
omitted rather than guessed. The module never writes to kernel/sysfs/device state.
"""
from __future__ import annotations

from dataclasses import dataclass
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import threading
import time
from typing import Any


def _command(args: list[str], timeout: float = 4.0) -> str:
    try:
        return subprocess.check_output(args, text=True, timeout=timeout, stderr=subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError):
        return ""


def _safe_float(value: str | int | float | None) -> float | None:
    try:
        number = float(value)  # type: ignore[arg-type]
        if number != number or number in (float("inf"), float("-inf")):
            return None
        return number
    except (TypeError, ValueError):
        return None


@dataclass(frozen=True)
class AIFingerprint:
    engine: str
    kind: str
    score: int
    markers: tuple[str, ...]


_AI_RULES: tuple[tuple[re.Pattern[str], AIFingerprint], ...] = (
    (re.compile(r"(?:^|[/ _-])vllm(?:$|[/ _-])", re.I), AIFingerprint("vLLM", "inference", 98, ("vllm",))),
    (re.compile(r"(?:^|[/ _-])tritonserver(?:$|[/ _-])|nvidia.*triton", re.I), AIFingerprint("Triton", "inference", 98, ("triton",))),
    (re.compile(r"(?:^|[/ _-])ollama(?:$|[/ _-])", re.I), AIFingerprint("Ollama", "inference", 98, ("ollama",))),
    (re.compile(r"llama[-_. ]?cpp|llama-server|llama-cli", re.I), AIFingerprint("llama.cpp", "inference", 96, ("llama.cpp",))),
    (re.compile(r"mlx(?:_|-)?lm|python.*mlx", re.I), AIFingerprint("MLX", "inference", 92, ("mlx", "apple-silicon"))),
    (re.compile(r"tensorflow|tf_serving", re.I), AIFingerprint("TensorFlow", "training", 90, ("tensorflow",))),
    (re.compile(r"torchrun|pytorch|deepspeed|accelerate launch", re.I), AIFingerprint("PyTorch", "training", 90, ("pytorch",))),
    (re.compile(r"text-generation-launcher|text_generation_server", re.I), AIFingerprint("TGI", "inference", 96, ("huggingface", "tgi"))),
    (re.compile(r"coreml|anecompiler|aneprogram", re.I), AIFingerprint("Core ML", "inference", 88, ("coreml", "ane"))),
    (re.compile(r"stable-diffusion|comfyui|automatic1111", re.I), AIFingerprint("Diffusion", "generation", 88, ("diffusion",))),
)


def classify_ai_process(name: str, app: str = "", project: str | None = None) -> dict[str, Any] | None:
    """Classify a process from non-sensitive labels already present in Vytrix.

    We intentionally do not inspect command-line arguments because the base collector's
    privacy contract excludes them. This means generic `python` processes are not
    classified unless their app/project label carries a strong marker.
    """
    haystack = " ".join(x for x in (name, app, project or "") if x)
    for pattern, fingerprint in _AI_RULES:
        if pattern.search(haystack):
            return {
                "engine": fingerprint.engine,
                "kind": fingerprint.kind,
                "confidence": fingerprint.score,
                "markers": list(fingerprint.markers),
            }
    return None


class AdvancedProbe:
    """Stateful enrichment used by the existing Collector.

    Adds process disk rates on Linux, socket counts, AI labels and host accelerator/
    thermal/power capabilities. Hardware discovery is cached to keep collector overhead
    low. Per-process network byte counters are deliberately not fabricated on Linux:
    `/proc/<pid>/net/dev` is a network-namespace counter, not a per-process counter.
    """

    def __init__(self, proc: Path | str = "/proc", linux: bool | None = None, hardware_ttl: float = 5.0):
        self.proc = Path(proc)
        self.linux = platform.system() == "Linux" if linux is None else linux
        self.hardware_ttl = max(1.0, hardware_ttl)
        self._previous_io: dict[tuple[int, int], tuple[int, int, float]] = {}
        self._hardware: dict[str, Any] = {}
        self._hardware_at = 0.0
        self._lock = threading.Lock()

    def enrich(self, snapshot: dict[str, Any]) -> dict[str, Any]:
        now = time.monotonic()
        processes = snapshot.get("processes") or []
        if self.linux:
            self._linux_process_rates(processes, now)
        self._annotate_processes(processes)
        hardware = self.hardware_snapshot(now)
        if hardware:
            snapshot["hardware"] = hardware
        workloads = self.ai_workloads(processes)
        if workloads:
            snapshot["aiWorkloads"] = workloads
        return snapshot

    def _linux_process_rates(self, processes: list[dict[str, Any]], now: float) -> None:
        current: dict[tuple[int, int], tuple[int, int, float]] = {}
        for process in processes:
            pid = int(process.get("pid") or 0)
            if pid <= 0:
                continue
            folder = self.proc / str(pid)
            try:
                stat = (folder / "stat").read_text()
                end = stat.rfind(")")
                fields = stat[end + 2 :].split()
                start = int(fields[19])
                io_values: dict[str, int] = {}
                for row in (folder / "io").read_text().splitlines():
                    key, _, value = row.partition(":")
                    if key in ("read_bytes", "write_bytes"):
                        io_values[key] = int(value.strip())
                read_total = io_values["read_bytes"]
                write_total = io_values["write_bytes"]
                key = (pid, start)
                previous = self._previous_io.get(key)
                if previous:
                    elapsed = max(0.001, now - previous[2])
                    process["diskReadRate"] = round(max(0, read_total - previous[0]) / elapsed, 2)
                    process["diskWriteRate"] = round(max(0, write_total - previous[1]) / elapsed, 2)
                else:
                    process["diskReadRate"] = 0.0
                    process["diskWriteRate"] = 0.0
                current[key] = (read_total, write_total, now)

                socket_count = 0
                try:
                    for fd in (folder / "fd").iterdir():
                        try:
                            if os.readlink(fd).startswith("socket:["):
                                socket_count += 1
                        except OSError:
                            continue
                except OSError:
                    pass
                process["networkSockets"] = socket_count
            except (OSError, ValueError, IndexError, KeyError):
                continue
        self._previous_io = current

    def _annotate_processes(self, processes: list[dict[str, Any]]) -> None:
        for process in processes:
            ai = classify_ai_process(
                str(process.get("name") or ""),
                str(process.get("app") or ""),
                process.get("project"),
            )
            if ai:
                process["ai"] = ai

    @staticmethod
    def ai_workloads(processes: list[dict[str, Any]]) -> list[dict[str, Any]]:
        groups: dict[tuple[str, str], dict[str, Any]] = {}
        for process in processes:
            ai = process.get("ai")
            if not isinstance(ai, dict):
                continue
            key = (str(ai.get("engine") or "AI"), str(ai.get("kind") or "unknown"))
            row = groups.setdefault(
                key,
                {
                    "engine": key[0],
                    "kind": key[1],
                    "processes": 0,
                    "cpu": 0.0,
                    "memory": 0.0,
                    "diskReadRate": 0.0,
                    "diskWriteRate": 0.0,
                    "confidence": int(ai.get("confidence") or 0),
                },
            )
            row["processes"] += 1
            row["cpu"] += max(0.0, float(process.get("cpu") or 0))
            row["memory"] += max(0.0, float(process.get("memory") or 0))
            row["diskReadRate"] += max(0.0, float(process.get("diskReadRate") or 0))
            row["diskWriteRate"] += max(0.0, float(process.get("diskWriteRate") or 0))
            row["confidence"] = max(row["confidence"], int(ai.get("confidence") or 0))
        return sorted(groups.values(), key=lambda row: (row["cpu"], row["memory"]), reverse=True)[:128]

    def hardware_snapshot(self, now: float | None = None) -> dict[str, Any]:
        now = time.monotonic() if now is None else now
        with self._lock:
            if self._hardware and now - self._hardware_at < self.hardware_ttl:
                return dict(self._hardware)
            data = self._linux_hardware() if self.linux else self._mac_hardware()
            self._hardware = data
            self._hardware_at = now
            return dict(data)

    def _linux_hardware(self) -> dict[str, Any]:
        data: dict[str, Any] = {"accelerators": []}
        gpu_rows: list[dict[str, Any]] = []
        for card in sorted(Path("/sys/class/drm").glob("card[0-9]*")):
            device = card / "device"
            busy = None
            try:
                busy = _safe_float((device / "gpu_busy_percent").read_text().strip())
            except OSError:
                pass
            vendor = ""
            try:
                vendor = (device / "vendor").read_text().strip().lower()
            except OSError:
                pass
            vendor_name = {"0x10de": "NVIDIA", "0x1002": "AMD", "0x8086": "Intel"}.get(vendor, "GPU")
            row: dict[str, Any] = {"name": f"{vendor_name} {card.name}", "backend": "drm"}
            if busy is not None and 0 <= busy <= 100:
                row["utilization"] = round(busy, 2)
            gpu_rows.append(row)
        if gpu_rows:
            data["gpus"] = gpu_rows
            data["accelerators"].append({"type": "gpu", "name": gpu_rows[0]["name"], "available": True})

        temperatures = []
        for zone in sorted(Path("/sys/class/thermal").glob("thermal_zone*")):
            try:
                raw = float((zone / "temp").read_text().strip())
                value = raw / 1000 if abs(raw) > 1000 else raw
                if not -50 <= value <= 200:
                    continue
                try:
                    label = (zone / "type").read_text().strip()[:128]
                except OSError:
                    label = zone.name
                temperatures.append({"name": label, "celsius": round(value, 1)})
            except (OSError, ValueError):
                continue
        if temperatures:
            data["temperatures"] = temperatures[:64]
            data["temperatureCelsius"] = max(x["celsius"] for x in temperatures)

        watts = []
        for supply in Path("/sys/class/power_supply").glob("*"):
            try:
                microwatts = float((supply / "power_now").read_text().strip())
                value = microwatts / 1_000_000
                if 0 <= value < 10000:
                    watts.append(value)
            except (OSError, ValueError):
                continue
        if watts:
            data["powerWatts"] = round(sum(watts), 2)

        if Path("/proc/driver/nvidia/version").exists() or Path("/dev/nvidia0").exists():
            if not any(a["name"] == "NVIDIA GPU" for a in data["accelerators"]):
                data["accelerators"].append({"type": "gpu", "name": "NVIDIA GPU", "available": True})
        if not data["accelerators"]:
            data.pop("accelerators", None)
        return data

    def _mac_hardware(self) -> dict[str, Any]:
        data: dict[str, Any] = {"accelerators": []}
        machine = platform.machine()
        chip = _command(["sysctl", "-n", "machdep.cpu.brand_string"]).strip()
        if chip:
            data["chip"] = chip[:256]
        apple_silicon = machine == "arm64" and ("Apple" in chip or not chip)

        display_raw = _command(["system_profiler", "SPDisplaysDataType", "-json"], timeout=8)
        gpu_name = "Apple GPU" if apple_silicon else "GPU"
        metal = False
        if display_raw:
            try:
                payload = json.loads(display_raw)
                displays = payload.get("SPDisplaysDataType") or []
                if displays:
                    gpu_name = str(displays[0].get("sppci_model") or displays[0].get("_name") or gpu_name)[:256]
                text = display_raw.lower()
                metal = "metal" in text and not re.search(r'"[^"\\]*metal[^"\\]*"\s*:\s*"unsupported"', text)
            except (ValueError, TypeError):
                pass

        agx = _command(["ioreg", "-r", "-d", "1", "-c", "AGXAccelerator"], timeout=4)
        utilization = None
        for key in ("Device Utilization %", "GPU Utilization %", "GPU Core Utilization"):
            match = re.search(r'"' + re.escape(key) + r'"\s*=\s*(?:<)?([0-9]+(?:\.[0-9]+)?)', agx)
            if match:
                candidate = _safe_float(match.group(1))
                if candidate is not None and 0 <= candidate <= 100:
                    utilization = candidate
                    break
        gpu: dict[str, Any] = {"name": gpu_name, "backend": "Metal" if metal else "IOKit"}
        if utilization is not None:
            gpu["utilization"] = round(utilization, 2)
        data["gpus"] = [gpu]
        data["accelerators"].append({"type": "gpu", "name": gpu_name, "backend": "Metal" if metal else None, "available": True})
        if metal:
            data["metal"] = {"available": True}

        # Every Apple M-series SoC includes an Apple Neural Engine. Public macOS APIs do
        # not expose stable global ANE utilization, so availability != utilization.
        if apple_silicon:
            data["ane"] = {"available": True, "utilization": None}
            data["accelerators"].append({"type": "npu", "name": "Apple Neural Engine", "backend": "Core ML", "available": True})

        therm = _command(["pmset", "-g", "therm"], timeout=3)
        limits: dict[str, float] = {}
        for label, key in (("CPU_Speed_Limit", "cpuSpeedLimit"), ("CPU_Scheduler_Limit", "cpuSchedulerLimit")):
            match = re.search(label + r"\s*=\s*(\d+)", therm)
            if match:
                value = float(match.group(1))
                if 0 <= value <= 100:
                    limits[key] = value
        if limits:
            data["thermalLimits"] = limits
        return data
