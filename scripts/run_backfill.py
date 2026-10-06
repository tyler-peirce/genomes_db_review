#!/usr/bin/env python3
"""Run scripts/backfill_v2.sql against the configured database (Phase V.4).

Why this exists
---------------
The backfill is plain SQL, and bare `psql` does not read the credentials file every other
tool here uses. This runs it through bin/apply_migrations.py's psql_base(), so the target is
resolved exactly as the migration runner resolves it -- $DATABASE_URL, then DB_* variables,
then ~/postgresql_details/oceanomics.cfg -- with ON_ERROR_STOP, and prints the target first.

It is deliberately NOT a migration (docs/phase_v3_plan.md decision 1): it needs
`import_v2.py --stage-attempt-keys` first, and it is meant to be re-run while the lab fixes
rows. The script is idempotent: a second run inserts nothing new.

After the first run on a database, check it with scripts/reconcile_v2.py BEFORE any
import_v2.py run (see that script's docstring for why the order matters).

Usage
-----
    scripts/run_backfill.py
"""

from __future__ import annotations

import importlib.util
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location(
    "apply_migrations", REPO / "bin" / "apply_migrations.py")
_am = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_am)

BACKFILL = REPO / "scripts" / "backfill_v2.sql"


def main() -> int:
    target = _am.query("SELECT current_database(), "
                       "coalesce(inet_server_addr()::text, 'local socket')")[0]
    print(f"Backfilling v2 on {target[0]} @ {target[1]}", flush=True)
    argv, env = _am.psql_base()
    argv += ["-X", "-v", "ON_ERROR_STOP=1", "-f", str(BACKFILL)]
    return subprocess.run(argv, env=env).returncode


if __name__ == "__main__":
    sys.exit(main())
