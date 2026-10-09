#!/usr/bin/env python3
# SPDX-License-Identifier: BUSL-1.1
"""Explicit, checksum-verified local updater for the Vytrix fleet entry point.

This is never invoked by the monitor itself. Operators must run it intentionally.
"""
import argparse, json, os, shutil, tempfile
from pathlib import Path
import importlib.util
HERE=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location("fleet_probe",HERE/"agent/fleet.py");m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
p=argparse.ArgumentParser();p.add_argument("manifest");p.add_argument("candidate");p.add_argument("target");args=p.parse_args()
manifest=json.loads(Path(args.manifest).read_text())
if not m.verify_update_manifest(manifest,args.candidate):raise SystemExit("checksum verification failed")
target=Path(args.target);target.parent.mkdir(parents=True,exist_ok=True);backup=target.with_suffix(target.suffix+".bak")
if target.exists():shutil.copy2(target,backup)
tmp=target.with_suffix(target.suffix+".new");shutil.copy2(args.candidate,tmp);os.replace(tmp,target)
print("installed",target,"backup",backup if backup.exists() else "none")
