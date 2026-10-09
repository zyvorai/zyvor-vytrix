#!/usr/bin/env python3
# SPDX-License-Identifier: BUSL-1.1
"""Drop-in cluster worker using the complete Vytrix fleet collector."""
from pathlib import Path
import importlib.util
import sys

HERE = Path(__file__).resolve().parent

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None: raise RuntimeError(f"Cannot load {path}")
    module = importlib.util.module_from_spec(spec); sys.modules[name] = module; spec.loader.exec_module(module); return module

fleet_entry = load("vytrix_fleet_entry", HERE / "vytrix_fleet.py")
# cluster_worker imports `Collector` from module name vytrix.
base = sys.modules["vytrix"]
base.Collector = fleet_entry.FleetCollector
worker = load("vytrix_cluster_worker", HERE / "cluster_worker.py")

if __name__ == "__main__":
    worker.main()
