#!/usr/bin/env bash
#
# Daily schema-governance check. Phase B.4.
#
# Runs the two checks that answer "does the database still match source
# control?" and mails only when one of them fails, so a healthy day is silent:
#
#   bin/check_drift.py              live tables/views vs schema/object_inventory.tsv
#   bin/apply_migrations.py --verify  every applied file's SHA-256 vs the ledger
#
# Everything is appended to the log either way; stdout is produced only on
# failure, which is what cron would turn into mail.
#
# NOTE: this host has no MTA -- no sendmail, no mail binary, postfix inactive --
# so cron mail goes nowhere. Until one is configured, the two durable signals
# are the log and the status file:
#
#   ~/log/genomes_db_drift.log      every run, pass or fail
#   ~/log/genomes_db_drift.FAILING  exists only while the last run failed
#
# The status file is what makes this check noticeable without mail. Check it
# from a shell prompt, a login banner, or a monitoring agent.
#
# Install with `crontab -e`:
#
#     17 7 * * * /home/tyler/genomes_db_review/bin/drift_cron.sh
#
# Credentials come from ~/postgresql_details/oceanomics.cfg, resolved by the two
# Python scripts themselves -- nothing is passed on the command line and nothing
# is written to the log. Cron gives you almost no environment, so PATH is set
# below; everything else the scripts find for themselves.
#
# Host cron rather than CI on purpose: GitHub runners cannot reach the database
# host, and giving them access would mean committing credentials, which is what
# Finding 14 undid.

set -uo pipefail

export PATH=/usr/local/bin:/usr/bin:/bin
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
LOG=${DRIFT_LOG:-$HOME/log/genomes_db_drift.log}
FAILFILE=$LOG.FAILING

mkdir -p -- "$(dirname -- "$LOG")"

out=$(mktemp) || exit 1
trap 'rm -f -- "$out"' EXIT

status=0
{
    echo "=============================================================="
    echo "drift_cron.sh  $(date -Is)  host=$(hostname -s)"
} >>"$LOG"

for check in "check_drift.py" "apply_migrations.py --verify"; do
    # shellcheck disable=SC2086
    if ! "$REPO"/bin/${check} >"$out" 2>&1; then
        status=1
        {
            echo "--- FAILED: bin/$check"
            cat -- "$out"
        } | tee -a "$LOG"
    else
        {
            echo "--- ok: bin/$check"
            cat -- "$out"
        } >>"$LOG"
    fi
done

if [ "$status" -ne 0 ]; then
    {
        echo "Schema governance check FAILED at $(date -Is)."
        echo "Full log: $LOG"
        echo "Runbook:  $REPO/docs/database_change_checklist.md (Migration Governance)"
    } | tee -- "$FAILFILE"
else
    # Healthy: clear the marker so a stale failure does not look current.
    rm -f -- "$FAILFILE"
fi

exit "$status"
