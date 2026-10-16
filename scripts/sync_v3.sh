#!/usr/bin/env bash
#
# Nightly Phase R sync: public -> v3, then check they are equal. Phase R.2.
#
# Production writers keep writing public until the R.6 merge. This copies their work into the
# v3 tables and proves v3 still equals public (scripts/sync_v3.sql). A failed check rolls the
# night back, so v3 is never left half-synced.
#
# Same signals as bin/drift_cron.sh (this host has no MTA):
#
#   ~/log/genomes_db_sync_v3.log           every run, pass or fail
#   ~/log/genomes_db_sync_v3.log.FAILING   exists only while the last run failed
#
# Install with `crontab -e`, after the 18:00 UTC import:
#
#     30 18 * * * /home/tyler/genomes_db_review/scripts/sync_v3.sh
#
# Credentials are resolved by bin/apply_migrations.py's psql_base(): $DATABASE_URL, then DB_*,
# then ~/postgresql_details/oceanomics.cfg. Nothing is written to the log.
#
# Remove the cron line at the R.6 merge.

set -uo pipefail

export PATH=/usr/local/bin:/usr/bin:/bin
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
LOG=${SYNC_V3_LOG:-$HOME/log/genomes_db_sync_v3.log}
FAILFILE=$LOG.FAILING

mkdir -p -- "$(dirname -- "$LOG")"
echo "=== sync_v3.sh  $(date -Is)  host=$(hostname -s)" >>"$LOG"

out=$(mktemp) || exit 1
trap 'rm -f -- "$out"' EXIT

python3 - "$REPO" >"$out" 2>&1 <<'PY'
import os, subprocess, sys
repo = sys.argv[1]
sys.path.insert(0, os.path.join(repo, "bin"))
import apply_migrations
argv, env = apply_migrations.psql_base()
sys.exit(subprocess.run(argv + ["-X", "-q", "-f", os.path.join(repo, "scripts", "sync_v3.sql")],
                        env=env).returncode)
PY
status=$?

cat -- "$out" >>"$LOG"
if [ "$status" -ne 0 ]; then
    {
        echo "Phase R v3 sync FAILED at $(date -Is). v3 is as of the last good run."
        echo "Full log: $LOG"
        echo "Runbook:  $REPO/docs/assembly_relations_runbook_r0_r5.md (R.2)"
    } | tee -- "$FAILFILE"
else
    rm -f -- "$FAILFILE"
fi
exit "$status"
