#!/usr/bin/env bash
#
# Daily schema-governance check. Phase B.4.
#
# Runs the two checks that answer "does the database still match source
# control?":
#
#   bin/check_drift.py              live tables/views vs schema/object_inventory.tsv
#   bin/apply_migrations.py --verify  every applied file's SHA-256 vs the ledger
#
# Everything is appended to the log either way. Stdout -- which cron mails to
# MAILTO via msmtp-mta (ops/README.md) -- is produced only when the state
# changes: the first failing run, and the first healthy run after a failure.
# A check that is left failing on purpose (open question 16) therefore mails
# once, not every morning.
#
# The durable signals are the log and the status file:
#
#   ~/log/genomes_db_drift.log           every run, pass or fail
#   ~/log/genomes_db_drift.log.FAILING   exists only while the last run failed
#   /var/lib/genomes-db/drift.FAILING    the same marker, readable by every user
#
# The shared copy is what the login banner reads (ops/genomes-db-status, run
# from the MOTD and /etc/bash.bashrc), since other users cannot read ~tyler.
# If that directory is missing or not writable the shared copy is skipped. See
# ops/README.md.
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
STATUS_DIR=${DRIFT_STATUS_DIR:-/var/lib/genomes-db}
SHAREDFAIL=$STATUS_DIR/drift.FAILING

mkdir -p -- "$(dirname -- "$LOG")"

# Was the previous run failing? Decides whether this run's result is news.
was_failing=0
[ -e "$FAILFILE" ] && was_failing=1

out=$(mktemp) || exit 1
fails=$(mktemp) || exit 1
trap 'rm -f -- "$out" "$fails"' EXIT

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
        } | tee -a "$LOG" >>"$fails"
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
    } >"$FAILFILE"
    [ -w "$STATUS_DIR" ] && cp -- "$FAILFILE" "$SHAREDFAIL"
    # Newly failing: say so, with this run's failures, for cron mail.
    if [ "$was_failing" -eq 0 ]; then
        cat -- "$FAILFILE"
        echo
        cat -- "$fails"
    fi
else
    # Healthy: clear the marker so a stale failure does not look current.
    rm -f -- "$FAILFILE"
    [ -w "$STATUS_DIR" ] && rm -f -- "$SHAREDFAIL"
    if [ "$was_failing" -eq 1 ]; then
        echo "Schema governance check RECOVERED at $(date -Is). Both checks pass."
        echo "Full log: $LOG"
    fi
fi

exit "$status"
