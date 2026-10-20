#!/usr/bin/env python3
# SPDX-License-Identifier: BUSL-1.1
"""Explicit, checksum-verified local updater for the Vytrix fleet entry point.

This is never invoked by the monitor itself. Operators must run it intentionally.
"""
import argparse, json, os, shutil, tempfile
from pathlib import Path
import importlib.util
HERE=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location("fleet_probe",HERE/"agent/fleet.py")
if spec is None or spec.loader is None:raise SystemExit("cannot load agent/fleet.py")
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
p=argparse.ArgumentParser();p.add_argument("manifest");p.add_argument("candidate");p.add_argument("target");args=p.parse_args()
manifest=json.loads(Path(args.manifest).read_text())
target=Path(args.target);target.parent.mkdir(parents=True,exist_ok=True)
# Read the candidate once, write those exact bytes to an unpredictable temp file (mkstemp does not
# follow a pre-planted symlink), then verify the staged copy that will actually be installed.
data=Path(args.candidate).read_bytes()
fd,tmp=tempfile.mkstemp(prefix=target.name+".",suffix=".new",dir=target.parent)
try:
    with os.fdopen(fd,"wb") as f:f.write(data)
    os.chmod(tmp,0o755)
    if not m.verify_update_manifest(manifest,tmp):raise SystemExit("checksum verification failed")
    backup=target.with_suffix(target.suffix+".bak")
    if target.exists():shutil.copy2(target,backup)
    os.replace(tmp,target)
finally:
    if os.path.exists(tmp):os.unlink(tmp)
print("installed",target,"backup",backup if backup.exists() else "none")
