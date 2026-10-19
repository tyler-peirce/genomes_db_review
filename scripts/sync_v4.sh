#!/usr/bin/env bash
#
# Nightly Phase RG sync: public -> v4, then check they are equal. Phase RG.1.
#
# Production writers keep writing public until the RG.6 swap. This copies their work into the
# v4 tables and proves v4 still equals public (scripts/sync_v4.sql). A failed check rolls the
# night back, so v4 is never left half-synced.
#
# Same signals as bin/drift_cron.sh (this host has no MTA):
#
#   ~/log/genomes_db_sync_v4.log           every run, pass or fail
#   ~/log/genomes_db_sync_v4.log.FAILING   exists only while the last run failed
#
# Install with `crontab -e`, after the 18:00 UTC import and the 18:30 sync_v3:
#
#     0 19 * * * /home/tyler/genomes_db_review/scripts/sync_v4.sh
#
# Credentials are resolved by bin/apply_migrations.py's psql_base(): $DATABASE_URL, then DB_*,
# then ~/postgresql_details/oceanomics.cfg. Nothing is written to the log.
#
# Remove the cron line at the RG.6 swap.

set -uo pipefail

export PATH=/usr/local/bin:/usr/bin:/bin
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
LOG=${SYNC_V4_LOG:-$HOME/log/genomes_db_sync_v4.log}
FAILFILE=$LOG.FAILING

mkdir -p -- "$(dirname -- "$LOG")"
echo "=== sync_v4.sh  $(date -Is)  host=$(hostname -s)" >>"$LOG"

out=$(mktemp) || exit 1
trap 'rm -f -- "$out"' EXIT

python3 - "$REPO" >"$out" 2>&1 <<'PY'
import os, subprocess, sys
repo = sys.argv[1]
sys.path.insert(0, os.path.join(repo, "bin"))
import apply_migrations
argv, env = apply_migrations.psql_base()
sys.exit(subprocess.run(argv + ["-X", "-q", "-f", os.path.join(repo, "scripts", "sync_v4.sql")],
                        env=env).returncode)
PY
status=$?

cat -- "$out" >>"$LOG"
if [ "$status" -ne 0 ]; then
    {
        echo "Phase RG v4 sync FAILED at $(date -Is). v4 is as of the last good run."
        echo "Full log: $LOG"
        echo "Runbook:  $REPO/docs/ref_genomes_runbook_rg0_rg5.md (RG.1)"
    } | tee -- "$FAILFILE"
else
    rm -f -- "$FAILFILE"
fi
exit "$status"
