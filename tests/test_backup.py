# SPDX-License-Identifier: BUSL-1.1
import sqlite3, subprocess, sys, tempfile, unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / 'cluster' / 'backup.py'


class BackupTests(unittest.TestCase):
    def run_backup(self, db, out):
        return subprocess.run([sys.executable, str(SCRIPT), str(db), str(out)], capture_output=True, text=True)

    def test_backs_up_existing_database(self):
        with tempfile.TemporaryDirectory() as d:
            db, out = Path(d) / 'a.db', Path(d) / 'out' / 'b.db'
            c = sqlite3.connect(db); c.execute('create table t(x)'); c.execute('insert into t values (7)'); c.commit(); c.close()
            r = self.run_backup(db, out)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertEqual(sqlite3.connect(out).execute('select x from t').fetchone(), (7,))

    def test_missing_database_fails_and_creates_nothing(self):
        with tempfile.TemporaryDirectory() as d:
            db, out = Path(d) / 'typo.db', Path(d) / 'b.db'
            r = self.run_backup(db, out)
            self.assertNotEqual(r.returncode, 0)
            self.assertFalse(db.exists())
            self.assertFalse(out.exists())


if __name__ == '__main__':
    unittest.main()
