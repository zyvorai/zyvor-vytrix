#!/usr/bin/env python3
# SPDX-License-Identifier: BUSL-1.1
"""Drop-in Vytrix collector with advanced and fleet enrichment."""
from __future__ import annotations
from pathlib import Path
import importlib.util
import sys

HERE = Path(__file__).resolve().parent

def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module

base = load("vytrix", HERE / "vytrix.py")
advanced = load("vytrix_advanced", HERE / "advanced.py")
fleet = load("vytrix_fleet_probe", HERE / "fleet.py")
BaseCollector = base.Collector

class FleetCollector(BaseCollector):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._advanced = advanced.AdvancedProbe(getattr(self, "proc", "/proc"), getattr(self, "linux", None))
        self._fleet = fleet.FleetProbe()

    def snapshot(self):
        sample = super().snapshot()
        sample = self._advanced.enrich(sample)
        return self._fleet.enrich(sample)

base.Collector = FleetCollector

if __name__ == "__main__":
    base.main()
