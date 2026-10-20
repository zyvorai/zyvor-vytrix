#!/usr/bin/env python3
# SPDX-License-Identifier: BUSL-1.1
"""Online SQLite backup tool for Vytrix coordinator HA/DR workflows."""
import argparse, os, sqlite3, tempfile
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('database');p.add_argument('output');args=p.parse_args();src=sqlite3.connect(Path(args.database).resolve().as_uri()+'?mode=ro',uri=True);dst_path=Path(args.output);dst_path.parent.mkdir(parents=True,exist_ok=True)
fd,tmp=tempfile.mkstemp(prefix=dst_path.name+'.',dir=dst_path.parent);os.close(fd)
try:
 dst=sqlite3.connect(tmp)
 try:src.backup(dst)
 finally:dst.close()
 os.chmod(tmp,0o600);os.replace(tmp,dst_path);print(dst_path)
finally:
 src.close()
 if os.path.exists(tmp):os.unlink(tmp)
